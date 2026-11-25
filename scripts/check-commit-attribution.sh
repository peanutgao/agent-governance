#!/usr/bin/env bash
set -euo pipefail

# check-commit-attribution.sh
#
# 检查新的 Git commit 和提交身份是否披露 AI、模型、Agent 或 Bot 信息。
# 该脚本只读 message/commit metadata，不自动改写提交、Git 配置或历史。
#
# 三层检查，词表按用途分开，避免互相污染：
#   1. co-author trailer —— message 里出现 Co-Authored-By 等合作作者归属声明。
#   2. identity —— author / committer 姓名或邮箱出现 AI 或自动化身份标识。
#   3. message 披露短语 —— message 正文出现「AI 参与」的明确表述。
#
# message 层只匹配「披露短语」，不匹配裸词。原因是 ai / agent / assistant / bot 这类词
# 在正常提交里大量出现（产品功能名、通用英文词），整词拦截会拦下合法提交，逼人改写
# commit message 绕开词表，规则反而失去意义。裸词判断放在 identity 层，那里出现这些词
# 基本等于身份披露。
#
# --governance：治理仓自身用于定义本政策的提交必须能描述「AI 归属」这件事，
# 因此该模式下跳过第 3 层，只保留 trailer 与 identity 两层硬检查。
#
# 注意：--audit-history 会对政策生效前（含 Co-Authored-By 的旧 commit）报红，这是
# 「历史不重写」的预期行为，不是回归；日常用 --range 只查新增 commit。

usage() {
  cat >&2 <<'USAGE'
用法:
  check-commit-attribution.sh --message <commit-message-file> [--governance]
  check-commit-attribution.sh --commit <commit-sha> [--governance]
  check-commit-attribution.sh --range <git-revision-range> [--governance]
  check-commit-attribution.sh --audit-history
  check-commit-attribution.sh --print-policy [--governance]

选项:
  --governance    跳过 message 披露短语检查（仍查 co-author trailer 与身份）
  --print-policy  打印当前生效的拦截清单

退出码: 0 通过 / 1 发现违规 / 2 用法或环境错误
USAGE
}

CO_AUTHOR_TRAILER_REGEX='^[[:space:]]*co[[:space:]_.-]*author(ed)?[[:space:]_.-]*(by)?[[:space:]]*:'
GIT_SCISSORS_REGEX='^#[[:space:]]*-+[[:space:]]*>8[[:space:]]*-+[[:space:]]*$'

# --- 身份层 ---------------------------------------------------------------
# 大小写不敏感。不含 agent ——「Agent Smith」这类人类姓名会被误伤。
# 不含裸 ai ——「Ai Wei」这类真实姓名会被误伤；裸 AI 由下面的全大写规则兜住。
# 不含短歧义词（如 amp/omp），只收录明确无歧义的 AI/自动化标识。
KNOWN_AI_IDENTITY_REGEX='(^|[^[:alnum:]])(人工智能|llm|large[[:space:]_.-]+language[[:space:]_.-]+model|chatgpt|gpt|openai|anthropic|claude|claudecode|codex|copilot|cursor|codeium|gemini|deepseek|qwen|mistral|minimax|aider|windsurf|replit|superpowers|commandcode\.ai|commandcodebot|workbuddy|codebuddy|antigravity|opencode|devin|cline|roocode|trae|augment|junie|assistant|bot|[[:alnum:]]+[._-]bot|bot[._-][[:alnum:]]+|[[:alnum:]]+\[bot\])([^[:alnum:]]|$)'

# 身份层的补充：只匹配全大写 AI，避免把「Ai Wei」这类真实姓名拦下。
UPPERCASE_AI_IDENTITY_REGEX='(^|[^[:alnum:]])AI([^[:alnum:]]|$)'

