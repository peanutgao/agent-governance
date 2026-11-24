#!/usr/bin/env bash
# distribute.sh — agent-governance 个人全局基线分发脚本
#
# 用法:
#   bash scripts/distribute.sh                     # 分发
#   bash scripts/distribute.sh --rollback          # 回滚到最近一次分发前的整组快照
#   bash scripts/distribute.sh --check             # 只校验已安装副本，不一致退出 1
#   bash scripts/distribute.sh --list-targets      # 只打印目标清单，不安装
#
# 行为:
#   1. 门禁：规则文件无未提交改动、VERSION 已 bump 且严格递增（scripts/check-version-bump.sh）
#   2. 门禁：本地检查（bash -n + 非递归测试套件）
#   3. 门禁：本地仓不落后 origin（有 remote 时）。origin 存在但 fetch 失败一律失败关闭，
#      绝不「装本地旧内容还显示已是最新」
#   4. 安装前校验受管目标类型、父目录和冲突，并阻止并行分发
#   5. 安装前对全部受管路径 + .gov-version 做一次整组快照，内容一致时跳过
#   6. 绝不触碰 settings.json / settings.local.json / 个人 memory / auth / token
set -euo pipefail

_self="${BASH_SOURCE[0]:-}"
[[ -f "$_self" ]] || _self="$0"
REPO_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
GLOBAL_DIR="$REPO_DIR/global"
VERSION_FILE="$REPO_DIR/VERSION"
DEVICE_HOME="$HOME"
native_windows=0
case "$(uname -s)" in
  MINGW*|MSYS*)
    native_windows=1
    DEVICE_HOME="$(cygpath -u "$USERPROFILE")"
    ;;
esac
PREFIX="$DEVICE_HOME/.codex"
CANONICAL_AGENTS="$PREFIX/AGENTS.md"
HOOKS_DIR="$PREFIX/git-hooks"
BACKUP_ROOT="$PREFIX/.gov-backup"
WORKBUDDY_RULE_NAME="agent-governance.md"

# 允许 HOME 之外的受管目录：默认关闭，防止测试或误设环境变量写到真实用户目录。
ALLOW_EXTERNAL_TARGETS="${AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS:-0}"

