#!/usr/bin/env bash
# init-project-governance.sh — 轻量初始化新项目的自包含 AI 治理骨架（支持单端与多端 Monorepo）
#
# 用法:
#   bash scripts/init-project-governance.sh --target <project-dir> [--project-name <name>] [--apps <a,b,...>] [--dry-run]
#   bash scripts/init-project-governance.sh --target <project-dir> --add-app <a,b,...> [--dry-run]
set -euo pipefail

_self="${BASH_SOURCE[0]:-}"
[[ -f "$_self" ]] || _self="$0"
REPO_DIR="$(cd "$(dirname "$_self")/.." && pwd)"

resolve_python() {
  local -a candidates=()
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) export PYTHONUTF8=1; candidates=(python python3) ;;
    *) candidates=(python3 python) ;;
  esac
  export PYTHONDONTWRITEBYTECODE=1

  local cmd
  for cmd in "${candidates[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1 &&
       "$cmd" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
      printf '%s\n' "$cmd"
      return 0
    fi
  done
  printf '错误: 需要 Python 3.9 或更高版本。\n' >&2
  return 1
}

PY_CMD="$(resolve_python)"
exec "$PY_CMD" "$REPO_DIR/scripts/init_project_governance.py" "$@"