# --- message 披露短语层 ---------------------------------------------------
# 匹配对本次提交或实现的归属。功能名、普通生成物和领域术语本身可用。
MESSAGE_AI_ACTION_REGEX='^[[:space:]]*([[:alnum:]_()/.-]+:[[:space:]]*)?(ai|a[[:space:]_.-]*i)([[:space:]_.-]+(agent|assistant))?[[:space:]_.-]+(assisted|generated|authored|written|implemented|produced|created)[[:space:]_.-]+(commit|patch|change|implementation|code|diff)([^[:alnum:]]|$)'
MESSAGE_GENERATED_BY_REGEX='(^[[:space:]]*([[:alnum:]_()/.-]+:[[:space:]]*)?|(^|[^[:alnum:]])(commit|patch|change|implementation|code|diff)[[:space:]]+((is|was|were)[[:space:]]+)?)(generated|written|authored|created|produced|implemented|assisted|built|made)[[:space:]_.-]+by[[:space:]_.-]+(ai|llm|machine|model|assistant|agent|bot|claude([[:space:]_.-]*code)?|codex|chatgpt|gpt|openai|anthropic|copilot|cursor|codeium|gemini|deepseek|qwen|mistral|minimax|aider|windsurf|replit|commandcode|workbuddy|codebuddy|antigravity|opencode|devin|cline|roocode|trae|augment|junie)([^[:alnum:]]|$)'
MESSAGE_GENERATED_WITH_REGEX='(^[[:space:]]*(([[:alnum:]_()/.-]+:[[:space:]]*)|([^[:alnum:][:space:]][[:space:]]*)+)?|(^|[^[:alnum:]])(commit|patch|change|implementation|code|diff)[[:space:]]+((is|was|were)[[:space:]]+)?)(generated|written|authored|created|produced|implemented|built|made)[[:space:]_.-]+(with|using)[[:space:]_.-]+\[?(ai|llm|claude([[:space:]_.-]*code)?|codex|chatgpt|gpt|openai|anthropic|copilot|cursor|codeium|gemini|deepseek|qwen|mistral|minimax|aider|windsurf|replit|commandcode|workbuddy|codebuddy|antigravity|opencode|devin|cline|roocode|trae|augment|junie)\]?([^[:alnum:]]|$)'
MESSAGE_ZH_REGEX='((由|借助|使用|通过|利用)[[:space:]]*)?(ai|人工智能|大模型|语言模型|llm|claude([[:space:]]*code)?|codex|copilot|chatgpt|gpt|deepseek|cursor|windsurf|gemini|workbuddy|codebuddy|antigravity|opencode|devin|cline|assistant|agent|bot)[[:space:]]*(生成|编写|撰写|实现|完成|辅助|协助|提交|修改|重构)[[:space:]]*((本次|这次|此次|此)(提交|改动|补丁|实现|代码)|[。！![:space:]]*$)'
MESSAGE_DISCLOSURE_REGEX="$MESSAGE_AI_ACTION_REGEX|$MESSAGE_GENERATED_BY_REGEX|$MESSAGE_GENERATED_WITH_REGEX|$MESSAGE_ZH_REGEX"

governance_mode=0
violations=0

# 用 bash 内建匹配，不调用 grep：
#   1. 不依赖 PATH 上的 grep —— hook 在每个 commit 上跑，PATH 被换成代理/包装脚本时
#      既慢（实测 110ms/次 vs 3ms）又可能漏匹配，静默放过违规是最坏结果；
#   2. 少一次进程派生，测试套件与分发门禁都快一个量级。
shopt -s nocasematch

report_violation() {
  local location="$1"
  local kind="$2"
  printf 'Commit attribution violation: %s (%s)\n' "$location" "$kind" >&2
  violations=$((violations + 1))
}

# 逐行匹配：message 的 ^ 语义按行生效，与「每行独立检查」一致。
match_any_line() {
  local text="$1"
  local pattern="$2"
  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ $pattern ]]; then
      return 0
    fi
  done <<<"$text"
  return 1
}

# 仅在 git commit -v 的精确剪刀线处截断，防止把附带的 diff 上下文误判为提交消息；
# 不剥离普通 # 注释行，避免与 `git commit -m`（默认保留 # 行）在本地与 CI 间产生分叉。
strip_git_scissors() {
  local message_file="$1"
  local line clean=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ $GIT_SCISSORS_REGEX ]]; then
      break
    fi
    if [[ -n "$clean" ]]; then
      clean+=$'\n'"$line"
    else
      clean="$line"
    fi
  done <"$message_file"
  printf '%s' "$clean"
}

check_message_text() {
  local location="$1"
  local message="$2"
  if match_any_line "$message" "$CO_AUTHOR_TRAILER_REGEX"; then
    report_violation "$location" "co-author trailer"
  fi
  if (( governance_mode == 1 )); then
    return 0
  fi
  if match_any_line "$message" "$MESSAGE_DISCLOSURE_REGEX"; then
    report_violation "$location" "AI information disclosure"
  fi
}

check_message_file() {
  local message_file="$1"
  if [[ ! -f "$message_file" ]]; then
    printf 'Commit attribution check failed: message file does not exist.\n' >&2
    return 2
  fi
  check_message_text "$message_file" "$(strip_git_scissors "$message_file")"
}

check_identity() {
  local location="$1"
  local identity="$2"
  if [[ "$identity" =~ $KNOWN_AI_IDENTITY_REGEX ]]; then
    report_violation "$location" "known AI/Bot identity"
    return 0
  fi
  # 裸 AI 只认全大写，需要临时关掉 nocasematch，避免「Ai Wei」被误伤。
  shopt -u nocasematch
  if [[ "$identity" =~ $UPPERCASE_AI_IDENTITY_REGEX ]]; then
    report_violation "$location" "known AI/Bot identity"
  fi
  shopt -s nocasematch
}