safe_path_syntax() {
  case "$1/" in
    *'/../'*|*'/./'*|*'//'*|*'|'*|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 目标目录解析 ---------------------------------------------------------
# 环境变量只在其位于 $DEVICE_HOME 之下时才被采用；否则回退到 HOME 下的默认位置并告警。
resolve_target_dir() {
  local from_env="$1"
  local fallback="$2"
  local label="$3"

  if [[ -n "$from_env" ]]; then
    if [[ "$native_windows" == 1 ]]; then
      from_env="$(cygpath -au "$from_env")"
    fi
    from_env="${from_env%/}"
    if ! safe_path_syntax "$from_env"; then
      printf '错误: %s 必须是无路径跳转的绝对目录。\n' "$label" >&2
      return 1
    fi
    if [[ "$from_env" == "$DEVICE_HOME"/* || "$ALLOW_EXTERNAL_TARGETS" == "1" ]]; then
      printf '%s\n' "$from_env"
      return 0
    fi
    printf '    ⚠️ 忽略 %s 指定的 HOME 之外目录: %s\n' "$label" "$from_env" >&2
    printf '       （确需安装到外部目录时设 AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS=1）\n' >&2
  fi
  printf '%s\n' "$fallback"
}

PI_AGENT_DIR="$DEVICE_HOME/.pi/agent"
OMP_AGENT_DIR="$DEVICE_HOME/.omp/agent"
OPENCODE_DIR="$DEVICE_HOME/.config/opencode"
COMMANDCODE_DIR="$DEVICE_HOME/.commandcode"
ZED_DIR="$DEVICE_HOME/.config/zed"
AMP_DIR="$DEVICE_HOME/.config/amp"
COPILOT_DIR="$DEVICE_HOME/.copilot"
DSH_DIR="$(resolve_target_dir "${DSH_HOME:-}" "$DEVICE_HOME/.dsh" "DSH_HOME")"
WORKBUDDY_DIR="$(resolve_target_dir "${WORKBUDDY_CONFIG_DIR:-}" "$DEVICE_HOME/.workbuddy-ai" "WORKBUDDY_CONFIG_DIR")"
WORKBUDDY_RULE_PATH="$WORKBUDDY_DIR/rules/$WORKBUDDY_RULE_NAME"

# OrbStack 等虚拟机把本机 work 目录共享进 VM 后，VM 内的 AI 工具（如 Claude Code）
# 读不到宿主机的 ~/.claude / ~/.codex 用户级入口；work 根目录的 CLAUDE.md 是它们经
# 挂载能看到的唯一祖先约束入口。用普通文件副本而非软链：不依赖 VM 侧是否也共享 home，
# 对任何挂载拓扑都成立。Claude Code 会从 cwd 向上逐级读取祖先目录的 CLAUDE.md。
WORK_SHARE_DIR="$DEVICE_HOME/Documents/work"

# --- 目标定义 -------------------------------------------------------------
# copy  ：内容来自仓库源文件，逐字节比对；受管路径为软链接时拒绝安装。
# link  ：软链接到 CANONICAL_AGENTS，保证多工具共用同一份真源，不会各自漂移。
# workbuddy：WorkBuddy 的用户级规则文件需要 frontmatter，内容由源文件生成。
COPY_SOURCES=(
  "global/AGENTS.md|$PREFIX/AGENTS.md"
  "scripts/check-commit-attribution.sh|$PREFIX/check-commit-attribution.sh"
  "global/git-hooks/commit-msg|$HOOKS_DIR/commit-msg"
  "global/git-hooks/_chain|$HOOKS_DIR/_chain"
  "global/git-hooks/pre-commit|$HOOKS_DIR/pre-commit"
  "global/git-hooks/pre-push|$HOOKS_DIR/pre-push"
  "global/AGENTS.md|$WORK_SHARE_DIR/CLAUDE.md"
  # Copilot CLI 的个人级指令只认这个文件名，不读 AGENTS.md，因此单独分发一份内容副本。
  "global/AGENTS.md|$COPILOT_DIR/copilot-instructions.md"
)

LINK_TARGETS=(
  "$DEVICE_HOME/.claude/CLAUDE.md|Claude Code"
  "$PI_AGENT_DIR/AGENTS.md|pi"
  "$OMP_AGENT_DIR/AGENTS.md|omp"
  "$OPENCODE_DIR/AGENTS.md|opencode"
  "$DSH_DIR/AGENTS.md|DeepSeek Harness"
  "$COMMANDCODE_DIR/AGENTS.md|commandcode"
  "$ZED_DIR/AGENTS.md|Zed"
  "$AMP_DIR/AGENTS.md|Amp"
)

# 需要 AGENTS.md 的厂商级入口。这些工具的用户级约定各不相同：Copilot 只认
# copilot-instructions.md，WorkBuddy 只认 rules/*.md + frontmatter，其余读 AGENTS.md。
# 单独列出以便按各自形态生成，不混进 LINK_TARGETS 的统一处理。
COPILOT_INSTRUCTIONS_PATH="$COPILOT_DIR/copilot-instructions.md"

if [[ "$native_windows" == 1 ]]; then
  for entry in "${LINK_TARGETS[@]}"; do
    COPY_SOURCES+=("global/AGENTS.md|${entry%|*}")
  done
  LINK_TARGETS=()
fi

# 各工具对用户级规则文件的正文长度上限。超限时这些工具是「静默丢弃」而不是报错，
# 规则看起来装好了、实际不生效，因此分发前必须自己拦住。
#   WorkBuddy ：<configDir>/rules/*.md，frontmatter alwaysApply 为真即全量注入，上限 40000 字符。
#   Windsurf  ：global_rules.md 单文件 12000 字符（docs.devin.ai/windsurf）。
#   Antigravity：单文件 24000 字节，另有全局 20000 token 总预算。
# 未在这些工具实现中确认「超限静默丢弃」的入口不做长度断言，只记录观察值。
WORKBUDDY_RULE_MAX_CHARS=40000
GLOBAL_RULE_MAX_CHARS=40000

# 已退役的受管路径：曾由本仓分发，现已从清单移除。
# 不做退役清理会留下孤儿副本——它不再被比对、不再被更新，却仍在被工具读取，
# 等于把过时规则留在本机。分发时删除，删除前同样纳入整组快照。
RETIRED_PATHS=(
  "$PREFIX/ai-change-implementation-prompt.md"
)

MANAGED_PATHS=()
for entry in "${COPY_SOURCES[@]}"; do
  MANAGED_PATHS+=("${entry#*|}")
done
for entry in "${LINK_TARGETS[@]}"; do
  MANAGED_PATHS+=("${entry%|*}")
done
MANAGED_PATHS+=("$WORKBUDDY_RULE_PATH" "$PREFIX/.gov-version")

lock_dir=
workbuddy_tmp=
staged_file=
pending_snapshot=
release_root=
cleanup() {
  [[ -z "$staged_file" ]] || rm -f "$staged_file"
  [[ -z "$workbuddy_tmp" ]] || rm -f "$workbuddy_tmp"
  [[ -z "$pending_snapshot" ]] || rm -rf "$pending_snapshot"
  [[ -z "$release_root" ]] || rm -rf "$release_root"
  [[ -z "$lock_dir" ]] || rmdir "$lock_dir"
}
trap cleanup EXIT

validate_parent() {
  local path="$1" parent
  safe_path_syntax "$path" || return 1
  [[ "$path" == "$DEVICE_HOME"/* || "$ALLOW_EXTERNAL_TARGETS" == "1" ]] || return 1
  parent="$(dirname "$path")"
  while [[ "$parent" != "$DEVICE_HOME" && "$parent" != / ]]; do
    if [[ -L "$parent" || ( -e "$parent" && ! -d "$parent" ) ]]; then
      printf '错误: 受管路径的父目录不是普通目录: %s\n' "$parent" >&2
      return 1
    fi
    parent="$(dirname "$parent")"
  done
}

validate_target() {
  local path="$1" allow_link="$2"
  validate_parent "$path" || return 1
  if [[ -L "$path" ]]; then
    [[ "$allow_link" == 1 ]] && return 0
  elif [[ ! -e "$path" || -f "$path" ]]; then
    return 0
  fi
  printf '错误: 受管目标类型不安全: %s\n' "$path" >&2
  return 1
}

preflight() (
  shopt -s nocasematch
  local i j entry
  for i in "${!MANAGED_PATHS[@]}"; do
    for ((j = 0; j < i; j++)); do
      if [[ "${MANAGED_PATHS[$i]}" == "${MANAGED_PATHS[$j]}" ||
        "${MANAGED_PATHS[$i]}" == "${MANAGED_PATHS[$j]}/"* ||
        "${MANAGED_PATHS[$j]}" == "${MANAGED_PATHS[$i]}/"* ]]; then
        printf '错误: 受管目标冲突: %s 与 %s\n' "${MANAGED_PATHS[$i]}" "${MANAGED_PATHS[$j]}" >&2
        return 1
      fi
    done
  done
  for entry in "${COPY_SOURCES[@]}"; do
    validate_target "${entry#*|}" 0 || return 1
  done
  for entry in "${LINK_TARGETS[@]}"; do
    validate_target "${entry%|*}" 1 || return 1
  done
  validate_target "$WORKBUDDY_RULE_PATH" 0 &&
    validate_target "$PREFIX/.gov-version" 0 &&
    validate_parent "$BACKUP_ROOT/manifest" || return 1
  if [[ "$native_windows" == 1 ]]; then
    python - "${MANAGED_PATHS[@]}" "$BACKUP_ROOT" <<'PY_WINDOWS'
import stat
import sys
from pathlib import Path

home = Path.home()
for argument in sys.argv[1:]:
    path = Path(argument)
    for part in (path, *path.parents):
        if part == home or part == Path(part.anchor):
            break
        try:
            attributes = part.lstat().st_file_attributes
        except FileNotFoundError:
            continue
        if attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise SystemExit(f"Windows deployment target is a reparse point: {part}")
PY_WINDOWS
  fi
)

acquire_lock() {
  mkdir -p "$BACKUP_ROOT"
  if ! mkdir "$BACKUP_ROOT/.lock"; then
    printf '错误: 已有分发或回滚持锁，或上次操作异常退出，请核对进程后再处理锁目录。\n' >&2
    return 1
  fi
  lock_dir="$BACKUP_ROOT/.lock"
}

install_copy() {
  local source="$1" path="$2" executable="${3:-0}"
  validate_target "$path" 0 || return 1
  mkdir -p "$(dirname "$path")"
  staged_file="$(mktemp "$(dirname "$path")/.governance.XXXXXX")"
  cp -p "$source" "$staged_file"
  if [[ "$executable" == 1 ]]; then
    chmod +x "$staged_file"
  fi
  mv -f "$staged_file" "$path"
  staged_file=
}

usage() {
  cat >&2 <<'USAGE'
用法:
  distribute.sh                # 分发
  distribute.sh --check        # 只校验已安装副本与源文件是否一致（不一致退出 1）
  distribute.sh --rollback     # 回滚到最近一次分发前的整组快照
  distribute.sh --list-targets # 打印目标清单
USAGE
}

# --- 一致性校验 -----------------------------------------------------------
# 只比较，不安装。用于回答「本机副本是否还等于治理仓源文件」：
# 手工改过本机副本、或某个工具入口仍是旧版时，这里会列出来并退出 1。
check_installed() {
  local drifts=0
  local entry src dest generated

  for entry in "${COPY_SOURCES[@]}"; do
    src="$REPO_DIR/${entry%%|*}"
    dest="${entry#*|}"
    if [[ ! -f "$src" || ! -e "$dest" ]]; then
      printf '缺失  %s\n' "$dest" >&2
      drifts=$((drifts + 1))
    elif ! cmp -s "$src" "$dest"; then
      printf '不一致 %s  ←  %s\n' "$dest" "${entry%%|*}" >&2
      drifts=$((drifts + 1))
    elif [[ "$dest" == "$HOOKS_DIR/"* && ! -x "$dest" ]]; then
      printf '不可执行 %s\n' "$dest" >&2
      drifts=$((drifts + 1))
    fi
  done

  for entry in "${LINK_TARGETS[@]}"; do
    dest="${entry%|*}"
    if [[ ! -L "$dest" || "$(readlink "$dest")" != "$CANONICAL_AGENTS" ]]; then
      printf '非软链 %s  →  %s  (%s)\n' "$dest" "$CANONICAL_AGENTS" "${entry#*|}" >&2
      drifts=$((drifts + 1))
    fi
  done

  generated="$(mktemp "${TMPDIR:-/tmp}/agent-governance-check.XXXXXX")"
  workbuddy_rule_content >"$generated"
  if [[ ! -f "$WORKBUDDY_RULE_PATH" ]]; then
    printf '缺失  %s\n' "$WORKBUDDY_RULE_PATH" >&2
    drifts=$((drifts + 1))
  elif ! cmp -s "$generated" "$WORKBUDDY_RULE_PATH"; then
    printf '不一致 %s  ←  global/AGENTS.md + frontmatter\n' "$WORKBUDDY_RULE_PATH" >&2
    drifts=$((drifts + 1))
  fi
  rm -f "$generated"

  local latest installed=""
  latest="$(tr -d '[:space:]' <"$VERSION_FILE")"
  [[ -f "$PREFIX/.gov-version" ]] && installed="$(tr -d '[:space:]' <"$PREFIX/.gov-version")"
  if ! cmp -s "$PREFIX/.gov-version" "$VERSION_FILE"; then
    printf '版本  已装 %s / 最新 %s\n' "${installed:-<none>}" "$latest" >&2
    drifts=$((drifts + 1))
  fi

  local legacy_ok=1
  check_no_legacy_override || legacy_ok=0
  if (( drifts > 0 )); then
    printf '==> %d 处与治理仓 %s 不一致。修复：bash scripts/distribute.sh\n' "$drifts" "$latest" >&2
    return 1
  fi
  printf '==> 全部受管副本与当前工作树 %s 一致。\n' "$latest"
  [[ "$legacy_ok" == 1 ]] || return 1
  printf '==> Git 保留原有钩子选择。归属门禁须在各项目及其 CI 中验证。\n'
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
  printf '  git       检测并移除直接配置的旧治理目录覆盖 %s\n' "$HOOKS_DIR"
  printf '\n长度门禁: AGENTS.md ≤ %s 字符；WorkBuddy 规则 ≤ %s 字符（超限会被工具静默丢弃）\n' \
    "$GLOBAL_RULE_MAX_CHARS" "$WORKBUDDY_RULE_MAX_CHARS"
}

# --- 回滚 -----------------------------------------------------------------
rollback() {
  preflight
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    printf '错误: 没有分发快照。\n' >&2
    return 1
  fi
  acquire_lock
  check_no_legacy_override
  local latest
  latest="$(ls -1d "$BACKUP_ROOT"/[0-9]*/ 2>/dev/null | LC_ALL=C sort | tail -1 || true)"
  latest="${latest%/}"
  if [[ -z "$latest" || -L "$latest" || ! -f "$latest/manifest" || -L "$latest/manifest" ]]; then
    printf '错误: 未找到有效的快照清单。\n' >&2
    return 1
  fi

  local index dest state extra expected
  local count=0
  local -a states=()
  while IFS=$'\t' read -r index dest state extra; do
    expected="${MANAGED_PATHS[$count]:-}"
    if [[ "$index" != "$count" || -z "$expected" || "$dest" != "$expected" || -n "$extra" ]]; then
      printf '错误: 快照清单中的序号或目标无效: %s\n' "$latest/manifest" >&2
      return 1
    fi
    case "$state" in
      present)
        if [[ ! -f "$latest/$index" && ! -L "$latest/$index" ]]; then
          printf '错误: 快照缺少备份文件: %s/%s\n' "$latest" "$index" >&2
          return 1
        fi
        if [[ -L "$latest/$index" ]]; then
          local link_entry found=0
          for link_entry in "${LINK_TARGETS[@]}"; do
            [[ "$dest" != "${link_entry%|*}" ]] || found=1
          done
          if [[ "$found" != 1 ]]; then
            printf '错误: 非链接目标的备份是软链接: %s\n' "$dest" >&2
            return 1
          fi
        fi
        ;;
      absent) ;;
      *) printf '错误: 快照状态无效: %s\n' "$state" >&2; return 1 ;;
    esac
    states+=("$state")
    count=$((count + 1))
  done <"$latest/manifest"
  expected="${#MANAGED_PATHS[@]}"
  if [[ "$count" != "$expected" ]]; then
    printf '错误: 快照清单不完整，当前 %s 项，预期 %s 项。\n' "$count" "$expected" >&2
    return 1
  fi

  for index in "${!states[@]}"; do
    dest="${MANAGED_PATHS[$index]}"
    validate_target "$dest" 1
    if [[ "${states[$index]}" == absent ]]; then
      rm -f "$dest"
    elif [[ -L "$latest/$index" ]]; then
      mkdir -p "$(dirname "$dest")"
      ln -sfn "$(readlink "$latest/$index")" "$dest"
    else
      # 被恢复的入口可能当前是受管软链。先去掉入口，再安全写入文件。
      if [[ -L "$dest" ]]; then
        rm -f "$dest"
      fi
      install_copy "$latest/$index" "$dest"
    fi
  done

  printf '==> 回滚完成（快照 %s）。\n' "$(basename "$latest")"
}

