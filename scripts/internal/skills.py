#!/usr/bin/env python3
"""Synchronize the governance repository's global Skills allowlist."""

import argparse
import concurrent.futures
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
from skills_store import Store, content_key, inside, lock_file, path_key, read_json


REPO = Path(__file__).resolve().parents[2]
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
EXCLUDE_FILES = frozenset({"metadata.json"})
EXCLUDE_DIRS = frozenset({".git", "__pycache__", "__pypackages__"})
SKIP_SCAN_DIRS = frozenset({".git", "node_modules", "__pycache__", "__pypackages__"})
PRIORITY_SEARCH_DIRS = (
    "skills",
    "skills/.curated",
    "skills/.experimental",
    "skills/.system",
    ".agents/skills",
)


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
        path = source["path"]
        upstream_name = source.get("upstreamName", name)
        if (
            source["type"] != "github"
            or not re.fullmatch(r"[a-zA-Z0-9][\w.-]*/[a-zA-Z0-9][\w.-]*", source["repo"], re.ASCII)
            or not re.fullmatch(r"[0-9a-f]{40}", source["commit"])
            or not re.fullmatch(r"[0-9a-f]{64}", source["digest"])
            or not NAME.fullmatch(upstream_name)
            or (path != "." and (
                "upstreamName" in source
                or not re.fullmatch(rf"(?:[\w-]+/)+{re.escape(name)}", path, re.ASCII)
            ))
        ):
            raise ValueError(f"无效的锁定来源: {name}")
        windows_digest = source.get("windowsDigest", source["digest"])
        if not re.fullmatch(r"[0-9a-f]{64}", windows_digest):
            raise ValueError(f"无效的 Windows 摘要: {name}")
        digest = windows_digest if os.name == "nt" else source["digest"]
        skills.append(Skill(name, source, None, ["directory", digest]))
    return skills


def frontmatter_name(entry):
    text = entry.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    metadata, delimiter, _ = text.partition("\n---\n")
    if not metadata.startswith("---\n") or not delimiter:
        return None
    names = re.findall(r"^name:[ \t]*([^\n]*?)[ \t]*$", metadata, re.MULTILINE)
    if len(names) != 1:
        return None
    value = names[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1].strip()
    return value


def scan_skill_matches(base, upstream_name, max_depth=None):
    matches = []
    base_depth = len(base.parts)
    for root, dirs, files in os.walk(base):
        current = Path(root)
        depth = len(current.parts) - base_depth
        dirs[:] = sorted(d for d in dirs if d not in SKIP_SCAN_DIRS)
        if "SKILL.md" in files and frontmatter_name(current / "SKILL.md") == upstream_name:
            matches.append(current)
            dirs[:] = []
            continue
        if max_depth is not None and depth >= max_depth:
            dirs[:] = []
    return matches


def find_skill_dir(checkout, skill_path, upstream_name):
    if skill_path != ".":
        candidate = checkout / skill_path
        if not (candidate / "SKILL.md").is_file():
            raise ValueError(f"上游归档缺少 SKILL.md: {skill_path}")
        return candidate
    if (checkout / "SKILL.md").is_file() and frontmatter_name(checkout / "SKILL.md") == upstream_name:
        return checkout
    for rel_dir in PRIORITY_SEARCH_DIRS:
        base = checkout / rel_dir
        if not base.is_dir():
            continue
        direct = base / upstream_name
        if (direct / "SKILL.md").is_file() and frontmatter_name(direct / "SKILL.md") == upstream_name:
            return direct
        matches = scan_skill_matches(base, upstream_name, max_depth=3)
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            raise ValueError(f"在 {rel_dir} 中发现多个同名上游 Skill ({upstream_name}): {matches}")
    matches = scan_skill_matches(checkout, upstream_name)
    if len(matches) == 1:
        return matches[0]
    raise ValueError(f"无法在归档中唯一定位上游 Skill ({upstream_name}): 找到 {len(matches)} 处")


