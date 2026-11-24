#!/usr/bin/env bash
# check-rule-paths.sh — 校验规则文件里引用的绝对路径仍然存在
#
# 用法: bash scripts/check-rule-paths.sh [--list]
#
# 背景：实证研究显示约 23% 的仓库存在指向已失效代码元素的 AI 指令引用（context rot）。
# 规则文件里的硬编码路径（~/.codex/... 等）会随目录调整静默失效，而规则内容本身看起来
# 完好无损。本脚本把「路径可达性」变成可执行的检查，而不是靠人定期复查。
#
# 只检查以 ~/ 或 $HOME/ 开头的反引号路径。仓库内相对路径由 shellcheck/测试覆盖，
# 不在本脚本断言范围内。
set -euo pipefail

_self="${BASH_SOURCE[0]:-}"
[[ -f "$_self" ]] || _self="$0"
REPO_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
cd "$REPO_DIR"

# 被检查的规则源。新增规则文件时在这里登记，否则不会被校验。
RULE_FILES=(
  global/AGENTS.md
  templates/project/AI-GOVERNANCE.md
  README.md
  onboarding.md
)

# 规则里明确写成「示例」或位于说明段落中的路径不计入。用固定前缀白名单排除。
# 每项都是一个字面路径前缀，命中即跳过。
EXEMPT_PREFIXES=(
  "/path/to/"      # onboarding 里的占位示例
  "<project>"      # 占位符
)

list_only=0
case "${1:-}" in
  --list) list_only=1 ;;
  "") ;;
  *) printf '用法: %s [--list]\n' "$0" >&2; exit 2 ;;
esac

failures=0
checked=0
declare -a missing=()

for rule in "${RULE_FILES[@]}"; do
  [[ -f "$rule" ]] || continue
  # 抓反引号或 ``` 块里的 ~/... 和 $HOME/... 绝对路径。
  while IFS= read -r raw; do
    [[ -n "$raw" ]] || continue
    checked=$((checked + 1))

    exempt=0
    for prefix in "${EXEMPT_PREFIXES[@]}"; do
      [[ "$raw" != "$prefix"* ]] || { exempt=1; break; }
    done
    (( exempt == 0 )) || continue

    # 展开 ~ 与 $HOME；去掉尾部的行内标注（如 ":24"、"，"、句号）。
    path="${raw//\$HOME/$HOME}"
    path="${path/#\~/$HOME}"
    path="${path%"${path##*[![:space:]]}"}"

    if [[ "$list_only" == 1 ]]; then
      printf '%-52s %s\n' "$rule" "$raw"
      continue
    fi

    if [[ ! -e "$path" ]]; then
      missing+=("$rule → $raw")
      failures=$((failures + 1))
    fi
  done < <(
    grep -oE '(~|\$HOME)/[^ `）)，。、；:]+' "$rule" 2>/dev/null | LC_ALL=C sort -u
  )
done

if [[ "$list_only" == 1 ]]; then
  printf '==> 共 %d 条绝对路径引用。\n' "$checked"
  exit 0
fi

if (( failures > 0 )); then
  printf '错误: 规则文件引用了 %d 个不存在的路径：\n' "$failures" >&2
  for item in "${missing[@]}"; do
    printf '  %s\n' "$item" >&2
  done
  printf '\n改法：更新路径，或从规则里删掉这条引用。\n' >&2
  exit 1
fi

printf '==> 规则内 %d 条绝对路径引用全部可达。\n' "$checked"
