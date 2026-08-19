#!/usr/bin/env bash
# distribute.sh — hengqin-governance 全局基线分发脚本
#
# 用法: bash scripts/distribute.sh
#
# 行为:
#   1. 校验 VERSION 与 global/ 必需文件存在
#   2. 安装 global/AGENTS.md → ~/.codex/AGENTS.md（先备份旧的到 AGENTS.md.bak-<时间戳>）
#   3. 维护 ~/.claude/CLAUDE.md 软链接 → ~/.codex/AGENTS.md（普通文件则先备份）
#   4. 安装 SDD 全文 → ~/.codex/ai-change-implementation-prompt.md
#   5. 版本提示：输出「最新版本 / 本机已装版本」
#   6. global/settings.json：仅当 ~/.claude/settings.json 不存在时安装，否则警告跳过（保护个人配置）
#   7. 绝不触碰 settings.local.json 与 Claude memory
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_DIR="$REPO_DIR/global"
VERSION_FILE="$REPO_DIR/VERSION"
PREFIX="$HOME/.codex"

# --- 校验 ---
[[ -f "$VERSION_FILE" ]] || { echo "错误: 缺少 VERSION 文件（$VERSION_FILE）" >&2; exit 1; }
for f in AGENTS.md ai-change-implementation-prompt.md; do
  [[ -f "$GLOBAL_DIR/$f" ]] || { echo "错误: 缺少 global/$f" >&2; exit 1; }
done

LATEST="$(tr -d '[:space:]' < "$VERSION_FILE")"

# --- 已安装版本 ---
INSTALLED=""
[[ -f "$PREFIX/.gov-version" ]] && INSTALLED="$(tr -d '[:space:]' < "$PREFIX/.gov-version")"

echo "==> hengqin-governance 全局基线分发"
echo "    最新版本: ${LATEST}"
if [[ -n "$INSTALLED" ]]; then
  echo "    本机已装: ${INSTALLED}"
  if [[ "$INSTALLED" == "$LATEST" ]]; then
    echo "    ✓ 已是最新，无需更新。"
  else
    echo "    → 检测到新版，执行更新..."
  fi
fi

mkdir -p "$PREFIX"

ts="$(date +%Y%m%d-%H%M%S)"

# --- 备份旧 AGENTS.md ---
if [[ -f "$PREFIX/AGENTS.md" ]]; then
  cp "$PREFIX/AGENTS.md" "$PREFIX/AGENTS.md.bak-$ts"
  echo "    已备份: AGENTS.md.bak-$ts"
fi

# --- 安装 ---
cp "$GLOBAL_DIR/AGENTS.md" "$PREFIX/AGENTS.md"
cp "$GLOBAL_DIR/ai-change-implementation-prompt.md" "$PREFIX/ai-change-implementation-prompt.md"
echo "$LATEST" > "$PREFIX/.gov-version"
echo "    已安装: AGENTS.md / ai-change-implementation-prompt.md"

# --- 软链接维护 ---
if [[ -e "$HOME/.claude/CLAUDE.md" && ! -L "$HOME/.claude/CLAUDE.md" ]]; then
  cp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.bak-$ts"
  echo "    已备份: ~/.claude/CLAUDE.md.bak-$ts（原为普通文件，改为软链接）"
fi
mkdir -p "$HOME/.claude"
ln -sf "$PREFIX/AGENTS.md" "$HOME/.claude/CLAUDE.md"
echo "    ~/.claude/CLAUDE.md → ~/.codex/AGENTS.md（软链接）"

# --- settings.json：仅首次安装，保护个人配置 ---
if [[ -f "$GLOBAL_DIR/settings.json" ]]; then
  if [[ ! -f "$HOME/.claude/settings.json" ]]; then
    cp "$GLOBAL_DIR/settings.json" "$HOME/.claude/settings.json"
    echo "    已安装: ~/.claude/settings.json（首次）"
  else
    echo "    ⚠️ 跳过 settings.json：~/.claude/settings.json 已存在（个人配置优先，团队版需人工合并）"
  fi
fi

echo "==> 完成（当前版本 ${LATEST}）。settings.local.json 与 Claude memory 未被触碰。"
