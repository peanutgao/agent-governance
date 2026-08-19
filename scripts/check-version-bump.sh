#!/usr/bin/env bash
# check-version-bump.sh — 规则改了但 VERSION 没 bump 就拦下
#
# 用法: bash scripts/check-version-bump.sh
#
# 规则文件（global/ 与 team-contract.md）一旦变更，VERSION 必须在同一次或更晚的
# 提交里 bump，否则各成员的 .gov-version 不变、distribute.sh 会显示「已是最新」，
# 新规则悄悄地发不下去。本脚本纯本地 git，不依赖 remote。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

RULE_PATHS=(global team-contract.md)

# --- 1. 工作区必须干净：分发的是工作区内容，未提交的规则不该下发给团队 ---
dirty="$(git status --porcelain -- "${RULE_PATHS[@]}" VERSION)"
if [[ -n "$dirty" ]]; then
  echo "错误: 规则文件有未提交改动，拒绝分发（先提交或 git stash）：" >&2
  echo "$dirty" >&2
  exit 1
fi

# --- 2. VERSION 的最后改动不得早于规则文件的最后改动 ---
rules_ts="$(git log -1 --format=%ct -- "${RULE_PATHS[@]}")"
version_ts="$(git log -1 --format=%ct -- VERSION)"

if [[ -z "$version_ts" ]]; then
  echo "错误: VERSION 从未被提交过。" >&2
  exit 1
fi

if (( rules_ts > version_ts )); then
  echo "错误: 规则文件比 VERSION 新——改了规则却没 bump VERSION。" >&2
  echo "      规则最后改动: $(git log -1 --format='%h %ad %s' --date=short -- "${RULE_PATHS[@]}")" >&2
  echo "      VERSION 最后改动: $(git log -1 --format='%h %ad %s' --date=short -- VERSION)" >&2
  echo "      → 修正: 更新 VERSION 后重新提交。" >&2
  exit 1
fi

echo "✓ VERSION（$(tr -d '[:space:]' < VERSION)）不早于规则文件的最后改动。"