def copy_skill_dir(src, dest):
    dest.mkdir(parents=True, exist_ok=True)
    for root, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
        current = Path(root)
        rel = current.relative_to(src)
        target_dir = dest / rel
        target_dir.mkdir(parents=True, exist_ok=True)
        for fname in sorted(files):
            if fname in EXCLUDE_FILES:
                continue
            sp = current / fname
            if sp.is_symlink():
                raise ValueError(f"Skill 源目录须为独立文件，发现软链: {sp}")
            dp = target_dir / fname
            shutil.copyfile(sp, dp)
            if os.name != "nt":
                dp.chmod(0o755 if (sp.stat().st_mode & 0o111) else 0o644)


def prepare_upstream_group(index, repo, commit, entries, stage, proxy):
    work = stage / "_upstream" / str(index)
    work.mkdir(parents=True)
    checkout = work / "checkout"
    extract_release(repo, commit, {skill.source["path"] for skill in entries}, checkout, proxy)
    group_sources = {}
    for skill in entries:
        upstream_name = skill.source.get("upstreamName", skill.name)
        src_dir = find_skill_dir(checkout, skill.source["path"], upstream_name)
        destination = stage / skill.name
        copy_skill_dir(src_dir, destination)
        if upstream_name != skill.name:
            rename_skill(destination / "SKILL.md", upstream_name, skill.name)
        group_sources[skill.name] = destination
    return group_sources


def prepare_sources(skills, stage, proxy):
    sources = {}
    upstream = defaultdict(list)
    for skill in skills:
        if skill.local is None:
            upstream[(skill.source["repo"], skill.source["commit"])].append(skill)
        else:
            destination = stage / skill.name
            shutil.copytree(skill.local, destination, symlinks=True)
            sources[skill.name] = destination
    items = list(enumerate(upstream.items()))
    if len(items) == 1:
        idx, ((repo, commit), entries) = items[0]
        sources.update(prepare_upstream_group(idx, repo, commit, entries, stage, proxy))
    elif len(items) > 1:
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(4, len(items))) as executor:
            futures = [
                executor.submit(prepare_upstream_group, idx, repo, commit, entries, stage, proxy)
                for idx, ((repo, commit), entries) in items
            ]
            for future in futures:
                sources.update(future.result())
    for skill in skills:
        if skill_key(sources[skill.name], skill.name) != skill.key:
            raise ValueError(f"Skill 文件与规划摘要不一致: {skill.name}")
    return sources


def rename_skill(entry, upstream_name, name):
    if entry.is_symlink():
        raise ValueError(f"Skill 清单不能是软链: {entry}")
    metadata, delimiter, body = entry.read_text(encoding="utf-8").partition("\n---\n")
    names = re.findall(r"^name:[ \t]*([^\n]*?)[ \t]*$", metadata, re.MULTILINE)
    if not metadata.startswith("---\n") or not delimiter or names != [upstream_name]:
        raise ValueError(f"无法核对上游 Skill 名称: {entry}")
    metadata = re.sub(r"^name:[^\n]*$", f"name: {name}", metadata, flags=re.MULTILINE)
    with entry.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(metadata + delimiter + body)


def extract_archive(archive, repo, commit, skill_paths, checkout):
    prefix = f"{repo.split('/')[1]}-{commit}"
    with tarfile.open(archive) as bundle:
        for member in bundle:
            root, _, relative = member.name.partition("/")
            if root != prefix or not relative:
                continue
            if "." not in skill_paths and not any(relative.startswith(path + "/") for path in skill_paths):
                continue
            parts = PurePosixPath(relative)
            if "\\" in relative or parts.is_absolute() or ".." in parts.parts:
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


def extract_release(repo, commit, skill_paths, checkout, proxy):
    archive = checkout.parent / "source.tar.gz"
    url = f"https://codeload.github.com/{repo}/tar.gz/{commit}"
    command = [
        "curl", "-fsSL", "--proto", "=https", "--proto-redir", "=https",
        "--retry", "2", "--retry-delay", "1",
        "--connect-timeout", "15", "--max-time", "90",
    ]
    if proxy:
        command.extend(["--proxy", proxy])
    result = subprocess.run([*command, "-o", str(archive), url], check=False, timeout=100)
    if result.returncode:
        raise ValueError(f"下载锁定的上游版本失败: {repo}@{commit} (curl {result.returncode})")
    extract_archive(archive, repo, commit, skill_paths, checkout)


