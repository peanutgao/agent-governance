#!/usr/bin/env bash
# distribute.sh — agent-governance 全局基线分发脚本
#
# 用法:
#   bash scripts/distribute.sh            # 分发
#   bash scripts/distribute.sh --rollback # 回滚到最近一次备份
#
# 行为:
#   1. 门禁：规则文件无未提交改动、VERSION 已 bump（scripts/check-version-bump.sh）
#   2. 门禁：本地仓不落后 origin（有 remote 时）——否则会把旧规则装成「最新」
#   3. 安装 global/AGENTS.md → ~/.codex/AGENTS.md，SDD 全文 → ~/.codex/ai-change-implementation-prompt.md
#      内容一致时跳过（不产生冗余备份）；内容不一致时先备份再覆盖
#   4. 维护 ~/.claude/CLAUDE.md 软链接 → ~/.codex/AGENTS.md（普通文件则先备份）
#   5. 版本提示：输出「最新版本 / 本机已装版本」
#   6. 绝不触碰 settings.json / settings.local.json / Claude memory（全部为个人层）
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_DIR="$REPO_DIR/global"
VERSION_FILE="$REPO_DIR/VERSION"
PREFIX="$HOME/.codex"
FILES=(AGENTS.md ai-change-implementation-prompt.md)

# --- 回滚 ---
if [[ "${1:-}" == "--rollback" ]]; then
  restored=0
  for f in "${FILES[@]}"; do
    latest="$(ls -t "$PREFIX/$f.bak-"* 2>/dev/null | head -1 || true)"
    if [[ -n "$latest" ]]; then
      cp "$latest" "$PREFIX/$f"
      echo "    已回滚: $f ← $(basename "$latest")"
      restored=1
    fi
  done
  if [[ "$restored" == 0 ]]; then
    echo "错误: 没有找到任何备份（$PREFIX/*.bak-*）" >&2
    exit 1
  fi
  echo "unknown" > "$PREFIX/.gov-version"
  echo "==> 回滚完成。.gov-version 置为 unknown，下次分发会重新安装。"
  exit 0
fi

# --- 校验 ---
[[ -f "$VERSION_FILE" ]] || { echo "错误: 缺少 VERSION 文件（$VERSION_FILE）" >&2; exit 1; }
for f in "${FILES[@]}"; do
  [[ -f "$GLOBAL_DIR/$f" ]] || { echo "错误: 缺少 global/$f" >&2; exit 1; }
done

bash "$REPO_DIR/scripts/check-version-bump.sh"

# --- 落后 origin 检查：装到旧规则却显示「已是最新」是最难发现的失败 ---
if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
  if git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null; then
    upstream="$(git -C "$REPO_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
    if [[ -n "$upstream" ]]; then
      behind="$(git -C "$REPO_DIR" rev-list --count "HEAD..$upstream")"
      if (( behind > 0 )); then
        echo "错误: 本地治理仓落后 $upstream $behind 个提交，会分发旧规则。先 git pull。" >&2
        exit 1
      fi
    fi
  else
    echo "    ⚠️ 无法 fetch origin（网络或权限），本次分发的是本地内容。"
  fi
else
  echo "    ⚠️ 治理仓尚未配置 origin remote——当前只能分发本机内容，团队拿不到。"
fi

LATEST="$(tr -d '[:space:]' < "$VERSION_FILE")"
INSTALLED=""
[[ -f "$PREFIX/.gov-version" ]] && INSTALLED="$(tr -d '[:space:]' < "$PREFIX/.gov-version")"

echo "==> agent-governance 全局基线分发"
echo "    最新版本: ${LATEST}"
[[ -n "$INSTALLED" ]] && echo "    本机已装: ${INSTALLED}"

mkdir -p "$PREFIX"
ts="$(date +%Y%m%d-%H%M%S)"
changed=0

for f in "${FILES[@]}"; do
  if [[ -f "$PREFIX/$f" ]] && cmp -s "$GLOBAL_DIR/$f" "$PREFIX/$f"; then
    echo "    ✓ $f 已是基线内容，跳过"
    continue
  fi
  if [[ -f "$PREFIX/$f" ]]; then
    cp "$PREFIX/$f" "$PREFIX/$f.bak-$ts"
    if [[ "$INSTALLED" == "$LATEST" ]]; then
      echo "    ⚠️ $f 与基线不一致但版本号相同——本机副本被手工改过，已备份为 $f.bak-$ts"
      echo "       （规则改动必须走治理仓 PR，本机副本会被覆盖）"
    else
      echo "    已备份: $f.bak-$ts"
    fi
  fi
  cp "$GLOBAL_DIR/$f" "$PREFIX/$f"
  echo "    已安装: $f"
  changed=1
done

echo "$LATEST" > "$PREFIX/.gov-version"

# --- 软链接维护 ---
mkdir -p "$HOME/.claude"
if [[ -e "$HOME/.claude/CLAUDE.md" && ! -L "$HOME/.claude/CLAUDE.md" ]]; then
  cp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.bak-$ts"
  echo "    已备份: ~/.claude/CLAUDE.md.bak-$ts（原为普通文件，改为软链接）"
fi
ln -sf "$PREFIX/AGENTS.md" "$HOME/.claude/CLAUDE.md"

if (( changed )); then
  echo "==> 完成（当前版本 ${LATEST}）。回滚: bash scripts/distribute.sh --rollback"
else
  echo "==> 无需更新（已是 ${LATEST}）。"
fi
echo "    settings.json / settings.local.json / Claude memory 属个人层，未被触碰。"
