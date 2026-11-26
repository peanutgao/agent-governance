import ctypes
import errno
import hashlib
import json
import os
import re
import shutil
import stat
import sys
from pathlib import Path
from uuid import uuid4


HEX_TX = re.compile(r"^[0-9a-f]{32}$")
DEFAULT_BACKUP_KEEP = 10


def backup_keep_limit():
    raw = os.environ.get("AGENT_GOVERNANCE_SKILLS_BACKUP_KEEP")
    if raw is None or raw == "":
        return DEFAULT_BACKUP_KEEP
    if not re.fullmatch(r"[1-9][0-9]*", raw):
        raise ValueError(f"AGENT_GOVERNANCE_SKILLS_BACKUP_KEEP 必须是正整数: {raw}")
    return int(raw)


def path_key(path, *, ignore_executable=os.name == "nt"):
    """Fingerprint a path without following links, including dangling links."""
    try:
        info = path.lstat()
        mode = info.st_mode
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(mode):
        return ["link", str(path.readlink())]
    if os.name == "nt" and info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
        raise ValueError(f"不支持的 Windows 重解析点: {path}")
    if stat.S_ISREG(mode):
        executable = 0 if ignore_executable else mode & 0o111
        return ["file", hashlib.sha256(path.read_bytes()).hexdigest(), executable]
    if stat.S_ISDIR(mode):
        entries = [[child.name, path_key(child, ignore_executable=ignore_executable)]
                   for child in sorted(path.iterdir(), key=lambda child: child.name)]
        return ["directory", hashlib.sha256(json.dumps(entries).encode()).hexdigest()]
    raise ValueError(f"不支持的文件类型: {path}")


def content_key(path):
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    return path_key(resolved) if resolved.is_dir() else None


def copy_path(source, destination):
    if source.is_symlink():
        destination.symlink_to(source.readlink())
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)


def remove_tree(path):
    """Remove a directory tree even when it contains read-only files or directories."""
    root = Path(path)

    def handle_readonly(func, failed, exc):
        if not isinstance(exc, PermissionError) or func not in (os.unlink, os.rmdir, os.remove):
            raise exc
        target = Path(failed)
        parent = target.parent
        if inside(parent, root) and not parent.is_symlink():
            os.chmod(parent, 0o700)
        if inside(target, root) and not target.is_symlink():
            os.chmod(target, 0o700 if target.is_dir() else 0o600)
        func(failed)

    if sys.version_info >= (3, 12):
        shutil.rmtree(root, onexc=handle_readonly)
    else:
        def handle_onerror(func, failed, exc_info):
            handle_readonly(func, failed, exc_info[1])

        shutil.rmtree(root, onerror=handle_onerror)


def publish_path(staged, destination):
    """Move atomically without silently replacing an external writer's path."""
    if os.name == "nt":
        os.rename(staged, destination)
        return
    libc = ctypes.CDLL(None, use_errno=True)
    source, target = os.fsencode(staged), os.fsencode(destination)
    if sys.platform == "darwin":
        # <sys/stdio.h> RENAME_EXCL
        renamex = libc.renamex_np
        renamex.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        renamex.restype = ctypes.c_int
        result = renamex(source, target, 0x00000004)
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        # <fcntl.h> AT_FDCWD and <linux/fs.h> RENAME_NOREPLACE
        renameat2 = libc.renameat2
        renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        renameat2.restype = ctypes.c_int
        result = renameat2(-100, source, -100, target, 1)
    else:
        raise ValueError("当前平台缺少原子无覆盖重命名支持")
    if result:
        error = ctypes.get_errno()
        if sys.platform.startswith("linux") and error in {errno.EINVAL, errno.ENOSYS, errno.EOPNOTSUPP}:
            raise OSError(
                error,
                f"当前文件系统不支持 renameat2(RENAME_NOREPLACE): {os.strerror(error)}",
                str(destination),
            )
        raise OSError(error, os.strerror(error), str(destination))


