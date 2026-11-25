#!/usr/bin/env python3
"""Standalone Spec sync & Todo hygiene gate (stdlib-only, single-app & monorepo aware)."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

EXEMPT_RE = re.compile(r"^\s*Spec-Exempt:\s*([A-Za-z0-9._-]+)\s*\|\s*reason=(\S.+)$", re.I | re.M)
UNCHECKED_TODO_RE = re.compile(r"^\s*-\s*\[\s\]\s+(.+)$")
DEFERRED_TAG_RE = re.compile(r"\((?:deferred|blocked)\s*:", re.I)
READY_TO_CLOSE_RE = re.compile(r"Status\*{0,2}\s*:\s*`?ready-to-close`?", re.I)

NON_SOURCE_META_GLOBS = [
    "**/*.md",
    "**/package-lock.json",
    "**/pnpm-lock.yaml",
    "**/yarn.lock",
    "**/Package.resolved",
    "**/Podfile.lock",
    "**/Cargo.lock",
    "**/poetry.lock",
    "**/go.sum",
    "**/gradle.lockfile",
    "**/.gitignore",
    "**/.gitattributes",
    "**/.editorconfig",
    "**/.env.example",
]


def norm_rel(p: str) -> str:
    rel = p.replace("\\", "/").strip()
    while rel.startswith("./"):
        rel = rel[2:]
    return rel.rstrip("/")


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    pat = norm_rel(pattern)
    i, n, parts = 0, len(pat), ["^"]
    while i < n:
        if pat[i : i + 3] == "**/":
            parts.append("(?:.*/)?")
            i += 3
        elif pat[i : i + 3] == "/**" and i + 3 == n:
            parts.append("(?:/.*)?")
            i += 3
        elif pat[i : i + 2] == "**":
            parts.append(".*")
            i += 2
        elif pat[i] == "*":
            parts.append("[^/]*")
            i += 1
        elif pat[i] == "?":
            parts.append("[^/]")
            i += 1
        else:
            parts.append(re.escape(pat[i]))
            i += 1
    parts.append("$")
    return re.compile("".join(parts))


def matches_any(rel: str, globs: Sequence[str]) -> bool:
    n = norm_rel(rel)
    return any(glob_to_regex(g).match(n) is not None for g in globs)


def under_any(rel: str, roots: Sequence[str]) -> bool:
    n = norm_rel(rel)
    return any((c := norm_rel(r)) and (n == c or n.startswith(c + "/")) for r in roots)


def run_git(root: Path, args: Sequence[str], *, binary: bool = False) -> subprocess.CompletedProcess[Any]:
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=str(root),
        capture_output=True,
        text=not binary,
        encoding=None if binary else "utf-8",
        errors=None if binary else "replace",
        check=False,
    )


def parse_name_status_z(raw: bytes) -> List[Tuple[str, str]]:
    tokens = raw.split(b"\x00")
    out: List[Tuple[str, str]] = []
    i, total = 0, len(tokens)
    while i < total:
        if not tokens[i]:
            i += 1
            continue
        code = tokens[i].decode("utf-8", errors="replace")[:1]
        i += 1
        if code in ("R", "C"):
            if i + 1 >= total:
                break
            new_path = norm_rel(tokens[i + 1].decode("utf-8", errors="replace"))
            i += 2
            out.append((code, new_path))
        elif code:
            if i >= total:
                break
            path = norm_rel(tokens[i].decode("utf-8", errors="replace"))
            i += 1
            out.append((code, path))
    return out


def get_changes(root: Path, mode: str, range_spec: Optional[str]) -> Tuple[List[Tuple[str, str]], Optional[str], Optional[str]]:
    if mode == "staged":
        proc = run_git(root, ["diff", "--cached", "-z", "--name-status"], binary=True)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
        return parse_name_status_z(proc.stdout), None, ":INDEX:"

    assert range_spec
    base_raw, head_raw = (range_spec.split("...", 1) if "..." in range_spec else range_spec.split("..", 1))
    base_raw, head_raw = base_raw.strip(), head_raw.strip() or "HEAD"
    if not base_raw or base_raw == "0" * 40:
        proc = run_git(root, ["diff-tree", "--no-commit-id", "--root", "-r", "-z", "--name-status", head_raw], binary=True)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
        return parse_name_status_z(proc.stdout), None, head_raw

    mb = run_git(root, ["merge-base", base_raw, head_raw])
    resolved_base = mb.stdout.strip() if mb.returncode == 0 and mb.stdout.strip() else base_raw
    proc = run_git(root, ["diff", "-z", "--name-status", resolved_base, head_raw], binary=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
    return parse_name_status_z(proc.stdout), resolved_base, head_raw


def strip_commit_comments(text: str) -> str:
    kept: List[str] = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if re.match(r"^#\s*-+\s*>8\s*-+\s*$", line):
            break
        if not line.startswith("#"):
            kept.append(line)
    return "\n".join(kept)


def read_git_text(root: Path, spec: str) -> Optional[str]:
    proc = run_git(root, ["show", spec], binary=True)
    if proc.returncode != 0 or b"\x00" in proc.stdout[:8192]:
        return None
    return proc.stdout.decode("utf-8", errors="replace")


def resolve_scope(rel: str, apps: Sequence[Dict[str, Any]]) -> str:
    n, best, best_len = norm_rel(rel), "__root__", -1
    for app in apps:
        aroot = norm_rel(str(app.get("root") or ""))
        if aroot and (n == aroot or n.startswith(aroot + "/")) and len(aroot) > best_len:
            best, best_len = aroot, len(aroot)
    return best


def main(argv: List[str]) -> int:
    for s in (sys.stdout, sys.stderr):
        if hasattr(s, "reconfigure"):
            try:
                s.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass

    parser = argparse.ArgumentParser(description="Verify Spec sync and Todo readiness.")
    grp = parser.add_mutually_exclusive_group(required=True)
    grp.add_argument("--staged", action="store_true")
    grp.add_argument("--range")
    parser.add_argument("--message", type=Path, default=None)
    parser.add_argument("--root", type=Path, default=None)
    args = parser.parse_args(argv)

    root = (args.root or Path.cwd()).resolve()
    cfg = json.loads((root / "governance.config.json").read_text(encoding="utf-8"))
    spec_cfg = cfg.get("specSync") if isinstance(cfg.get("specSync"), dict) else {}
    if not spec_cfg.get("enabled", True):
        return 0

    mode = "staged" if args.staged else "range"
    if mode == "staged" and run_git(root, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]).returncode == 0:
        return 0

    entries, resolved_base, resolved_head = get_changes(root, mode, args.range)
    if not entries:
        return 0

    apps = [a for a in cfg.get("apps", []) if isinstance(a, dict) and a.get("root")]
    source_roots = [str(r) for r in cfg.get("sourceRoots", [])]
    root_specs = [str(r) for r in cfg.get("specRoots", ["docs/specs", "docs/contracts", "specs", "contracts"])]
    root_todos = [str(r) for r in cfg.get("todoRoots", ["docs/todos", "plans"])]
    ignore_globs = [str(g) for g in spec_cfg.get("ignoreGlobs", [])]
    allowed_exempt = {str(t).lower(): str(t) for t in spec_cfg.get("allowedExemptTypes", ["L0", "L1-bug", "internal-refactor"])}
    strict_todo = str(spec_cfg.get("uncheckedTodoMode", "advisory")) == "strict"

    app_specs = {norm_rel(str(a["root"])): [str(r) for r in a.get("specRoots", [f"{a['root']}/docs/specs", f"{a['root']}/specs"])] for a in apps}
    app_todos = {norm_rel(str(a["root"])): [str(r) for r in a.get("todoRoots", [f"{a['root']}/docs/todos", f"{a['root']}/plans"])] for a in apps}
    docs_roots = ["docs"] + [f"{norm_rel(str(a['root']))}/docs" for a in apps]

    spec_scopes: Set[str] = set()
    todo_files: List[str] = []
    src_by_scope: Dict[str, List[str]] = {}

    for code, rel in entries:
        scope = resolve_scope(rel, apps)
        if (scope == "__root__" and under_any(rel, root_specs)) or (scope != "__root__" and under_any(rel, app_specs.get(scope, []))):
            if Path(rel).name not in ("_template.md", "README.md"):
                spec_scopes.add(scope)
            continue
        if (scope == "__root__" and under_any(rel, root_todos)) or (scope != "__root__" and under_any(rel, app_todos.get(scope, []))):
            if Path(rel).name not in ("_template.md", "README.md") and code != "D":
                todo_files.append(rel)
            continue
        if under_any(rel, docs_roots) or matches_any(rel, NON_SOURCE_META_GLOBS):
            continue
        if under_any(rel, source_roots) and not matches_any(rel, ignore_globs):
            src_by_scope.setdefault(scope, []).append(rel)

    errors: List[str] = []
    uncovered = {
        sc: files for sc, files in sorted(src_by_scope.items())
        if not (("__root__" in spec_scopes) or (sc != "__root__" and sc in spec_scopes))
    }

    if uncovered:
        texts: List[str] = []
        if args.message and args.message.is_file():
            texts.append(strip_commit_comments(args.message.read_text(encoding="utf-8", errors="replace")))
        if mode == "range" and resolved_head:
            rev = f"{resolved_base}..{resolved_head}" if resolved_base else resolved_head
            log = run_git(root, ["log", "--format=%B", rev])
            if log.returncode == 0 and log.stdout:
                texts.append(strip_commit_comments(log.stdout))
        if os.environ.get("PR_BODY"):
            texts.append(re.sub(r"<!--.*?-->", "", os.environ["PR_BODY"], flags=re.DOTALL))
        if os.environ.get("SPEC_EXEMPT"):
            texts.append(os.environ["SPEC_EXEMPT"])

        exempt = next(
            (m for t in texts for m in EXEMPT_RE.finditer(t) if m.group(1).strip().lower() in allowed_exempt),
            None,
        )
        if exempt is None:
            allowed_str = "|".join(allowed_exempt.values())
            for sc, files in uncovered.items():
                label = "项目源码" if sc == "__root__" else f"端 `{sc}` 源码"
                hint = ", ".join(root_specs) if sc == "__root__" else f"{', '.join(root_specs)} 或 {', '.join(app_specs[sc])}"
                errors.append(
                    f"改动了{label}（{', '.join(files[:4])}），但未同步 Spec（{hint}）。"
                    f"请更新 Spec，或声明 `Spec-Exempt: <{allowed_str}> | reason=<一句话原因>`。"
                )

    for rel in todo_files:
        text = read_git_text(root, f":{rel}" if mode == "staged" else f"{resolved_head}:{rel}")
        if not text:
            continue
        unchecked = [
            idx for idx, line in enumerate(text.splitlines(), 1)
            if UNCHECKED_TODO_RE.match(line) and not DEFERRED_TAG_RE.search(line)
        ]
        if unchecked and (strict_todo or READY_TO_CLOSE_RE.search(text)):
            errors.append(f"{rel} 仍有 {len(unchecked)} 项未勾选 Todo（首个在第 {unchecked[0]} 行），请勾选或标注 `(deferred: 原因)`。")

    if errors:
        for e in errors:
            print(f"错误: {e}", file=sys.stderr)
        return 1
    print("✓ Spec 与 Todo 检查通过。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
