#!/usr/bin/env bash
# check-rule-paths.sh — 校验规则与文档中引用的路径仍然存在
#
# 用法:
#   bash scripts/gov check paths [--list]               # 默认：静态检查仓内相对路径引用（CI 安全）
#   bash scripts/gov check paths --installed [--list]   # 检查规则内 ~/ 与 $HOME/ 本机已分发路径
#
# 背景：规则文件里的硬编码路径会随目录调整静默失效（context rot）。
# 默认模式只校验仓库内路径，不依赖任何机器的 $HOME 安装状态，可直接跑在 CI 与新设备上；
# --installed 模式用于分发完成后在本机核对用户级入口路径是否可达。
set -euo pipefail

_self="${BASH_SOURCE[0]:-}"
[[ -f "$_self" ]] || _self="$0"
REPO_DIR="$(cd "$(dirname "$_self")/../.." && pwd)"
cd "$REPO_DIR"

# 被检查的规则与文档源（默认静态模式）。
REPO_RULE_FILES=(
  AGENTS.md
  global/AGENTS.md
  templates/project/AI-GOVERNANCE.md
  README.md
  onboarding.md
  skills/README.md
  skills/local/ai-change-flow/SKILL.md
  skills/local/ai-change-flow/references/full-flow.md
  skills/local/new-project-bootstrap/SKILL.md
  skills/local/new-project-bootstrap/references/stages.md
  skills/local/new-project-bootstrap/references/existing-repo-onboarding.md
)

# 检查本机已分发路径（--installed 模式）的规则源。
INSTALLED_RULE_FILES=(
  global/AGENTS.md
  templates/project/AI-GOVERNANCE.md
  README.md
  onboarding.md
  skills/README.md
  skills/local/ai-change-flow/SKILL.md
  skills/local/new-project-bootstrap/SKILL.md
)

# --installed 模式下的豁免路径（非本仓受管副本、历史退役说明或按需创建的状态目录）。
EXEMPT_INSTALLED_PATHS=(
  "~/.claude/settings.json"
  "~/.codex/.gov-backup/"
  "~/.codex/ai-change-implementation-prompt.md"
  "~/.codex/skills"
  "~/.local/state/agent-governance/skills"
  "~/.agents/skills"
  "~/.claude/skills"
  "~/.pi/agent/skills"
  "~/.config/opencode/skills"
  "~/.dsh/skills"
  "~/.commandcode/skills"
  "~/.omp/agent/skills"
  "~/.workbuddy-ai/skills"
)

mode="repo"
list_only=0

usage() {
  printf '用法: bash scripts/gov check paths [--installed] [--list]\n' >&2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --installed) mode="installed" ;;
    --list) list_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