# --- 门禁 -----------------------------------------------------------------
run_local_checks() {
  local suite
  local ran=0
  local file
  local -a suites=(
    tests/check-commit-attribution.sh
    tests/check-hook.sh
    tests/check-global-hook.sh
    tests/check-version-bump.sh
    tests/check-rule-paths.sh
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
  upstream="$(git -C "$REPO_DIR" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ "$upstream" != refs/remotes/origin/* ]]; then
    upstream="$(git -C "$REPO_DIR" symbolic-ref --quiet refs/remotes/origin/HEAD || true)"
  fi
  if [[ "$upstream" != refs/remotes/origin/* ]]; then
    printf '错误: 无法确定 origin 的对照分支。\n' >&2
    return 1
  fi

  local behind
  behind="$(git -C "$REPO_DIR" rev-list --count "HEAD..$upstream")"
  if (( behind > 0 )); then
    printf '错误: 本地治理仓落后 %s %d 个提交，会分发旧规则。先 git pull。\n' "$upstream" "$behind" >&2
    return 1
  fi

  return 0
}

# --- 迁移旧版全局钩子配置 --------------------------------------------------
# 只从直接全局配置中删除旧版分发自己写入的字面值；包含文件和其他配置保持原状。
configured_hooks_path() {
  local value status
  if value="$(git config --global --includes --path --get core.hooksPath)"; then
    printf '%s\n' "$value"
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
    if value="$(git config --system --includes --path --get core.hooksPath)"; then
      printf '%s\n' "$value"
    else
      status=$?
      [[ "$status" == 1 ]] || return "$status"
    fi
  fi
}

check_no_legacy_override() {
  local path
  path="$(configured_hooks_path)" || return 1
  if [[ "$path" == "$HOOKS_DIR" || ( -n "$path" && "$path" -ef "$HOOKS_DIR" ) ]]; then
    printf '错误: Git 仍全局覆盖为旧治理目录 %s，项目原生钩子会受影响。\n' "$path" >&2
    printf '直接旧配置可由分发迁移；若来自包含文件或系统配置，请在对应来源处理。\n' >&2
    return 1
  fi
}

remove_legacy_override() {
  local direct status
  if direct="$(git config --global --no-includes --get-all core.hooksPath)"; then
    if printf '%s\n' "$direct" | grep -Fxq -- "$HOOKS_DIR"; then
      git config --global --fixed-value --unset-all core.hooksPath "$HOOKS_DIR"
      printf '    已移除旧治理目录的全局覆盖。各项目需验证自己的提交归属检查。\n'
    fi
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  check_no_legacy_override
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

# --- 退役路径清理 ---------------------------------------------------------
# 删除不再受管的旧分发副本。退役路径刻意不进 MANAGED_PATHS：那会改变快照清单的
# 项数契约，使既有快照无法回滚。删除前把内容移到独立的 retired 目录，可人工恢复。
remove_retired_paths() {
  local retired=()
  local path
  for path in "${RETIRED_PATHS[@]}"; do
    [[ -e "$path" || -L "$path" ]] || continue
    retired+=("$path")
  done
  (( ${#retired[@]} > 0 )) || return 0

  local backup_dir
  backup_dir="$BACKUP_ROOT/retired-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir" || return 1
  for path in "${retired[@]}"; do
    local name
    name="$(printf '%s' "$path" | tr '/' '_')"
    mv "$path" "$backup_dir/$name" || return 1
    printf '    已退役: %s（备份于 %s）\n' "$path" "${backup_dir#"$DEVICE_HOME"/}"
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
    --check)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      [[ -f "$VERSION_FILE" ]] || { printf '错误: 缺少 VERSION 文件（%s）\n' "$VERSION_FILE" >&2; return 1; }
      preflight
      check_installed
      return
      ;;
    --list-targets)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      preflight
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

  preflight
  local release_commit
  release_commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
  bash "$REPO_DIR/scripts/check-version-bump.sh"
  run_local_checks
  check_remote_freshness
  if [[ "$(git -C "$REPO_DIR" rev-parse HEAD)" != "$release_commit" ]]; then
    printf '错误: 治理仓提交在验证期间发生变化，请重新运行。\n' >&2
    return 1
  fi
  release_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-governance-release.XXXXXX")"
  git -C "$REPO_DIR" archive "$release_commit" VERSION global scripts/check-commit-attribution.sh |
    tar -xf - -C "$release_root"
  GLOBAL_DIR="$release_root/global"
  VERSION_FILE="$release_root/VERSION"
  acquire_lock
  preflight

  local latest
  local installed=""
  latest="$(tr -d '[:space:]' < "$VERSION_FILE")"
  [[ -f "$PREFIX/.gov-version" ]] && installed="$(tr -d '[:space:]' < "$PREFIX/.gov-version")"

  printf '    最新版本: %s\n' "$latest"
  [[ -n "$installed" ]] && printf '    本机已装: %s\n' "$installed"

  local entry dest
  # 长度门禁：规则正文超过工具上限时，工具通常「静默丢弃」而不是报错——规则看起来装好了、
  # 实际不生效。分发前必须先拦住，不能把失效的安装当成成功。
  local agents_chars
  agents_chars="$(wc -m <"$GLOBAL_DIR/AGENTS.md" | tr -d '[:space:]')"
  if (( agents_chars > GLOBAL_RULE_MAX_CHARS )); then
    printf '错误: AGENTS.md 正文 %s 字符，超过通用上限 %s，部分工具会静默丢弃。\n' "$agents_chars" "$GLOBAL_RULE_MAX_CHARS" >&2
    return 1
  fi

  # 提前生成 WorkBuddy 规则，避免发布超过工具的长度限制的内容。
  workbuddy_tmp="$(mktemp "${TMPDIR:-/tmp}/agent-governance-workbuddy.XXXXXX")"
  workbuddy_rule_content >"$workbuddy_tmp"
  local workbuddy_chars
  workbuddy_chars="$(wc -m <"$workbuddy_tmp" | tr -d '[:space:]')"
  if (( workbuddy_chars > WORKBUDDY_RULE_MAX_CHARS )); then
    printf '错误: WorkBuddy 规则正文 %s 字符，超过上限 %s，会被静默丢弃。\n' "$workbuddy_chars" "$WORKBUDDY_RULE_MAX_CHARS" >&2
    return 1
  fi

  local -a plan_copy_src=() plan_copy_dest=() plan_link_dest=() plan_link_name=()
  local need_workbuddy=0

  for entry in "${COPY_SOURCES[@]}"; do
    local src="$release_root/${entry%%|*}"
    dest="${entry#*|}"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest" &&
      [[ "$dest" != "$HOOKS_DIR/"* || -x "$dest" ]]; then
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

  remove_legacy_override

  # 退役清理要在「无需更新」短路之前：孤儿副本本身就是需要处理的状态。
  local retired_count=0
  for entry in "${RETIRED_PATHS[@]}"; do
    [[ -e "$entry" || -L "$entry" ]] && retired_count=$((retired_count + 1))
  done

  if (( ${#plan_copy_dest[@]} == 0 && ${#plan_link_dest[@]} == 0 && need_workbuddy == 0 && retired_count == 0 )) && cmp -s "$PREFIX/.gov-version" "$VERSION_FILE"; then
    printf '==> 无需更新（已是 %s）。\n' "$latest"
    printf '    settings.json / settings.local.json / 个人 memory / auth 属个人层，未被触碰。\n'
    return 0
  fi

  local ts snapshot_dir sequence=0
  ts="$(date +%Y%m%d-%H%M%S)"
  while :; do
    snapshot_dir="$(printf '%s/%s-%08d' "$BACKUP_ROOT" "$ts" "$sequence")"
    [[ ! -e "$snapshot_dir" && ! -L "$snapshot_dir" ]] && break
    sequence=$((sequence + 1))
  done
  pending_snapshot="$(mktemp -d "$BACKUP_ROOT/.pending.XXXXXX")"
  create_snapshot "$pending_snapshot"
  mv "$pending_snapshot" "$snapshot_dir"
  pending_snapshot=
  printf '    已快照当前状态: %s\n' "${snapshot_dir#"$DEVICE_HOME"/}"

  local index executable
  for index in "${!plan_copy_dest[@]}"; do
    dest="${plan_copy_dest[$index]}"
    executable=0
    [[ "$dest" != "$HOOKS_DIR/"* ]] || executable=1
    install_copy "${plan_copy_src[$index]}" "$dest" "$executable"
    printf '    已安装: %s\n' "$dest"
  done

  for index in "${!plan_link_dest[@]}"; do
    dest="${plan_link_dest[$index]}"
    validate_target "$dest" 1
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$CANONICAL_AGENTS" "$dest"
    printf '    已链接: %s → %s  (%s)\n' "$dest" "$CANONICAL_AGENTS" "${plan_link_name[$index]}"
  done

  if (( need_workbuddy == 1 )); then
    install_copy "$workbuddy_tmp" "$WORKBUDDY_RULE_PATH"
    printf '    已安装: %s  (WorkBuddy 用户级规则，%s 字符)\n' "$WORKBUDDY_RULE_PATH" "$workbuddy_chars"
  fi

  remove_retired_paths

  install_copy "$VERSION_FILE" "$PREFIX/.gov-version"

  if [[ -n "$installed" && "$installed" == "$latest" ]]; then
    printf '    ⚠️ 受管副本与基线不一致但版本号相同，已快照并修复。\n'
    printf '       （规则改动请回到治理仓修改源文件，本机副本会被覆盖）\n'
  fi

  printf '==> 完成（当前版本 %s）。回滚: bash scripts/distribute.sh --rollback\n' "$latest"
  printf '    settings.json / settings.local.json / 个人 memory / auth 属个人层，未被触碰。\n'
}

main "$@"
