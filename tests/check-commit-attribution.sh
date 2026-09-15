#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check-commit-attribution.sh"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-commit-attribution.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0

expect_success() {
  local label="$1"
  shift
  if "$CHECKER" "$@" >"$TEST_ROOT/$label.out" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected success)\n' "$label" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

expect_env_success() {
  local label="$1"
  shift
  if "$@" >"$TEST_ROOT/$label.out" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected success)\n' "$label" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

expect_failure_code() {
  local label="$1"
  local expected_code="$2"
  shift
  shift
  local actual_code
  if "$@" >"$TEST_ROOT/$label.out" 2>&1; then
    actual_code=0
  else
    actual_code=$?
  fi
  if [[ "$actual_code" -eq "$expected_code" ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected exit %s, got %s)\n' "$label" "$expected_code" "$actual_code" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

write_message() {
  local name="$1"
  local body="$2"
  printf '%s\n' "$body" >"$TEST_ROOT/$name"
}

REPO="$TEST_ROOT/repo"
git init -q "$REPO"
git -C "$REPO" config user.name "Joseph Koh"
git -C "$REPO" config user.email "joseph@example.com"

write_message human.txt 'docs: update governance'
write_message co-authored-by.txt $'docs: update governance\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
write_message co-authored-lowercase.txt $'docs: update governance\n\nCo-authored-by: ChatGPT <noreply@openai.com>'
write_message co-author.txt $'docs: update governance\n\nCo-Author: Bot <bot@example.invalid>'
write_message coauthor.txt $'docs: update governance\n\nCoauthor: Agent <agent@example.invalid>'
write_message co-author-underscore.txt $'docs: update governance\n\nCo_Authored_By: Bot <bot@example.invalid>'
write_message co-author-spaces.txt $'docs: update governance\n\nCo Authored By: Agent <agent@example.invalid>'
write_message governance-exception.txt $'docs: update governance\n\nGovernance-Exception: docs | approved-by=@Joseph | reason=owner review'
write_message message-ai-disclosure.txt 'chore: AI-assisted implementation'
write_message message-agent-disclosure.txt 'chore: update coding agent workflow'
write_message message-generated-disclosure.txt 'chore: generated-by assistant'
write_message message-data-model.txt 'refactor: update data model mapping'

expect_success message-human --message "$TEST_ROOT/human.txt"
expect_failure_code message-co-authored-by 1 "$CHECKER" --message "$TEST_ROOT/co-authored-by.txt"
expect_failure_code message-co-authored-lowercase 1 "$CHECKER" --message "$TEST_ROOT/co-authored-lowercase.txt"
expect_failure_code message-co-author 1 "$CHECKER" --message "$TEST_ROOT/co-author.txt"
expect_failure_code message-coauthor 1 "$CHECKER" --message "$TEST_ROOT/coauthor.txt"
expect_failure_code message-co-author-underscore 1 "$CHECKER" --message "$TEST_ROOT/co-author-underscore.txt"
expect_failure_code message-co-author-spaces 1 "$CHECKER" --message "$TEST_ROOT/co-author-spaces.txt"
expect_success message-governance-exception --message "$TEST_ROOT/governance-exception.txt"
expect_failure_code message-ai-disclosure 1 "$CHECKER" --message "$TEST_ROOT/message-ai-disclosure.txt"
expect_failure_code message-agent-disclosure 1 "$CHECKER" --message "$TEST_ROOT/message-agent-disclosure.txt"
expect_failure_code message-generated-disclosure 1 "$CHECKER" --message "$TEST_ROOT/message-generated-disclosure.txt"
expect_success message-data-model --message "$TEST_ROOT/message-data-model.txt"
expect_failure_code message-missing-file 2 "$CHECKER" --message "$TEST_ROOT/missing.txt"
expect_failure_code current-ai-author 1 env GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com "$CHECKER" --message "$TEST_ROOT/human.txt"
expect_failure_code current-ai-claudecode 1 env GIT_AUTHOR_NAME=ClaudeCode GIT_AUTHOR_EMAIL=claude-code@example.invalid "$CHECKER" --message "$TEST_ROOT/human.txt"
expect_failure_code current-ai-committer 1 env GIT_COMMITTER_NAME=CommandCodeBot GIT_COMMITTER_EMAIL=noreply@commandcode.ai "$CHECKER" --message "$TEST_ROOT/human.txt"
expect_failure_code current-github-actions-committer 1 env GIT_COMMITTER_NAME='github-actions[bot]' GIT_COMMITTER_EMAIL=actions@example.invalid "$CHECKER" --message "$TEST_ROOT/human.txt"
expect_failure_code current-human-agent-name 1 env GIT_AUTHOR_NAME='Agent Smith' GIT_AUTHOR_EMAIL=smith@example.invalid "$CHECKER" --message "$TEST_ROOT/human.txt"
expect_failure_code current-human-bot-email 1 env GIT_AUTHOR_EMAIL='bot-service@acme.com' "$CHECKER" --message "$TEST_ROOT/human.txt"

git -C "$REPO" commit --allow-empty -q -m "chore: baseline"
base_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_success root_commit_commit_mode --commit "$base_commit")
expect_failure_code commit_missing_arg 2 "$CHECKER" --commit

git -C "$REPO" commit --allow-empty -q -m "docs: human change"
human_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_success human_range --range "$base_commit..$human_commit")
(cd "$REPO" && expect_failure_code invalid_range 2 "$CHECKER" --range "not-a-revision-range")

git -C "$REPO" commit --allow-empty -q --author="Claude <noreply@anthropic.com>" -m "docs: ai author"
ai_author_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_failure_code ai_author_range 1 "$CHECKER" --range "$human_commit..$ai_author_commit")
(cd "$REPO" && expect_failure_code ai_author_commit_mode 1 "$CHECKER" --commit "$ai_author_commit")

GIT_COMMITTER_NAME="CommandCodeBot" \
GIT_COMMITTER_EMAIL="noreply@commandcode.ai" \
git -C "$REPO" commit --allow-empty -q -m "docs: ai committer"
ai_committer_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_failure_code ai_committer_range 1 "$CHECKER" --range "$ai_author_commit..$ai_committer_commit")

git -C "$REPO" commit --allow-empty -q -m $'docs: forbidden trailer\n\nCo-Authored-By: Bot <bot@example.invalid>'
new_trailer_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_failure_code new_trailer_range 1 "$CHECKER" --range "$ai_committer_commit..$new_trailer_commit")

git -C "$REPO" commit --allow-empty -q -m $'chore: old history\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
old_history_commit="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" commit --allow-empty -q -m "docs: post-history human change"
post_history_human_commit="$(git -C "$REPO" rev-parse HEAD)"
(cd "$REPO" && expect_success old_history_excluded --range "$old_history_commit..$post_history_human_commit")
(cd "$REPO" && expect_failure_code audit_history 1 "$CHECKER" --audit-history)

if (( failures > 0 )); then
  printf '%d attribution checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All commit attribution checks passed.\n'
