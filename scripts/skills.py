#!/usr/bin/env python3
"""Synchronize the governance repository's global Skills allowlist."""

import argparse
import fcntl
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

sys.dont_write_bytecode = True
from skills_store import Store, content_key, inside, path_key, read_json


REPO = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPO / "skills"
TARGETS = {
    "codex": (None, ".agents/skills", ""),
    "claude-code": ("CLAUDE_CONFIG_DIR", ".claude", "skills"),
    "pi": ("PI_CODING_AGENT_DIR", ".pi/agent", "skills"),
    "opencode": ("XDG_CONFIG_HOME", ".config", "opencode/skills"),
    "dsh": ("DSH_HOME", ".dsh", "skills"),
    "command-code": (None, ".commandcode/skills", ""),
    "omp": (None, ".omp/agent", "skills"),
    "workbuddy-ai": ("WORKBUDDY_CONFIG_DIR", ".workbuddy-ai", "skills"),
}
NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
CHANGES = {"install", "update", "adopt"}
READY = {"ready", "reuse"}


@dataclass
class Skill:
    name: str
    source: dict
    local: Path
    key: list


@dataclass
class Target:
    identifier: str
    skill: Skill
    path: Path
    current: list
    action: str


def skill_key(path, name):
    entry = path / "SKILL.md"
    if path.is_symlink() or any(part.is_symlink() for part in path.rglob("*")):
        raise ValueError(f"Skill 源目录须为独立文件，发现软链: {path}")
    if not entry.is_file() or not re.match(
        rf"\A---\n(?:[^\n]*\n)*?name:\s*{re.escape(name)}[ \t]*\n",
        entry.read_text(encoding="utf-8"),
    ):
        raise ValueError(f"SKILL.md 缺失或 name 与清单不一致: {entry}")
    return path_key(path)


def load_skills():
    manifest = read_json(SOURCE_ROOT / "manifest.json")
    skills = []
    for name, source in manifest["skills"].items():
        if not NAME.fullmatch(name):
            raise ValueError(f"无效的 Skill 名称: {name}")
        if source["type"] == "local":
            local = SOURCE_ROOT / "local" / name
            skills.append(Skill(name, source, local, skill_key(local, name)))
            continue
        if (
            source["type"] != "github"
            or not re.fullmatch(r"[a-zA-Z0-9][\w.-]*/[a-zA-Z0-9][\w.-]*", source["repo"], re.ASCII)
            or not re.fullmatch(r"[0-9a-f]{40}", source["commit"])
            or not re.fullmatch(r"[0-9a-f]{64}", source["digest"])
            or not re.fullmatch(rf"(?:[\w-]+/)+{re.escape(name)}", source["path"], re.ASCII)
        ):
            raise ValueError(f"无效的锁定来源: {name}")
        skills.append(Skill(name, source, None, ["directory", source["digest"]]))
    return skills, manifest.get("registryCli")


def prepare_sources(skills, cli, stage, proxy):
    sources = {}
    upstream = defaultdict(list)
    for skill in skills:
        if skill.local is None:
            upstream[(skill.source["repo"], skill.source["commit"])].append(skill)
        else:
            destination = stage / skill.name
            shutil.copytree(skill.local, destination, symlinks=True)
            sources[skill.name] = destination
    for index, ((repo, commit), entries) in enumerate(upstream.items()):
        if not cli or not re.fullmatch(r"\d+\.\d+\.\d+", cli):
            raise ValueError("清单需锁定 Vercel Skills CLI 版本")
        work = stage / f"upstream-{index}"
        work.mkdir()
        checkout = work / "checkout"
        extract_release(repo, commit, {skill.source["path"] for skill in entries}, checkout, proxy)
        subprocess.run(
            ["npm", "exec", "--yes", f"--package=skills@{cli}", "--", "skills", "add",
             str(checkout),
             "--skill", *(skill.name for skill in entries), "--agent", "codex", "--yes", "--copy"],
            cwd=work, env={**os.environ, "DISABLE_TELEMETRY": "1", "NPM_CONFIG_IGNORE_SCRIPTS": "true"},
            check=True, timeout=65,
        )
        for skill in entries:
            sources[skill.name] = work / ".agents" / "skills" / skill.name
    for skill in skills:
        if skill_key(sources[skill.name], skill.name) != skill.key:
            raise ValueError(f"Skill 文件与规划摘要不一致: {skill.name}")
    return sources