check_current_identity() {
  local author_identity
  local committer_identity

  if ! author_identity="$(git var GIT_AUTHOR_IDENT 2>/dev/null)"; then
    printf 'Commit attribution check failed: unable to read Git author identity.\n' >&2
    return 2
  fi
  if ! committer_identity="$(git var GIT_COMMITTER_IDENT 2>/dev/null)"; then
    printf 'Commit attribution check failed: unable to read Git committer identity.\n' >&2
    return 2
  fi

  check_identity "current author" "$author_identity"
  check_identity "current committer" "$committer_identity"
}

check_commit() {
  local commit="$1"
  local message
  local author_identity
  local committer_identity

  message="$(git show -s --format='%B' "$commit")"
  author_identity="$(git show -s --format='%an <%ae>' "$commit")"
  committer_identity="$(git show -s --format='%cn <%ce>' "$commit")"

  check_message_text "$commit" "$message"
  check_identity "$commit author" "$author_identity"
  check_identity "$commit committer" "$committer_identity"
}

check_revision_range() {
  local revision_range="$1"
  local commits
  local commit

  if ! commits="$(git rev-list --reverse "$revision_range")"; then
    printf 'Commit attribution check failed: invalid Git revision range.\n' >&2
    return 2
  fi

  if [[ -z "$commits" ]]; then
    printf 'No commits found in the requested range.\n'
    return
  fi

  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    check_commit "$commit"
  done <<< "$commits"
}

audit_history() {
  local commits
  local commit

  if ! commits="$(git rev-list --all)"; then
    printf 'Commit attribution audit failed: unable to enumerate Git history.\n' >&2
    return 2
  fi

  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    check_commit "$commit"
  done <<< "$commits"

  printf 'Audited all reachable commits.\n'
}

print_policy() {
  if (( governance_mode == 1 )); then
    printf '模式: governance（trailer + 身份，跳过 message 披露短语）\n'
  else
    printf '模式: 默认（trailer + 身份 + message 披露短语）\n'
  fi
  printf '\n[1] co-author trailer:\n%s\n' "$CO_AUTHOR_TRAILER_REGEX"
  printf '\n[2] 身份层（大小写不敏感，author/committer）:\n%s\n' "$KNOWN_AI_IDENTITY_REGEX"
  printf '\n[2b] 身份层补充（全大写 AI）:\n%s\n' "$UPPERCASE_AI_IDENTITY_REGEX"
  printf '\n[3] message 披露短语 A（AI + 动作词）:\n%s\n' "$MESSAGE_AI_ACTION_REGEX"
  printf '\n[4] message 披露短语 B（动作 + by + 身份）:\n%s\n' "$MESSAGE_GENERATED_BY_REGEX"
  printf '\n[5] message 披露短语 C（动作 + with/using + 工具）:\n%s\n' "$MESSAGE_GENERATED_WITH_REGEX"
  printf '\n[6] message 披露短语 D（中文披露）:\n%s\n' "$MESSAGE_ZH_REGEX"
  printf '\n说明: 层 3-6 只匹配披露短语，不匹配裸词 ai / agent / assistant / bot。\n'
  printf '      「修复 AI 模块的空指针」「增加 ai 摘要」属于产品功能描述，不拦截。\n'
}

main() {
  local arg
  local args=()

  for arg in "$@"; do
    case "$arg" in
      --governance)
        governance_mode=1
        ;;
      *)
        args+=("$arg")
        ;;
    esac
  done

  if (( ${#args[@]} > 0 )); then
    set -- "${args[@]}"
  else
    set --
  fi

  local mode="${1:-}"

  case "$mode" in
    --message)
      [[ "$#" -eq 2 ]] || { usage; return 2; }
      check_message_file "$2"
      check_current_identity
      ;;
    --commit)
      [[ "$#" -eq 2 ]] || { usage; return 2; }
      check_commit "$2"
      ;;
    --range)
      [[ "$#" -eq 2 ]] || { usage; return 2; }
      check_revision_range "$2"
      ;;
    --audit-history)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      audit_history
      ;;
    --print-policy)
      [[ "$#" -eq 1 ]] || { usage; return 2; }
      print_policy
      return 0
      ;;
    *)
      usage
      return 2
      ;;
  esac

  if (( violations > 0 )); then
    printf '%d commit attribution violation(s) found.\n' "$violations" >&2
    return 1
  fi

  printf 'Commit attribution check passed.\n'
}

main "$@"
