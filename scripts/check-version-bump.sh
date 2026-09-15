#!/usr/bin/env bash
# check-version-bump.sh — 规则改了但 VERSION 没 bump 就拦下
#
# 用法: bash scripts/check-version-bump.sh
#
# 规则文件（global/、.github/、.githooks/、README.md、onboarding.md 与公共检查脚本）一旦变更，VERSION 必须在同一次或更晚的
# 提交里 bump，否则各成员的 .gov-version 不变、distribute.sh 会显示「已是最新」，
# 新规则悄悄地发不下去。本脚本纯本地 git，不依赖 remote。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

RULE_PATHS=(
  global
  .github
  .githooks
  README.md
  onboarding.md
  scripts/check-commit-attribution.sh
  scripts/distribute.sh
  scripts/check-version-bump.sh
)

# --- 1. 工作区必须干净：分发的是工作区内容，未提交的规则不该下发给团队 ---
dirty="$(git status --porcelain -- "${RULE_PATHS[@]}" VERSION)"
if [[ -n "$dirty" ]]; then
  echo "错误: 规则文件有未提交改动，拒绝分发（先提交或 git stash）：" >&2
  echo "$dirty" >&2
  exit 1
fi

# --- 2. VERSION 的最近一次提交必须包含所有规则文件的最近一次提交 ---
version_commit="$(git log -1 --format=%H -- VERSION)"

if [[ -z "$version_commit" ]]; then
  echo "错误: VERSION 从未被提交过。" >&2
  exit 1
fi

for rule_path in "${RULE_PATHS[@]}"; do
  rule_commit="$(git log -1 --format=%H -- "$rule_path")"
  if [[ -z "$rule_commit" ]]; then
    echo "错误: 规则路径从未被提交过: $rule_path" >&2
    exit 1
  fi
  if ! git merge-base --is-ancestor "$rule_commit" "$version_commit"; then
    echo "错误: 规则路径最近一次提交不在 VERSION 提交之前——改了规则却没 bump VERSION: $rule_path" >&2
    echo "      规则提交: $(git log -1 --format='%h %ad %s' --date=short -- "$rule_path")" >&2
    echo "      VERSION 提交: $(git log -1 --format='%h %ad %s' --date=short -- VERSION)" >&2
    echo "      → 修正: 更新 VERSION 后重新提交。" >&2
    exit 1
  fi
done

echo "✓ VERSION（$(tr -d '[:space:]' < VERSION)）的提交包含所有规则路径的最近一次提交。"
