#!/usr/bin/env bash
set -euo pipefail

# check-commit-attribution.sh
#
# 检查新的 Git commit 和提交身份是否披露 AI、模型、Agent 或 Bot 信息。
# 该脚本只读 message/commit metadata，不自动改写提交、Git 配置或历史。
#
# 注意：--audit-history 会对政策生效前（含 Co-Authored-By 的旧 commit）报红，这是
# 「历史不重写」的预期行为，不是回归；日常用 --range 只查新增 commit。

usage() {
  cat >&2 <<'USAGE'
用法:
  check-commit-attribution.sh --message <commit-message-file>
  check-commit-attribution.sh --commit <commit-sha>
  check-commit-attribution.sh --range <git-revision-range>
  check-commit-attribution.sh --audit-history
USAGE
}

# 新的项目交付物和协作记录不得披露 AI 信息；匹配大小写不敏感。
# 不把普通 data model 误判为 AI 信息，只匹配 AI/LLM/语言模型及常见工具或身份。
FORBIDDEN_AI_DISCLOSURE_REGEX='(^|[^[:alnum:]])(ai|a[[:space:]_.-]*i|人工智能|artificial[[:space:]_.-]+intelligence|llm|large[[:space:]_.-]+language[[:space:]_.-]+model|chatgpt|gpt|openai|anthropic|claude|claudecode|codex|copilot|cursor|codeium|gemini|deepseek|qwen|mistral|minimax|aider|windsurf|replit|agent|subagent|agentic|bot|assistant|superpowers|generated[[:space:]_.-]+by|machine[[:space:]_.-]+generated|anthropic\.com|openai\.com|commandcode\.ai)([^[:alnum:]]|$)'
CO_AUTHOR_TRAILER_REGEX='^[[:space:]]*co[[:space:]_.-]*author(ed)?[[:space:]_.-]*(by)?[[:space:]]*:'

violations=0

report_violation() {
  local location="$1"
  local kind="$2"
  printf 'Commit attribution violation: %s (%s)\n' "$location" "$kind" >&2
  violations=$((violations + 1))
}

check_message_text() {
  local location="$1"
  local message="$2"
  if printf '%s\n' "$message" | LC_ALL=C grep -Eiq "$CO_AUTHOR_TRAILER_REGEX"; then
    report_violation "$location" "co-author trailer"
  fi
  if printf '%s\n' "$message" | LC_ALL=C grep -Eiq "$FORBIDDEN_AI_DISCLOSURE_REGEX"; then
    report_violation "$location" "AI information disclosure"
  fi
}

check_message_file() {
  local message_file="$1"
  if [[ ! -f "$message_file" ]]; then
    printf 'Commit attribution check failed: message file does not exist.\n' >&2
    return 2
  fi
  check_message_text "$message_file" "$(<"$message_file")"
}

check_identity() {
  local location="$1"
  local identity="$2"
  if printf '%s\n' "$identity" | LC_ALL=C grep -Eiq "$FORBIDDEN_AI_DISCLOSURE_REGEX"; then
    report_violation "$location" "AI information disclosure in identity"
  fi
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

main() {
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
