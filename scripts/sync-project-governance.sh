#!/usr/bin/env bash
# sync-project-governance.sh — 从模板生成项目仓库的 AI-GOVERNANCE.md 快照
#
# 用法:
#   bash scripts/sync-project-governance.sh [--check] [--root <monorepo-root>]
#
# 默认目标根目录:
#   $HOME/Documents/work/personal-project/hengqin
#
# 目标仓库:
#   hengqin-backend / hengqin-desktop / hengqin-admin
#
# 行为:
#   1. 从 templates/project/AI-GOVERNANCE.md 渲染 baseline-version
#   2. 按现有校验方案计算 baseline-content-sha256（header 的 hash 字段先还原为占位符）
#   3. 写入三仓 AI-GOVERNANCE.md；--check 只比较，不写入，不一致时退出 1
#
# 该脚本只改由治理仓生成的快照，不改各仓 AGENTS.md、specs 或业务代码。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_DIR/templates/project/AI-GOVERNANCE.md"
VERSION_FILE="$REPO_DIR/VERSION"
TARGET_ROOT="${PROJECT_GOVERNANCE_ROOT:-$HOME/Documents/work/personal-project/hengqin}"
REPOS=(hengqin-backend hengqin-desktop hengqin-admin)

# 与 scripts/check-governance-snapshot.sh 的 PLACEHOLDER 保持一致。
PLACEHOLDER="416fd18874c6a253af427226a890c03d0b35da8c2d33ceaec46be376de67ef1d"

mode="write"

usage() {
  cat >&2 <<'USAGE'
用法:
  sync-project-governance.sh                  # 生成/更新三仓快照
  sync-project-governance.sh --check          # 只校验，不写入
  sync-project-governance.sh --root <path>    # 指定 monorepo 根目录

环境变量:
  PROJECT_GOVERNANCE_ROOT                     # 等价于 --root
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --root)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      TARGET_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -f "$TEMPLATE" ]] || { printf '错误: 缺少模板 %s\n' "$TEMPLATE" >&2; exit 1; }
[[ -f "$VERSION_FILE" ]] || { printf '错误: 缺少 VERSION %s\n' "$VERSION_FILE" >&2; exit 1; }
[[ -d "$TARGET_ROOT" ]] || { printf '错误: 目标根目录不存在 %s\n' "$TARGET_ROOT" >&2; exit 1; }

for repo in "${REPOS[@]}"; do
  [[ -d "$TARGET_ROOT/$repo" ]] || { printf '错误: 目标仓库不存在 %s\n' "$TARGET_ROOT/$repo" >&2; exit 1; }
done

version="$(tr -d '[:space:]' <"$VERSION_FILE")"
[[ -n "$version" ]] || { printf '错误: VERSION 为空\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-governance-sync.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# 先把版本号写进 header 与边界标记；hash 字段暂时保留占位符。
sed "s/__BASELINE_VERSION__/$version/g" "$TEMPLATE" >"$tmp_dir/rendered.md"

# 计算哈希时，header 的 hash 字段必须还原为固定占位符（与 check 脚本同一方案）。
sed "s/^> baseline-content-sha256: .*/> baseline-content-sha256: $PLACEHOLDER/" \
  "$tmp_dir/rendered.md" >"$tmp_dir/hash-input.md"
hash="$(shasum -a 256 "$tmp_dir/hash-input.md" | cut -d' ' -f1)"

# 只替换 header 的 hash 字段；正文里解释哈希方案的那一行保持占位符原文。
awk -v hash="$hash" '
  /^> baseline-content-sha256: / {
    print "> baseline-content-sha256: " hash
    next
  }
  { print }
' "$tmp_dir/rendered.md" >"$tmp_dir/final.md"

# 检查渲染结果里没有残留占位符（版本/哈希都替换完毕）。
if grep -q '__BASELINE_' "$tmp_dir/final.md"; then
  printf '错误: 渲染结果仍有未替换的占位符:\n' >&2
  grep -n '__BASELINE_' "$tmp_dir/final.md" >&2 || true
  exit 1
fi

mismatch=0
for repo in "${REPOS[@]}"; do
  dest="$TARGET_ROOT/$repo/AI-GOVERNANCE.md"
  if [[ "$mode" == "check" ]]; then
    if [[ ! -f "$dest" ]]; then
      printf '不一致: %s 不存在\n' "$dest" >&2
      mismatch=1
    elif ! cmp -s "$tmp_dir/final.md" "$dest"; then
      printf '不一致: %s 与模板 %s 生成结果不同\n' "$dest" "$version" >&2
      mismatch=1
    else
      printf '✓ %s\n' "$dest"
    fi
  else
    cp "$tmp_dir/final.md" "$dest"
    printf '已更新: %s\n' "$dest"
  fi
done

if [[ "$mode" == "check" ]]; then
  if (( mismatch > 0 )); then
    printf '==> 项目治理快照校验未通过；运行不带 --check 的同名脚本重新生成。\n' >&2
    exit 1
  fi
  printf '==> 项目治理快照与模板一致 (baseline-version=%s)\n' "$version"
else
  printf '==> 项目治理快照已更新 (baseline-version=%s)\n' "$version"
fi
