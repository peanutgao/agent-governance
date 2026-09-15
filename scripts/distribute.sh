#!/usr/bin/env bash
# distribute.sh — agent-governance 个人全局基线分发脚本
#
# 用法:
#   bash scripts/distribute.sh                     # 分发
#   bash scripts/distribute.sh --rollback          # 回滚到最近一次分发前的整组快照
#   bash scripts/distribute.sh --list-targets      # 只打印目标清单，不安装
#
# 行为:
#   1. 门禁：规则文件无未提交改动、VERSION 已 bump 且严格递增（scripts/check-version-bump.sh）
#   2. 门禁：本地检查（bash -n + 非递归测试套件）
#   3. 门禁：本地仓不落后 origin（有 remote 时）。origin 存在但 fetch 失败一律失败关闭，
#      绝不「装本地旧内容还显示已是最新」
#   4. 受管路径若为软链接则拒绝安装（避免顺着链接写坏用户文件）
#   5. 安装前对全部受管路径 + .gov-version 做一次整组快照，内容一致时跳过
#   6. 绝不触碰 settings.json / settings.local.json / 个人 memory / auth / token
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_DIR="$REPO_DIR/global"
VERSION_FILE="$REPO_DIR/VERSION"
PREFIX="$HOME/.codex"
CANONICAL_AGENTS="$PREFIX/AGENTS.md"
BACKUP_ROOT="$PREFIX/.gov-backup"
WORKBUDDY_RULE_NAME="agent-governance.md"

# 允许 HOME 之外的受管目录：默认关闭，防止测试或误设环境变量写到真实用户目录。
ALLOW_EXTERNAL_TARGETS="${AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS:-0}"

