#!/usr/bin/env bash
# Cross-platform Python >= 3.9 resolver for project governance scripts.

resolve_gov_python() {
  local -a candidates=()
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      export PYTHONUTF8=1
      candidates=(python python3)
      ;;
    *)
      candidates=(python3 python)
      ;;
  esac
  export PYTHONDONTWRITEBYTECODE=1

  local cmd
  for cmd in "${candidates[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
        printf '%s\n' "$cmd"
        return 0
      fi
    fi
  done

  printf '错误: 需要 Python 3.9 或更高版本运行治理脚本。\n' >&2
  return 1
}