def expand_config_path(raw, device):
    expanded = Path(raw).expanduser()
    if ".." in expanded.parts:
        raise ValueError(f"配置目录不能包含路径跳转: {raw}")
    if expanded.is_absolute():
        # 若宿主机 HOME 经符号链接映射（如 macOS /var -> /private/var），把前缀对齐到已解析的 device。
        raw_home = Path.home()
        if inside(expanded, raw_home) and raw_home != device:
            return device / expanded.relative_to(raw_home)
        return expanded
    return device / expanded


def roots_for(device, isolated):
    for tool, (env, default, suffix) in TARGETS.items():
        override = os.environ.get(env) if env and not isolated else None
        if override:
            expanded = Path(override).expanduser()
            if not expanded.is_absolute():
                raise ValueError(f"{tool} 的配置目录需要使用绝对路径: {expanded}")
            base = expand_config_path(override, device)
        else:
            base = device / default
        if tool == "opencode" and not isolated and os.environ.get("OPENCODE_CONFIG_DIR"):
            raw_oc = os.environ["OPENCODE_CONFIG_DIR"]
            expanded_oc = Path(raw_oc).expanduser()
            if not expanded_oc.is_absolute():
                raise ValueError(f"{tool} 的配置目录需要使用绝对路径: {expanded_oc}")
            base = expand_config_path(raw_oc, device)
            suffix = "skills"
        if tool == "omp" and not isolated:
            profile = os.environ.get("OMP_PROFILE", os.environ.get("PI_PROFILE", "")).strip()
            raw_pi_cfg = os.environ.get("PI_CONFIG_DIR")
            config_dir = expand_config_path(raw_pi_cfg, device) if raw_pi_cfg else device / ".omp"
            if profile and profile != "default":
                if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", profile) or profile.endswith("."):
                    raise ValueError(f"无效的 omp profile: {profile}")
                base = config_dir / "profiles" / profile / "agent"
            else:
                agent_dir = os.environ.get("PI_CODING_AGENT_DIR")
                if agent_dir:
                    expanded_agent = Path(agent_dir).expanduser()
                    if not expanded_agent.is_absolute():
                        raise ValueError(f"{tool} 的配置目录需要使用绝对路径: {expanded_agent}")
                    base = expand_config_path(agent_dir, device)
                else:
                    base = config_dir / "agent"
        if not base.is_absolute() or ".." in base.parts:
            raise ValueError(f"{tool} 的配置目录需要使用无路径跳转的绝对路径: {base}")
        yield tool, (base / suffix) if suffix else base
    # Some Codex installations also expose this directory. Handle existing names
    # there without adding a second installation on clean devices.
    yield "codex-legacy", device / ".codex/skills"


def make_plan(skills, roots, store, state, adopt, adopt_all=False):
    if adopt_all and adopt:
        raise ValueError("--adopt 与 --adopt-all 不能同时使用")
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
            elif adopt_all or identifier in adopt:
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
        try:
            resolved = target.path.resolve()
        except (OSError, RuntimeError):
            continue
        linked = primary.get(resolved)
        if linked and linked.action in CHANGES and linked.skill.name == target.skill.name:
            if adopt_all or target.action != "adopt":
                target.action = "linked"
    return targets


def report(targets, state):
    for target in targets:
        link = f" -> {target.path.readlink()}" if target.action == "conflict" and target.path.is_symlink() else ""
        print(f"{target.action:<9} {target.identifier:<31} {target.path}{link}")
    paths = {str(target.path) for target in targets}
    for path in sorted(set(state["managed"]) - paths):
        print(f"retained  {path}")