# --- 目标目录解析 ---------------------------------------------------------
# 环境变量只在其位于 $HOME 之下时才被采用；否则回退到 HOME 下的默认位置并告警。
resolve_target_dir() {
  local from_env="$1"
  local fallback="$2"
  local label="$3"

  if [[ -n "$from_env" ]]; then
    if [[ "$from_env" == "$HOME"/* || "$ALLOW_EXTERNAL_TARGETS" == "1" ]]; then
      printf '%s\n' "$from_env"
      return 0
    fi
    printf '    ⚠️ 忽略 %s 指定的 HOME 之外目录: %s\n' "$label" "$from_env" >&2
    printf '       （确需安装到外部目录时设 AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS=1）\n' >&2
  fi
  printf '%s\n' "$fallback"
}

PI_AGENT_DIR="$HOME/.pi/agent"
OPENCODE_DIR="$HOME/.config/opencode"
COMMANDCODE_DIR="$HOME/.commandcode"
DSH_DIR="$(resolve_target_dir "${DSH_HOME:-}" "$HOME/.dsh" "DSH_HOME")"
WORKBUDDY_DIR="$(resolve_target_dir "${WORKBUDDY_CONFIG_DIR:-}" "$HOME/.workbuddy-ai" "WORKBUDDY_CONFIG_DIR")"
WORKBUDDY_RULE_PATH="$WORKBUDDY_DIR/rules/$WORKBUDDY_RULE_NAME"

# --- 目标定义 -------------------------------------------------------------
# copy  ：内容来自仓库源文件，逐字节比对；受管路径为软链接时拒绝安装。
# link  ：软链接到 CANONICAL_AGENTS，保证多工具共用同一份真源，不会各自漂移。
# workbuddy：WorkBuddy 的用户级规则文件需要 frontmatter，内容由源文件生成。
COPY_SOURCES=(
  "global/AGENTS.md|$PREFIX/AGENTS.md"
  "global/ai-change-implementation-prompt.md|$PREFIX/ai-change-implementation-prompt.md"
  "scripts/check-commit-attribution.sh|$PREFIX/check-commit-attribution.sh"
)

LINK_TARGETS=(
  "$HOME/.claude/CLAUDE.md|Claude Code"
  "$PI_AGENT_DIR/AGENTS.md|pi"
  "$OPENCODE_DIR/AGENTS.md|opencode"
  "$DSH_DIR/AGENTS.md|DeepSeek Harness"
  "$COMMANDCODE_DIR/AGENTS.md|commandcode"
)

# WorkBuddy 读取用户级规则的路径与上限，来自其运行时实现：
#   <configDir>/rules/*.md，frontmatter alwaysApply 为真即全量注入；
#   单文件正文上限 40000 字符，超限会被静默丢弃。
WORKBUDDY_RULE_MAX_CHARS=40000

MANAGED_PATHS=()
for entry in "${COPY_SOURCES[@]}"; do
  MANAGED_PATHS+=("${entry#*|}")
done
for entry in "${LINK_TARGETS[@]}"; do
  MANAGED_PATHS+=("${entry%|*}")
done
MANAGED_PATHS+=("$WORKBUDDY_RULE_PATH" "$PREFIX/.gov-version")

usage() {
  cat >&2 <<'USAGE'
用法:
  distribute.sh                # 分发
  distribute.sh --rollback     # 回滚到最近一次分发前的整组快照
  distribute.sh --list-targets # 打印目标清单
USAGE
}

list_targets() {
  printf '受管目标（共 %d 个）:\n' "${#MANAGED_PATHS[@]}"
  for entry in "${COPY_SOURCES[@]}"; do
    printf '  copy      %s  ←  %s\n' "${entry#*|}" "${entry%%|*}"
  done
  for entry in "${LINK_TARGETS[@]}"; do
    printf '  link      %s  →  %s  (%s)\n' "${entry%|*}" "$CANONICAL_AGENTS" "${entry#*|}"
  done
  printf '  workbuddy %s  ←  global/AGENTS.md + frontmatter\n' "$WORKBUDDY_RULE_PATH"
  printf '  state     %s  （版本记录，供门禁与回滚使用）\n' "$PREFIX/.gov-version"
}

# --- 回滚 -----------------------------------------------------------------
rollback() {
  local latest
  local restored=0
  local index dest state source

  if [[ ! -d "$BACKUP_ROOT" ]]; then
    printf '错误: 没有找到任何分发快照（%s）。\n' "$BACKUP_ROOT" >&2
    return 1
  fi

  latest="$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1 || true)"
  if [[ -z "$latest" ]]; then
    printf '错误: 没有找到任何分发快照（%s）。\n' "$BACKUP_ROOT" >&2
    return 1
  fi

  latest="${latest%/}"
  if [[ ! -f "$latest/manifest" ]]; then
    printf '错误: 快照缺少 manifest，拒绝回滚: %s\n' "$latest" >&2
    return 1
  fi

  while IFS=$'\t' read -r index dest state; do
    [[ -z "${dest:-}" ]] && continue
    if [[ "$state" == "present" ]]; then
      source="$latest/$index"
      [[ -e "$source" || -L "$source" ]] || continue
      rm -f "$dest"
      mkdir -p "$(dirname "$dest")"
      cp -a "$source" "$dest"
      printf '    已回滚: %s\n' "$dest"
      restored=$((restored + 1))
    else
      if [[ -e "$dest" || -L "$dest" ]]; then
        rm -f "$dest"
        printf '    已移除（快照中原本不存在）: %s\n' "$dest"
        restored=$((restored + 1))
      fi
    fi
  done <"$latest/manifest"

  if (( restored == 0 )); then
    printf '错误: 快照 %s 未包含任何可回滚内容。\n' "$latest" >&2
    return 1
  fi

  local current_version="unknown"
  if [[ -f "$PREFIX/.gov-version" ]]; then
    current_version="$(tr -d '[:space:]' <"$PREFIX/.gov-version")"
  fi
  printf '==> 回滚完成（快照 %s）。当前版本: %s\n' "$(basename "$latest")" "$current_version"
  printf '    如需重新装到最新基线，再跑一次 bash scripts/distribute.sh。\n'
}

# --- 门禁 -----------------------------------------------------------------
run_local_checks() {
  local suite
  local ran=0
  local file
  local -a suites=(
    tests/check-commit-attribution.sh
    tests/check-hook.sh
    tests/check-version-bump.sh
  )

  for suite in "${suites[@]}"; do
    [[ -f "$REPO_DIR/$suite" ]] || continue
    if ! bash "$REPO_DIR/$suite" >/dev/null 2>&1; then
      printf '错误: 本地检查失败，拒绝分发: %s\n' "$suite" >&2
      printf '      （单独运行可看详细输出: bash %s）\n' "$suite" >&2
      return 1
    fi
    ran=$((ran + 1))
  done

  for file in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/.githooks/*; do
    [[ -f "$file" ]] || continue
    if ! bash -n "$file" 2>/dev/null; then
      printf '错误: 语法检查失败，拒绝分发: %s\n' "$file" >&2
      return 1
    fi
  done

  if (( ran == 0 )); then
    printf '    ⚠️ 未找到本地测试套件，跳过（本仓之外的副本属于预期情况）。\n'
  else
    printf '    ✓ 本地检查通过（%d 个测试套件 + 脚本语法）\n' "$ran"
  fi
}

check_remote_freshness() {
  if ! git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
    printf '    ⚠️ 治理仓尚未配置 origin remote——当前只能分发本机内容。\n'
    return 0
  fi

  if ! git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null; then
    printf '错误: 无法 fetch origin。为避免把本地旧规则装成「已是最新」，本次分发中止。\n' >&2
    printf '      （确认网络与权限后重试；确实要分发本机内容请显式说明。）\n' >&2
    return 1
  fi

  local upstream
  upstream="$(git -C "$REPO_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    printf '    ⚠️ 当前分支没有 upstream，跳过落后检查。\n'
    return 0
  fi

  local behind
  behind="$(git -C "$REPO_DIR" rev-list --count "HEAD..$upstream")"
  if (( behind > 0 )); then
    printf '错误: 本地治理仓落后 %s %d 个提交，会分发旧规则。先 git pull。\n' "$upstream" "$behind" >&2
    return 1
  fi

  return 0
}

# --- 内容生成 -------------------------------------------------------------
workbuddy_rule_content() {
  printf -- '---\nalwaysApply: true\nenabled: true\n---\n\n'
  cat "$GLOBAL_DIR/AGENTS.md"
}

# --- 快照 -----------------------------------------------------------------
create_snapshot() {
  local snapshot_dir="$1"
  local manifest="$snapshot_dir/manifest"
  local index=0
  local dest
  local state

  mkdir -p "$snapshot_dir"
  : >"$manifest"

  for dest in "${MANAGED_PATHS[@]}"; do
    if [[ -e "$dest" || -L "$dest" ]]; then
      cp -a "$dest" "$snapshot_dir/$index"
      state="present"
    else
      state="absent"
    fi
    printf '%s\t%s\t%s\n' "$index" "$dest" "$state" >>"$manifest"
    index=$((index + 1))
  done
}

# --- 主流程 ---------------------------------------------------------------
main() {
  local mode="${1:-}"

  case "$mode" in
    --rollback)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      rollback
      return
      ;;
    --list-targets)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      list_targets
      return
      ;;
    "")
      ;;
    *)
      usage
      return 2
      ;;
  esac

  [[ -f "$VERSION_FILE" ]] || { printf '错误: 缺少 VERSION 文件（%s）\n' "$VERSION_FILE" >&2; return 1; }
  for entry in "${COPY_SOURCES[@]}"; do
    [[ -f "$REPO_DIR/${entry%%|*}" ]] || { printf '错误: 缺少 %s\n' "${entry%%|*}" >&2; return 1; }
  done

  printf '==> agent-governance 个人全局基线分发\n'

  bash "$REPO_DIR/scripts/check-version-bump.sh"
  run_local_checks
  check_remote_freshness

  local latest
  local installed=""
  latest="$(tr -d '[:space:]' < "$VERSION_FILE")"
  [[ -f "$PREFIX/.gov-version" ]] && installed="$(tr -d '[:space:]' < "$PREFIX/.gov-version")"

  printf '    最新版本: %s\n' "$latest"
  [[ -n "$installed" ]] && printf '    本机已装: %s\n' "$installed"

  # 受管 copy 目标为软链接时拒绝：写入会顺着链接改坏链接指向的真实文件。
  local entry dest
  for entry in "${COPY_SOURCES[@]}"; do
    dest="${entry#*|}"
    if [[ -L "$dest" ]]; then
      printf '错误: 受管路径是软链接，拒绝安装（避免写到链接目标）: %s\n' "$dest" >&2
      printf '      → 先删除该软链接，或改回普通文件后重试。\n' >&2
      return 1
    fi
  done

  # 预生成 WorkBuddy 规则内容，先做长度校验，避免装进去被静默丢弃。
  local workbuddy_tmp
  workbuddy_tmp="$(mktemp "${TMPDIR:-/tmp}/agent-governance-workbuddy.XXXXXX")"
  trap "rm -f '$workbuddy_tmp'" EXIT
  workbuddy_rule_content >"$workbuddy_tmp"
  local workbuddy_chars
  workbuddy_chars="$(wc -m <"$workbuddy_tmp" | tr -d '[:space:]')"
  if (( workbuddy_chars > WORKBUDDY_RULE_MAX_CHARS )); then
    printf '错误: WorkBuddy 规则正文 %s 字符，超过上限 %s，会被静默丢弃。\n' "$workbuddy_chars" "$WORKBUDDY_RULE_MAX_CHARS" >&2
    return 1
  fi

  # --- 计算变更 ---
  local -a plan_copy_src=() plan_copy_dest=() plan_link_dest=() plan_link_name=()
  local need_workbuddy=0

  for entry in "${COPY_SOURCES[@]}"; do
    local src="$REPO_DIR/${entry%%|*}"
    dest="${entry#*|}"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
      continue
    fi
    plan_copy_src+=("$src")
    plan_copy_dest+=("$dest")
  done

  for entry in "${LINK_TARGETS[@]}"; do
    dest="${entry%|*}"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$CANONICAL_AGENTS" ]]; then
      continue
    fi
    plan_link_dest+=("$dest")
    plan_link_name+=("${entry#*|}")
  done

  if [[ ! -f "$WORKBUDDY_RULE_PATH" ]] || ! cmp -s "$workbuddy_tmp" "$WORKBUDDY_RULE_PATH"; then
    need_workbuddy=1
  fi

  if (( ${#plan_copy_dest[@]} == 0 && ${#plan_link_dest[@]} == 0 && need_workbuddy == 0 )) && [[ "$installed" == "$latest" ]]; then
    printf '==> 无需更新（已是 %s）。\n' "$latest"
    printf '    settings.json / settings.local.json / 个人 memory / auth 属个人层，未被触碰。\n'
    return 0
  fi

  # --- 快照 + 安装 ---
  local ts
  local snapshot_dir
  ts="$(date +%Y%m%d-%H%M%S)"
  snapshot_dir="$BACKUP_ROOT/$ts"
  create_snapshot "$snapshot_dir"
  printf '    已快照当前状态: %s\n' "${snapshot_dir#"$HOME"/}"

  local index
  for index in "${!plan_copy_dest[@]}"; do
    dest="${plan_copy_dest[$index]}"
    mkdir -p "$(dirname "$dest")"
    cp "${plan_copy_src[$index]}" "$dest"
    printf '    已安装: %s\n' "$dest"
  done

  for index in "${!plan_link_dest[@]}"; do
    dest="${plan_link_dest[$index]}"
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$CANONICAL_AGENTS" "$dest"
    printf '    已链接: %s → %s  (%s)\n' "$dest" "$CANONICAL_AGENTS" "${plan_link_name[$index]}"
  done

  if (( need_workbuddy == 1 )); then
    mkdir -p "$(dirname "$WORKBUDDY_RULE_PATH")"
    cp "$workbuddy_tmp" "$WORKBUDDY_RULE_PATH"
    printf '    已安装: %s  (WorkBuddy 用户级规则，%s 字符)\n' "$WORKBUDDY_RULE_PATH" "$workbuddy_chars"
  fi

  printf '%s\n' "$latest" >"$PREFIX/.gov-version"

  if [[ -n "$installed" && "$installed" == "$latest" ]]; then
    printf '    ⚠️ 受管副本与基线不一致但版本号相同——本机副本被手工改过，已快照。\n'
    printf '       （规则改动请回到治理仓修改源文件，本机副本会被覆盖）\n'
  fi

  printf '==> 完成（当前版本 %s）。回滚: bash scripts/distribute.sh --rollback\n' "$latest"
  printf '    settings.json / settings.local.json / 个人 memory / auth 属个人层，未被触碰。\n'
}

main "$@"
