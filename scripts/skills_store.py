import ctypes
import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path
from uuid import uuid4


def path_key(path):
    """Fingerprint a path without following links, including dangling links."""
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(mode):
        return ["link", str(path.readlink())]
    if stat.S_ISREG(mode):
        return ["file", hashlib.sha256(path.read_bytes()).hexdigest(), mode & 0o111]
    if stat.S_ISDIR(mode):
        entries = [[child.name, path_key(child)] for child in sorted(path.iterdir())]
        return ["directory", hashlib.sha256(json.dumps(entries).encode()).hexdigest()]
    raise ValueError(f"不支持的文件类型: {path}")


def content_key(path):
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError):
        return None
    return path_key(resolved) if resolved.is_dir() else None


def copy_path(source, destination):
    if source.is_symlink():
        destination.symlink_to(source.readlink())
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)


def publish_path(staged, destination):
    """Move atomically without silently replacing an external writer's path."""
    libc = ctypes.CDLL(None, use_errno=True)
    source, target = os.fsencode(staged), os.fsencode(destination)
    if sys.platform == "darwin":
        # <sys/stdio.h> RENAME_EXCL
        result = libc.renamex_np(source, target, 0x00000004)
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        # <fcntl.h> AT_FDCWD and <linux/fs.h> RENAME_NOREPLACE
        result = libc.renameat2(-100, source, -100, target, 1)
    else:
        raise ValueError("当前平台缺少原子无覆盖重命名支持")
    if result:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def write_json(path, data):
    temporary = path.with_name(f".{path.name}-{uuid4().hex}")
    try:
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def inside(path, parent):
    return path == parent or parent in path.parents


class Store:
    def __init__(self, root, device, allow_external=False):
        self.root = root
        self.device = device
        self.allow_external = allow_external
        self.pending = root / "pending.json"
        self.state_path = root / "state.json"

    def state(self):
        if self.state_path.exists():
            return read_json(self.state_path)
        return {"managed": {}, "latest": None, "applied": None}

    def destination(self, path):
        path = Path(path)
        parent = path.parent.resolve()
        if parent != path.parent or inside(parent, self.root):
            raise ValueError(f"目标父目录已改变或指向同步状态目录: {path}")
        if not self.allow_external and not inside(parent, self.device):
            raise ValueError(f"目标目录越出用户目录: {path}")
        return path

    def snapshot(self, transaction):
        if not isinstance(transaction, str) or len(transaction) != 32 or any(
            c not in "0123456789abcdef" for c in transaction
        ):
            raise ValueError("无效的 Skills 快照编号")
        return self.root / transaction

    def replace(self, path, source, expected, staging):
        path = self.destination(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        staging.mkdir()
        old = staging / "old"
        try:
            if source is not None:
                copy_path(source, staging / "new")
            self.destination(path)
            if path_key(path) != expected:
                raise ValueError(f"同步期间路径发生变化: {path}")
            if expected is not None:
                publish_path(path, old)
                if path_key(old) != expected:
                    raise ValueError(f"移动时路径发生变化: {path}")
            if source is not None:
                publish_path(staging / "new", path)
        except BaseException as error:
            if old.exists() or old.is_symlink():
                if path.exists() or path.is_symlink():
                    raise ValueError(f"路径被外部程序占用，原文件保留在 {old}: {path}") from error
                publish_path(old, path)
            shutil.rmtree(staging)
            raise
        else:
            shutil.rmtree(staging)

    def recover(self):
        if not self.pending.exists():
            return
        transaction = read_json(self.pending)
        snapshot = self.snapshot(transaction)
        if self.state()["applied"] == transaction:
            self.pending.unlink()
            return
        record = read_json(snapshot / "record.json")
        recovery = []
        for index, entry in enumerate(record["entries"]):
            path = self.destination(entry["path"])
            actual = path_key(path)
            staging = path.parent / f".gov-skill-{transaction}-{index}"
            recovering = staging.with_name(staging.name + "-restore")
            moved = [path_key(temp / "old") for temp in (staging, recovering)]
            if any(key not in (None, entry["before"], entry["after"]) for key in moved):
                raise ValueError(f"暂存原件出现外部变更，已保留 {staging} 和 {recovering}: {path}")
            if actual != entry["before"] and actual != entry["after"]:
                interrupted_move = actual is None and any(key is not None for key in moved)
                if not interrupted_move:
                    raise ValueError(f"检测到中断后的外部变更，已保留快照 {snapshot}: {path}")
            backup = snapshot / str(index) if entry["before"] is not None else None
            if backup is not None and path_key(backup) != entry["before"]:
                raise ValueError(f"快照内容不一致: {backup}")
            recovery.append((entry, path, actual, backup, staging, recovering))
        for entry, path, actual, backup, staging, recovering in recovery:
            if recovering.exists():
                shutil.rmtree(recovering)
            if actual != entry["before"]:
                self.replace(path, backup, actual, recovering)
            if staging.exists():
                shutil.rmtree(staging)
        self.pending.unlink()
        shutil.rmtree(snapshot)

    def apply(self, changes, state, rollback_to=None):
        transaction = uuid4().hex
        snapshot = self.snapshot(transaction)
        snapshot.mkdir(mode=0o700)
        entries = []
        try:
            for index, (path, source, expected) in enumerate(changes):
                path = self.destination(path)
                if path_key(path) != expected:
                    raise ValueError(f"同步期间路径发生变化: {path}")
                if expected is not None:
                    copy_path(path, snapshot / str(index))
                    if path_key(snapshot / str(index)) != expected:
                        raise ValueError(f"备份期间路径发生变化: {path}")
                entries.append({"path": str(path), "before": expected,
                                "after": path_key(source) if source is not None else None})
            write_json(snapshot / "record.json", {"state": state, "entries": entries})
            write_json(self.pending, transaction)
        except BaseException:
            if not self.pending.exists():
                shutil.rmtree(snapshot)
            raise
        try:
            for index, (path, source, expected) in enumerate(changes):
                staging = path.parent / f".gov-skill-{transaction}-{index}"
                self.replace(path, source, expected, staging)
            if rollback_to is None:
                managed = dict(state["managed"])
                managed.update({entry["path"]: entry["after"] for entry in entries})
                next_state = {"managed": managed, "latest": transaction}
            else:
                next_state = dict(rollback_to)
            write_json(self.state_path, {**next_state, "applied": transaction})
        except BaseException:
            self.recover()
            raise
        self.pending.unlink()
        if rollback_to is not None:
            shutil.rmtree(snapshot)
            shutil.rmtree(self.snapshot(state["latest"]))

    def rollback(self, state):
        if state["latest"] is None:
            raise ValueError("没有可回退的 Skills 同步")
        snapshot = self.snapshot(state["latest"])
        record = read_json(snapshot / "record.json")
        changes = []
        for index, entry in enumerate(record["entries"]):
            path = self.destination(entry["path"])
            backup = snapshot / str(index) if entry["before"] is not None else None
            if backup is not None and path_key(backup) != entry["before"]:
                raise ValueError(f"快照内容不一致: {backup}")
            changes.append((path, backup, entry["after"]))
        self.apply(changes, state, rollback_to=record["state"])
        return len(changes)