is_exempt_installed() {
  local raw="$1" item
  for item in "${EXEMPT_INSTALLED_PATHS[@]}"; do
    if [[ "$raw" == "$item" || "$raw" == "${item%/}" || "$raw/" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

strip_trailing_punct() {
  local val="$1"
  while [[ -n "$val" ]]; do
    case "${val: -1}" in
      '.'|','|';'|':'|')'|']'|'"'|"'"|'`') val="${val%?}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$val"
}

failures=0
checked=0
declare -a missing=()

check_repo_paths() {
  local rule raw cleaned resolved rule_dir
  for rule in "${REPO_RULE_FILES[@]}"; do
    [[ -f "$rule" ]] || continue
    rule_dir="$(dirname "$rule")"

    while IFS= read -r raw; do
      [[ -n "$raw" ]] || continue
      cleaned="${raw%%#*}"
      cleaned="$(strip_trailing_punct "$cleaned")"
      [[ -n "$cleaned" ]] || continue

      # 跳过模板占位符与通配符（如 <project>、*.md、YYYY-MM-DD）
      case "$cleaned" in
        *'*'*|*'<'*|*'>'*|*'...'*|*'$'*|*'~'*) continue ;;
      esac

      if [[ "$cleaned" == references/* ]]; then
        resolved="$rule_dir/$cleaned"
      else
        resolved="$cleaned"
      fi

      checked=$((checked + 1))
      if [[ "$list_only" == 1 ]]; then
        printf '%-52s %s -> %s\n' "$rule" "$cleaned" "$resolved"
        continue
      fi

      if [[ ! -e "$resolved" ]]; then
        missing+=("$rule → $cleaned")
        failures=$((failures + 1))
      fi
    done < <(
      {
        # 1. 明确指向本仓受控目录的相对路径
        grep -oE '(^|[^A-Za-z0-9_./~-])(global|scripts|skills|templates|tests|\.github|\.githooks)/[A-Za-z0-9._/@*-]+' "$rule" 2>/dev/null |
          sed 's/^[^A-Za-z0-9_.]//' || true
        # 2. Skill 内部相对 references/ 路径（仅对 skills/local/* 下的文档生效）
        if [[ "$rule" == skills/local/* ]]; then
          grep -oE '(^|[^A-Za-z0-9_./~-])references/[A-Za-z0-9._/@*-]+' "$rule" 2>/dev/null |
            sed 's/^[^A-Za-z0-9_.]//' || true
        fi
      } | LC_ALL=C sort -u
    )

    # 3. Markdown 相对链接 [text](target)（排除 http/https/mailto/#anchor）
    while IFS= read -r raw; do
      [[ -n "$raw" ]] || continue
      cleaned="${raw#](}"
      cleaned="${cleaned%)}"
      cleaned="${cleaned%%#*}"
      [[ -n "$cleaned" ]] || continue
      case "$cleaned" in
        http://*|https://*|mailto:*|/*|*'<'*|*'>'*|*'*'*) continue ;;
      esac
      resolved="$rule_dir/$cleaned"
      checked=$((checked + 1))
      if [[ "$list_only" == 1 ]]; then
        printf '%-52s %s -> %s\n' "$rule" "$cleaned" "$resolved"
        continue
      fi
      if [[ ! -e "$resolved" ]]; then
        missing+=("$rule → $cleaned")
        failures=$((failures + 1))
      fi
    done < <(
      grep -oE '\]\([^()[:space:]]+\)' "$rule" 2>/dev/null | LC_ALL=C sort -u || true
    )
  done
}

check_installed_paths() {
  local rule raw path
  for rule in "${INSTALLED_RULE_FILES[@]}"; do
    [[ -f "$rule" ]] || continue
    while IFS= read -r raw; do
      [[ -n "$raw" ]] || continue
      raw="$(strip_trailing_punct "$raw")"
      [[ -n "$raw" ]] || continue

      case "$raw" in
        *'*'*|*'<'*|*'>'*|*'...'*) continue ;;
      esac

      if is_exempt_installed "$raw"; then
        continue
      fi

      checked=$((checked + 1))
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
      grep -oE '(~|\$HOME)/[^ `"'"'"'（）()，。、；:」』】》]+' "$rule" 2>/dev/null | LC_ALL=C sort -u || true
    )
  done
}

if [[ "$mode" == "installed" ]]; then
  check_installed_paths
  label="本机绝对路径"
else
  check_repo_paths
  label="仓内路径"
fi

if [[ "$list_only" == 1 ]]; then
  printf '==> 共 %d 条%s引用。\n' "$checked" "$label"
  exit 0
fi

if (( failures > 0 )); then
  printf '错误: 规则文件引用了 %d 个不存在的%s：\n' "$failures" "$label" >&2
  for item in "${missing[@]}"; do
    printf '  %s\n' "$item" >&2
  done
  printf '\n改法：更新路径，或从规则里删掉这条引用。\n' >&2
  exit 1
fi

printf '==> 规则内 %d 条%s引用全部可达。\n' "$checked" "$label"
