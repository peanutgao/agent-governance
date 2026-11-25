#!/usr/bin/env python3
"""Lightweight scaffolding CLI for self-contained single-app and multi-end monorepo AI governance."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Sequence, Set

SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
TEMPLATED_FILES = {"AGENTS.md", "governance.config.json", "docs/overview.md"}
RESERVED_APP_ROOTS = {
    "docs", "scripts", "contracts", "specs", "plans",
    ".git", ".githooks", ".github", ".claude", ".cursor", ".vscode",
}


def configure_stdio() -> None:
    for s in (sys.stdout, sys.stderr):
        if hasattr(s, "reconfigure"):
            try:
                s.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def norm_rel(p: str) -> str:
    rel = p.replace("\\", "/").strip()
    while rel.startswith("./"):
        rel = rel[2:]
    return rel.rstrip("/")


def is_safe_rel(rel: str) -> bool:
    if not rel or "\x00" in rel or "\\" in rel or rel.startswith("/") or re.match(r"^[A-Za-z]:", rel):
        return False
    return all(part not in ("", ".", "..") for part in rel.split("/"))


def safe_dest(root: Path, rel: str) -> Path:
    if not is_safe_rel(rel):
        raise ValueError(f"非法相对路径: {rel}")
    resolved_root = root.resolve()
    cur = resolved_root
    for part in rel.split("/"):
        cur = cur / part
        if cur.is_symlink():
            raise ValueError(f"拒绝写入软链路径: {cur}")
    resolved = cur.resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise ValueError(f"路径越界目标目录: {rel}") from exc
    return resolved


def to_lf(raw: bytes) -> bytes:
    return raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def atomic_write(dest: Path, data: bytes, executable: bool = False) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".gov-init.", dir=str(dest.parent))
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        if executable and os.name != "nt":
            os.chmod(tmp, 0o755)
        os.replace(tmp, dest)
        if executable and os.name != "nt":
            os.chmod(dest, 0o755)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise


def is_executable(rel: str) -> bool:
    return rel.startswith(".githooks/") or (rel.startswith("scripts/governance/") and rel.endswith(".sh"))


def read_version(repo_dir: Path) -> str:
    lines = (repo_dir / "VERSION").read_text(encoding="utf-8").splitlines()
    if len(lines) != 1 or not SEMVER_RE.match(lines[0].strip()):
        raise RuntimeError("VERSION 必须只包含一行严格的 SemVer。")
    return lines[0].strip()


def render_ai_governance(repo_dir: Path, version: str) -> bytes:
    raw = (repo_dir / "templates" / "project" / "AI-GOVERNANCE.md").read_bytes().decode("utf-8").replace("\r\n", "\n")
    m = re.search(r"baseline-content-sha256\s+是把自身\s+hash\s+字段保留为\s+([0-9a-f]{64})", raw)
    if not m:
        raise RuntimeError("templates/project/AI-GOVERNANCE.md 缺少哈希占位符声明。")
    rendered = raw.replace("__BASELINE_VERSION__", version)
    hash_in = re.sub(r"^> baseline-content-sha256:.*$", f"> baseline-content-sha256: {m.group(1)}", rendered, count=1, flags=re.M)
    digest = hashlib.sha256(hash_in.encode("utf-8")).hexdigest()
    final = re.sub(r"^> baseline-content-sha256:.*$", f"> baseline-content-sha256: {digest}", rendered, count=1, flags=re.M)
    if "__BASELINE_" in final:
        raise RuntimeError("AI-GOVERNANCE.md 渲染后仍残留占位符。")
    return final.encode("utf-8")


def parse_apps(raw_values: Sequence[str]) -> List[str]:
    out: List[str] = []
    for raw in raw_values:
        for item in raw.split(","):
            rel = norm_rel(item)
            if not rel:
                continue
            if not is_safe_rel(rel):
                raise ValueError(f"非法子端路径: {item}")
            top = rel.split("/", 1)[0]
            if top in RESERVED_APP_ROOTS:
                raise ValueError(f"子端不能使用保留顶层路径 `{top}`: {rel}")
            out.append(rel)
    return out


def validate_apps(existing: Sequence[Dict[str, Any]], new_roots: Sequence[str]) -> List[Dict[str, Any]]:
    new_entries = [
        {"name": r, "root": r, "specRoots": [f"{r}/docs/specs", f"{r}/specs"], "todoRoots": [f"{r}/docs/todos", f"{r}/plans"]}
        for r in new_roots
    ]
    seen_roots: Set[str] = set()
    for app in list(existing) + new_entries:
        r = norm_rel(str(app.get("root") or ""))
        if not is_safe_rel(r):
            raise ValueError(f"非法子端 root: {r}")
        if r in seen_roots:
            raise ValueError(f"重复的子端目录: {r}")
        for prev in seen_roots:
            if r.startswith(prev + "/") or prev.startswith(r + "/"):
                raise ValueError(f"子端目录存在父子嵌套重叠: `{prev}` 与 `{r}`")
        seen_roots.add(r)
    return new_entries


def render_apps_routing_section(apps: Sequence[Dict[str, Any]]) -> str:
    if not apps:
        return ""
    lines = [
        "",
        "## 多端入口路由（改动某端前必读本端 AGENTS.md 与选型地图）",
        "",
        "| 子端目录 | 本端入口 | 本端选型与封装地图 | 本端 Spec |",
        "| --- | --- | --- | --- |",
    ]
    for app in apps:
        r = str(app["root"])
        lines.append(f"| `{r}/` | [{r}/AGENTS.md]({r}/AGENTS.md) | [{r}/docs/architecture/tech-stack.md]({r}/docs/architecture/tech-stack.md) | [{r}/docs/specs/README.md]({r}/docs/specs/README.md) |")
    return "\n".join(lines) + "\n"


def render_app_files(project_name: str, app_root: str) -> Dict[str, bytes]:
    up = "../" * len(app_root.split("/"))
    agents_md = (
        f"# {app_root} — 本端工程规范入口\n\n"
        f"本目录属于 `{project_name}` 的独立端。改动本端代码前请同时遵守顶层共有真源与本端规范。\n\n"
        f"## 必读真源\n\n"
        f"1. 项目总览与术语：[{up}docs/overview.md]({up}docs/overview.md)\n"
        f"2. 跨端共享契约：[{up}docs/contracts/README.md]({up}docs/contracts/README.md)\n"
        f"3. 顶层共享业务 Spec：[{up}docs/specs/README.md]({up}docs/specs/README.md)\n"
        f"4. 公共治理基线：[{up}AI-GOVERNANCE.md]({up}AI-GOVERNANCE.md)\n"
        f"5. 本端选型与封装地图：[docs/architecture/tech-stack.md](docs/architecture/tech-stack.md)\n"
        f"6. 本端专属 Spec：[docs/specs/README.md](docs/specs/README.md)\n\n"
        f"## 本端常用命令（按本端技术栈填写）\n\n"
        f"```bash\n# 构建 / 测试 / 原生 Lint\n```\n"
    )
    claude_md = f"# {app_root} 入口指针\n\n- 本端工程规范：[AGENTS.md](AGENTS.md)\n- 项目总入口：[{up}AGENTS.md]({up}AGENTS.md)\n"
    tech_stack = (
        f"# {app_root} — 本端开源选型与封装目录地图\n\n"
        f"跨端共享约束见 `{up}docs/architecture/tech-stack.md`；本文件记录 `{app_root}` 批准的成熟开源库与封装/公共目录。\n\n"
        f"| 能力域 | 批准开源库 | 本端封装 / 公共目录 | 禁止行为（用原生 Linter 拦截） |\n"
        f"| --- | --- | --- | --- |\n"
        f"| Design Token / 组件（UI 端） | _按端填写_ | _如 `{app_root}/.../tokens/`_ | 禁止硬编码色值或绕过组件封装 |\n"
        f"| 网络 / 日志 / 存储封装 | _按端填写_ | _如 `{app_root}/.../infra/`_ | 禁止业务层裸调底层 SDK |\n"
    )
    spec_readme = (
        f"# {app_root} — 本端专属 Spec 索引\n\n"
        f"跨端共享规则写在顶层 `{up}docs/specs/` 与 `{up}docs/contracts/`；本目录只记录 `{app_root}` 端内特有行为与验收条件。\n"
    )
    return {
        f"{app_root}/AGENTS.md": to_lf(agents_md.encode("utf-8")),
        f"{app_root}/CLAUDE.md": to_lf(claude_md.encode("utf-8")),
        f"{app_root}/docs/architecture/tech-stack.md": to_lf(tech_stack.encode("utf-8")),
        f"{app_root}/docs/specs/README.md": to_lf(spec_readme.encode("utf-8")),
    }


def validate_target(repo_dir: Path, target_raw: Path, *, allow_create: bool) -> Path:
    if target_raw.is_symlink():
        raise ValueError(f"拒绝操作软链目标目录: {target_raw}")
    if not target_raw.exists():
        if not allow_create:
            raise ValueError(f"目标目录不存在: {target_raw}")
        parent = target_raw.parent
        if parent.is_symlink() or not parent.is_dir():
            raise ValueError(f"目标父目录无效或为软链: {parent}")
        resolved = parent.resolve() / target_raw.name
    else:
        if not target_raw.is_dir():
            raise ValueError(f"目标路径不是目录: {target_raw}")
        resolved = target_raw.resolve()
    repo_resolved = repo_dir.resolve()
    if resolved == repo_resolved or repo_resolved in resolved.parents:
        raise ValueError(f"拒绝在治理仓自身内部初始化项目: {resolved}")
    return resolved


def main(argv: List[str]) -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description="Scaffold lightweight self-contained project AI governance.")
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--project-name", default="")
    parser.add_argument("--apps", action="append", default=[], help="Comma-separated sub-app dirs for monorepo init.")
    parser.add_argument("--add-app", action="append", default=[], help="Add sub-app dir(s) to an initialized repo.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    if args.apps and args.add_app:
        print("错误: --apps 与 --add-app 不能同时使用。", file=sys.stderr)
        return 2

    repo_dir = Path(__file__).resolve().parent.parent
    try:
        version = read_version(repo_dir)
        target = validate_target(repo_dir, args.target, allow_create=not bool(args.add_app))
        project_name = args.project_name.strip() or target.name

        if args.add_app:
            cfg_path = target / "governance.config.json"
            if not cfg_path.is_file():
                raise ValueError(f"{target} 缺少 governance.config.json，请先初始化项目。")
            cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
            new_roots = parse_apps(args.add_app)
            if not new_roots:
                raise ValueError("--add-app 未提供有效子端路径。")
            new_entries = validate_apps(cfg.get("apps", []), new_roots)
            proj = str(cfg.get("projectName") or project_name)

            files_to_create: Dict[str, bytes] = {}
            for entry in new_entries:
                files_to_create.update(render_app_files(proj, str(entry["root"])))
            for rel in files_to_create:
                safe_dest(target, rel)

            cfg["layout"] = "monorepo"
            cfg.setdefault("apps", []).extend(new_entries)
            for entry in new_entries:
                if entry["root"] not in cfg.setdefault("sourceRoots", []):
                    cfg["sourceRoots"].append(entry["root"])

            created, skipped = 0, 0
            for rel, data in sorted(files_to_create.items()):
                dest = safe_dest(target, rel)
                if dest.exists():
                    skipped += 1
                else:
                    created += 1
                    if not args.dry_run:
                        atomic_write(dest, data)
            if not args.dry_run:
                atomic_write(safe_dest(target, "governance.config.json"), (json.dumps(cfg, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))

            tag = "[dry-run] " if args.dry_run else ""
            print(f"{tag}✓ 已追加子端 ({', '.join(new_roots)})：新建 {created} 项，保留既有 {skipped} 项。")
            print("  - 请在根 AGENTS.md 多端路由表与 docs/overview.md 补充新端入口。")
            return 0

        if (target / "governance.config.json").exists():
            raise ValueError(f"{target} 已初始化（存在 governance.config.json）；追加子端请用 --add-app，更新 AI-GOVERNANCE.md 请用 sync-project-governance.sh。")

        kit_dir = repo_dir / "templates" / "project" / "kit"
        init_roots = parse_apps(args.apps) if args.apps else []
        app_entries = validate_apps([], init_roots) if init_roots else []
        routing_md = render_apps_routing_section(app_entries)

        files: Dict[str, bytes] = {}
        for p in sorted(kit_dir.rglob("*")):
            if p.is_dir() or p.name == ".DS_Store" or "__pycache__" in p.parts or p.suffix in (".pyc", ".pyo"):
                continue
            rel = p.relative_to(kit_dir).as_posix()
            data = to_lf(p.read_bytes())
            if rel in TEMPLATED_FILES:
                text = data.decode("utf-8").replace("__PROJECT_NAME__", project_name).replace("__APPS_ROUTING_SECTION__", routing_md)
                data = text.encode("utf-8")
            files[rel] = data

        if app_entries:
            cfg = json.loads(files["governance.config.json"].decode("utf-8"))
            cfg["layout"] = "monorepo"
            cfg["apps"] = app_entries
            for entry in app_entries:
                if entry["root"] not in cfg["sourceRoots"]:
                    cfg["sourceRoots"].append(entry["root"])
            files["governance.config.json"] = (json.dumps(cfg, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
            for entry in app_entries:
                files.update(render_app_files(project_name, str(entry["root"])))

        files["AI-GOVERNANCE.md"] = render_ai_governance(repo_dir, version)
        files["scripts/governance/check-commit-attribution.sh"] = to_lf(
            (repo_dir / "scripts" / "check-commit-attribution.sh").read_bytes()
        )

        if target.exists():
            for rel in files:
                safe_dest(target, rel)

        created, skipped = 0, 0
        if not args.dry_run:
            target.mkdir(parents=True, exist_ok=True)
        for rel, data in sorted(files.items()):
            dest = safe_dest(target, rel) if target.exists() else target / rel
            if dest.exists():
                skipped += 1
            else:
                created += 1
                if not args.dry_run:
                    atomic_write(dest, data, executable=is_executable(rel))

        tag = "[dry-run] " if args.dry_run else ""
        print(f"{tag}✓ 已初始化项目治理骨架 (baseline-version={version}): {target}（新建 {created} 项，保留既有 {skipped} 项）")
        if not args.dry_run:
            print("  - 下一步：补全 AGENTS.md 命令、将 .github/CODEOWNERS 的 @team-leads 替换为真实负责人，并运行 `bash scripts/governance/install-hooks.sh`。")
        return 0
    except Exception as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
