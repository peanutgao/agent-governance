#!/usr/bin/env bash
# Activate project-local Git hooks (.githooks) without clobbering existing Husky/Lefthook setups.
set -euo pipefail

force=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --force) force=1; shift ;;
    -h|--help) printf '用法: bash scripts/governance/install-hooks.sh [--force]\n' >&2; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/../.." rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  printf '错误: %s 不是 Git 仓库，请先 git init。\n' "$REPO_ROOT" >&2
  exit 1
fi

existing="$(git -C "$REPO_ROOT" config --local --get core.hooksPath 2>/dev/null || true)"
if [[ -n "$existing" && "$existing" != ".githooks" && "$force" != 1 ]]; then
  printf '错误: 当前仓库已配置 local core.hooksPath=%s（例如 Husky/Lefthook），拒绝覆盖。\n' "$existing" >&2
  printf '      如需替换请传 --force；否则请在现有 commit-msg 钩子中调用 .githooks/commit-msg。\n' >&2
  exit 1
fi

chmod +x "$REPO_ROOT"/.githooks/* "$REPO_ROOT"/scripts/governance/*.sh 2>/dev/null || true
for tracked in .githooks/commit-msg scripts/governance/check-commit-attribution.sh scripts/governance/install-hooks.sh scripts/governance/_python.sh; do
  if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$tracked" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" update-index --chmod=+x "$tracked" >/dev/null 2>&1 || true
  fi
done

git -C "$REPO_ROOT" config --local core.hooksPath .githooks
printf '✓ 已启用项目本地 Git 钩子（core.hooksPath=.githooks）。\n'