def extract_release(repo, commit, skill_paths, checkout, proxy):
    archive = checkout.parent / "source.tar.gz"
    url = f"https://codeload.github.com/{repo}/tar.gz/{commit}"
    command = ["curl", "-fsSL", "--connect-timeout", "8", "--max-time", "45"]
    if proxy:
        command.extend(["--proxy", proxy])
    result = subprocess.run([*command, "-o", str(archive), url], check=False, timeout=50)
    if result.returncode:
        raise ValueError(f"下载锁定的上游版本失败: {repo}@{commit} (curl {result.returncode})")
    prefix = f"{repo.split('/')[1]}-{commit}"
    with tarfile.open(archive) as bundle:
        for member in bundle:
            root, _, relative = member.name.partition("/")
            if root != prefix or not any(relative.startswith(path + "/") for path in skill_paths):
                continue
            parts = PurePosixPath(relative)
            if parts.is_absolute() or ".." in parts.parts:
                raise ValueError(f"无效的归档路径: {member.name}")
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"无效的归档文件类型: {member.name}")
            destination = checkout.joinpath(parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, destination.open("xb") as output:
                shutil.copyfileobj(source, output)
            destination.chmod(0o755 if member.mode & 0o111 else 0o644)


def roots_for(device, isolated):
    for tool, (env, default, suffix) in TARGETS.items():
        override = os.environ.get(env) if env and not isolated else None
        base = Path(override).expanduser() if override else device / default
        if tool == "opencode" and not isolated and os.environ.get("OPENCODE_CONFIG_DIR"):
            base = Path(os.environ["OPENCODE_CONFIG_DIR"]).expanduser()
            suffix = "skills"
        if tool == "omp" and not isolated:
            profile = os.environ.get("OMP_PROFILE", os.environ.get("PI_PROFILE", "")).strip()
            config_dir = device / (os.environ.get("PI_CONFIG_DIR") or ".omp")
            if profile and profile != "default":
                if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", profile) or profile.endswith("."):
                    raise ValueError(f"无效的 omp profile: {profile}")
                base = config_dir / "profiles" / profile / "agent"
            else:
                agent_dir = os.environ.get("PI_CODING_AGENT_DIR")
                base = Path(agent_dir).expanduser() if agent_dir else config_dir / "agent"
        if not base.is_absolute():
            raise ValueError(f"{tool} 的配置目录需要使用绝对路径: {base}")
        yield tool, (base / suffix).resolve()
    # Some Codex installations also expose this directory. Handle existing names
    # there without adding a second installation on clean devices.
    yield "codex-legacy", (device / ".codex/skills").resolve()


def make_plan(skills, roots, store, state, adopt):
    primary = {}
    targets = []
    for tool, root in roots:
        for skill in skills:
            path = store.destination(root / skill.name)
            current = path_key(path)
            if tool == "codex-legacy" and current is None:
                continue
            identifier = f"{tool}:{skill.name}"
            if current is None:
                action = "install"
            elif content_key(path) == skill.key:
                action = "ready" if state["managed"].get(str(path)) == current else "reuse"
            elif state["managed"].get(str(path)) == current:
                action = "update"
            elif identifier in adopt:
                action = "adopt"
            else:
                action = "conflict"
            existing = primary.get(path)
            if existing:
                if existing.action == "conflict" and action == "adopt":
                    existing.action = "adopt"
                if action in CHANGES or action == "conflict":
                    action = "shared"
            target = Target(identifier, skill, path, current, action)
            targets.append(target)
            primary.setdefault(path, target)
    for target in targets:
        if target.action not in {"conflict", "reuse", "adopt"} or not target.path.is_symlink():
            continue
        linked = primary.get(target.path.resolve())
        if linked and linked.action in CHANGES and linked.skill.name == target.skill.name:
            if target.action != "adopt":
                target.action = "linked"
    return targets


def report(targets, state):
    for target in targets:
        link = f" -> {target.path.readlink()}" if target.action == "conflict" and target.path.is_symlink() else ""
        print(f"{target.action:<9} {target.identifier:<31} {target.path}{link}")
    paths = {str(target.path) for target in targets}
    for path in sorted(set(state["managed"]) - paths):
        print(f"retained  {path}")


def sync(args, skills, cli, roots, store, state):
    selected = set(args.adopt)
    current_plan = make_plan(skills, roots, store, state, set())
    conflicts = {target.identifier for target in current_plan if target.action == "conflict"}
    if selected - conflicts:
        raise ValueError(f"--adopt 只接受预览中的冲突项: {', '.join(sorted(selected - conflicts))}")
    plan = make_plan(skills, roots, store, state, selected)
    report(plan, state)
    changes = [target for target in plan if target.action in CHANGES]
    if changes:
        with tempfile.TemporaryDirectory(prefix="governance-skills-") as temporary:
            changed_names = {target.skill.name for target in changes}
            sources = prepare_sources(
                [skill for skill in skills if skill.name in changed_names], cli, Path(temporary),
                args.proxy,
            )
            store.apply(
                [(target.path, sources[target.skill.name], target.current) for target in changes],
                state,
            )
        print(f"已同步 {len(changes)} 个路径。")
    return int(any(target.action == "conflict" for target in plan))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("plan", "status", "sync", "rollback"))
    parser.add_argument("--home", type=Path, help="用于隔离验证的用户目录")
    parser.add_argument("--proxy", help="获取 GitHub 源时使用的 HTTP 或 SOCKS 代理")
    parser.add_argument("--adopt", action="append", default=[], metavar="TOOL:SKILL")
    args = parser.parse_args()
    if (args.adopt or args.proxy) and args.command != "sync":
        parser.error("--adopt 和 --proxy 仅用于 sync")
    try:
        device = (args.home or Path.home()).resolve(strict=True)
        state_root = (device / ".local/state/agent-governance/skills").resolve()
        if not device.is_dir() or not inside(state_root, device):
            raise ValueError("用户目录或状态目录无效")
        allow_external = args.home is None and os.environ.get("AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS") == "1"
        store = Store(state_root, device, allow_external)
        if args.command != "rollback":
            skills, cli = load_skills()
            roots = list(roots_for(device, args.home is not None))
        if args.command in {"plan", "status"}:
            if store.pending.exists():
                raise ValueError("检测到中断的同步。运行 sync 或 rollback 恢复后再查看状态。")
            state = store.state()
            plan = make_plan(skills, roots, store, state, set())
            report(plan, state)
            return int(args.command == "status" and any(
                target.action not in READY | {"shared"} for target in plan
            ))

        state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (state_root / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            store.recover()
            state = store.state()
            if args.command == "rollback":
                print(f"已回退 {store.rollback(state)} 个路径。")
                return 0
            return sync(args, skills, cli, roots, store, state)
    except BlockingIOError:
        print("已有 Skills 同步正在执行。", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print(f"Skills: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