def lock_file(lock):
    if os.name == "nt":
        import msvcrt

        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as error:
            if error.errno not in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                raise
            raise BlockingIOError(error.errno, error.strerror) from error
    else:
        import fcntl

        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


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
        if not path.is_absolute() or ".." in path.parts:
            raise ValueError(f"目标路径必须是无路径跳转的绝对路径: {path}")
        parent = path.parent
        if not self.allow_external and not inside(parent, self.device):
            raise ValueError(f"目标目录越出用户目录: {path}")
        # 与 distribute.sh 一致：拒绝用户目录之下任何一层父目录是软链，防止静默穿越或越界写入。
        stop = self.device if inside(parent, self.device) else Path(parent.anchor)
        cursor = parent
        while cursor != stop and cursor != Path(cursor.anchor):
            if cursor.is_symlink():
                raise ValueError(f"目标父目录包含软链: {cursor}")
            if cursor.exists() and not cursor.is_dir():
                raise ValueError(f"目标父目录不是普通目录: {cursor}")
            cursor = cursor.parent
        resolved_parent = parent.resolve()
        if resolved_parent != parent or inside(resolved_parent, self.root):
            raise ValueError(f"目标父目录已改变或指向同步状态目录: {path}")
        if not self.allow_external and not inside(resolved_parent, self.device):
            raise ValueError(f"目标目录越出用户目录: {path}")
        return path

    def snapshot(self, transaction):
        if not isinstance(transaction, str) or not HEX_TX.fullmatch(transaction):
            raise ValueError("无效的 Skills 快照编号")
        return self.root / transaction

    def replace(self, path, source, expected, staging):
        path = self.destination(path)
        if source is None and expected is None:
            if path_key(path) is not None:
                raise ValueError(f"同步期间路径发生变化: {path}")
            return
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
            remove_tree(staging)
            raise
        else:
            remove_tree(staging)

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
                remove_tree(recovering)
            if actual != entry["before"]:
                self.replace(path, backup, actual, recovering)
            if staging.exists():
                remove_tree(staging)
        self.pending.unlink()
        remove_tree(snapshot)

    def prune_snapshots(self, latest_tx):
        keep = backup_keep_limit()
        kept = []
        cursor = latest_tx
        seen = set()
        while cursor is not None and len(kept) < keep:
            if cursor in seen:
                break
            seen.add(cursor)
            snap = self.snapshot(cursor)
            record_path = snap / "record.json"
            if not record_path.is_file():
                break
            kept.append((cursor, snap, read_json(record_path)))
            cursor = kept[-1][2]["state"].get("latest")

        if kept and cursor is not None:
            # 截断保留链表尾节点，避免连续 rollback 追踪到已被裁剪的快照而报 FileNotFoundError。
            _, tail_snap, tail_record = kept[-1]
            tail_state = dict(tail_record["state"])
            tail_state["latest"] = None
            write_json(tail_snap / "record.json", {**tail_record, "state": tail_state})

        kept_names = {tx for tx, _, _ in kept}
        for child in self.root.iterdir():
            if child.is_dir() and not child.is_symlink() and HEX_TX.fullmatch(child.name):
                if child.name not in kept_names:
                    remove_tree(child)

    def apply(self, changes, state, rollback_to=None):
        if rollback_to is None:
            backup_keep_limit()
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
                remove_tree(snapshot)
            raise
        try:
            for index, (path, source, expected) in enumerate(changes):
                staging = path.parent / f".gov-skill-{transaction}-{index}"
                self.replace(path, source, expected, staging)
            if rollback_to is None:
                managed = dict(state["managed"])
                for entry in entries:
                    if entry["after"] is None:
                        managed.pop(entry["path"], None)
                    else:
                        managed[entry["path"]] = entry["after"]
                next_state = {"managed": managed, "latest": transaction}
            else:
                next_state = dict(rollback_to)
            write_json(self.state_path, {**next_state, "applied": transaction})
        except BaseException:
            self.recover()
            raise
        self.pending.unlink()
        if rollback_to is not None:
            remove_tree(snapshot)
            remove_tree(self.snapshot(state["latest"]))
        else:
            self.prune_snapshots(next_state["latest"])

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
