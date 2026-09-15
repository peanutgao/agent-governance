#!/usr/bin/env bash
# check-version-bump.sh — 规则改了但 VERSION 没 bump 就拦下
#
# 用法: bash scripts/check-version-bump.sh
#
# 规则文件（global/、tests/、.github/、.githooks/、README.md、onboarding.md 与公共检查脚本）一旦变更，VERSION 必须在同一次或更晚的
# 提交里 bump，否则各成员的 .gov-version 不变、distribute.sh 会显示「已是最新」，
# 新规则悄悄地发不下去。本脚本纯本地 git，不依赖 remote。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

RULE_PATHS=(
  global
  tests
  .github
  .githooks
  README.md
  onboarding.md
  scripts/check-commit-attribution.sh
  scripts/distribute.sh
  scripts/check-version-bump.sh
)

SEMVER_REGEX='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

validate_version_value() {
  local label="$1"
  local value="$2"

  if [[ ! "$value" =~ $SEMVER_REGEX ]]; then
    echo "错误: $label 不是严格的 SemVer（需要 major.minor.patch，且数字不能有前导 0）: $value" >&2
    return 1
  fi
}

version_is_greater() {
  local old_version="$1"
  local new_version="$2"
  local old_major old_minor old_patch
  local new_major new_minor new_patch
  local -a old_parts new_parts
  local index old_part new_part

  IFS=. read -r old_major old_minor old_patch <<<"$old_version"
  IFS=. read -r new_major new_minor new_patch <<<"$new_version"
  old_parts=("$old_major" "$old_minor" "$old_patch")
  new_parts=("$new_major" "$new_minor" "$new_patch")

  for index in 0 1 2; do
    old_part="${old_parts[$index]}"
    new_part="${new_parts[$index]}"
    if (( ${#new_part} > ${#old_part} )); then
      return 0
    fi
    if (( ${#new_part} < ${#old_part} )); then
      return 1
    fi
    if [[ "$new_part" > "$old_part" ]]; then
      return 0
    fi
    if [[ "$new_part" < "$old_part" ]]; then
      return 1
    fi
  done

  return 1
}

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

version_line_count="$(awk 'END { print NR }' VERSION)"
if [[ "$version_line_count" -ne 1 ]]; then
  echo "错误: VERSION 必须只包含一行 SemVer。" >&2
  exit 1
fi

current_version="$(sed -n '1p' VERSION)"
validate_version_value "VERSION" "$current_version"

previous_version=""
if previous_version="$(git show "${version_commit}^:VERSION" 2>/dev/null)"; then
  validate_version_value "VERSION 的上一版本" "$previous_version"
  if ! version_is_greater "$previous_version" "$current_version"; then
    echo "错误: VERSION 必须比上一版本递增（上一版本: $previous_version，当前版本: $current_version）。" >&2
    exit 1
  fi
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

echo "✓ VERSION（${current_version}）的格式、递增关系和提交关系均通过。"