def sync(args, skills, roots, store, state):
    selected = set(args.adopt)
    if selected:
        current_plan = make_plan(skills, roots, store, state, set())
        conflicts = {target.identifier for target in current_plan if target.action == "conflict"}
        if selected - conflicts:
            raise ValueError(f"--adopt 只接受预览中的冲突项: {', '.join(sorted(selected - conflicts))}")
    plan = make_plan(skills, roots, store, state, selected, adopt_all=args.adopt_all)
    report(plan, state)
    changes = [target for target in plan if target.action in CHANGES]
    if changes:
        with tempfile.TemporaryDirectory(prefix="governance-skills-") as temporary:
            changed_names = {target.skill.name for target in changes}
            sources = prepare_sources(
                [skill for skill in skills if skill.name in changed_names], Path(temporary),
                args.proxy,
            )
            store.apply(
                [(target.path, sources[target.skill.name], target.current) for target in changes],
                state,
            )
        print(f"已同步 {len(changes)} 个路径。")
    return int(any(target.action == "conflict" for target in plan))


def prune(skills, roots, store, state):
    plan = make_plan(skills, roots, store, state, set())
    active_paths = {str(target.path) for target in plan}
    retained = sorted(set(state["managed"]) - active_paths)
    if not retained:
        print("没有可清理的已移除 Skill。")
        return 0
    changes = []
    conflicts = []
    for raw_path in retained:
        path = store.destination(Path(raw_path))
        actual = path_key(path)
        expected = state["managed"][raw_path]
        if actual is None:
            print(f"prune-ref {path}")
            changes.append((path, None, None))
        elif actual == expected:
            print(f"prune     {path}")
            changes.append((path, None, actual))
        else:
            print(f"conflict  {path}")
            conflicts.append(raw_path)
    if changes:
        store.apply(changes, state)
        print(f"已清理 {len(changes)} 个已移除路径。")
    if conflicts:
        print(f"Skills: 保留 {len(conflicts)} 个被外部修改的已移除路径，未删除。", file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(prog="bash scripts/gov skills", description=__doc__)
    parser.add_argument("command", choices=("plan", "status", "sync", "prune", "rollback"))
    parser.add_argument("--home", type=Path, help="用于隔离验证的用户目录")
    parser.add_argument("--proxy", help="获取 GitHub 源时使用的 HTTP 或 SOCKS 代理")
    parser.add_argument("--adopt", action="append", default=[], metavar="TOOL:SKILL")
    parser.add_argument("--adopt-all", action="store_true", help="自动接管并覆盖全部同名冲突 Skill（仍建快照可回退）")
    args = parser.parse_args()
    if (args.adopt or args.adopt_all or args.proxy) and args.command != "sync":
        parser.error("--adopt、--adopt-all 和 --proxy 仅用于 sync")
    if args.adopt and args.adopt_all:
        parser.error("--adopt 与 --adopt-all 不能同时使用")
    try:
        device = (args.home or Path.home()).resolve(strict=True)
        state_root = (device / ".local/state/agent-governance/skills").resolve()
        if not device.is_dir() or not inside(state_root, device):
            raise ValueError("用户目录或状态目录无效")
        allow_external = args.home is None and os.environ.get("AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS") == "1"
        store = Store(state_root, device, allow_external)
        if args.command != "rollback":
            skills = load_skills()
            roots = list(roots_for(device, args.home is not None))
        if args.command in {"plan", "status"}:
            if store.pending.exists():
                raise ValueError("检测到中断的同步。运行 sync、prune 或 rollback 恢复后再查看状态。")
            state = store.state()
            plan = make_plan(skills, roots, store, state, set())
            report(plan, state)
            return int(args.command == "status" and any(
                target.action not in READY | {"shared"} for target in plan
            ))

        state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (state_root / "lock").open("a+b") as lock:
            lock_file(lock)
            store.recover()
            state = store.state()
            if args.command == "rollback":
                print(f"已回退 {store.rollback(state)} 个路径。")
                return 0
            if args.command == "prune":
                return prune(skills, roots, store, state)
            return sync(args, skills, roots, store, state)
    except BlockingIOError:
        print("已有 Skills 同步正在执行。", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print(f"Skills: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
