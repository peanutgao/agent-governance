#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-distribute.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0

make_fixture() {
  local name="$1"
  local repo="$TEST_ROOT/$name/repo"

  mkdir -p "$repo/global" "$repo/.github" "$repo/.githooks" "$repo/scripts" "$repo/tests"
  git init -q "$repo"
  git -C "$repo" config user.name "Joseph Koh"
  git -C "$repo" config user.email "joseph@example.com"

  printf 'global rules v1\n' >"$repo/global/AGENTS.md"
  printf 'detailed flow v1\n' >"$repo/global/ai-change-implementation-prompt.md"
  printf 'owners\n' >"$repo/.github/CODEOWNERS"
  printf 'hook\n' >"$repo/.githooks/commit-msg"
  printf 'readme\n' >"$repo/README.md"
  printf 'onboarding\n' >"$repo/onboarding.md"
  printf 'attribution checker\n' >"$repo/scripts/check-commit-attribution.sh"
  cp "$ROOT_DIR/scripts/check-version-bump.sh" "$repo/scripts/check-version-bump.sh"
  cp "$ROOT_DIR/scripts/distribute.sh" "$repo/scripts/distribute.sh"
  printf 'baseline tests\n' >"$repo/tests/placeholder.sh"
  printf '1.0.0\n' >"$repo/VERSION"

  git -C "$repo" add .
  git -C "$repo" commit -q -m "chore: baseline"
  printf '%s\n' "$repo"
}

run_distribution() {
  local repo="$1"
  local home="$2"
  mkdir -p "$home"
  HOME="$home" bash "$repo/scripts/distribute.sh" >"$home/distribute.out" 2>&1
}

expect_failure() {
  local label="$1"
  shift
  local actual_code

  set +e
  "$@" >"$TEST_ROOT/$label.out" 2>&1
  actual_code=$?
  set -e

  if [[ "$actual_code" -ne 0 ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected failure)\n' "$label" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

remote_failure_repo="$(make_fixture remote-failure)"
remote_failure_home="$TEST_ROOT/remote-failure/home"
git -C "$remote_failure_repo" remote add origin "$TEST_ROOT/remote-failure/missing-remote"
expect_failure remote-fetch-fails-closed run_distribution "$remote_failure_repo" "$remote_failure_home"
if [[ -e "$remote_failure_home/.codex/AGENTS.md" ]]; then
  printf 'FAIL remote-fetch-does-not-install (stale rules were installed)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS remote-fetch-does-not-install\n'
fi

symlink_repo="$(make_fixture symlink-target)"
symlink_home="$TEST_ROOT/symlink-target/home"
mkdir -p "$symlink_home/.codex"
printf 'sensitive sentinel\n' >"$symlink_home/outside.txt"
ln -s "$symlink_home/outside.txt" "$symlink_home/.codex/AGENTS.md"
expect_failure managed-symlink-rejected run_distribution "$symlink_repo" "$symlink_home"
if [[ "$(<"$symlink_home/outside.txt")" == 'sensitive sentinel' ]]; then
  printf 'PASS managed-symlink-target-unchanged\n'
else
  printf 'FAIL managed-symlink-target-unchanged\n' >&2
  failures=$((failures + 1))
fi

rollback_repo="$(make_fixture rollback)"
rollback_home="$TEST_ROOT/rollback/home"
run_distribution "$rollback_repo" "$rollback_home"

printf 'global rules v2\n' >"$rollback_repo/global/AGENTS.md"
printf '1.1.0\n' >"$rollback_repo/VERSION"
git -C "$rollback_repo" add global/AGENTS.md VERSION
git -C "$rollback_repo" commit -q -m "chore: release 1.1.0"
run_distribution "$rollback_repo" "$rollback_home"
expected_agents="$(<"$rollback_home/.codex/AGENTS.md")"
expected_prompt="$(<"$rollback_home/.codex/ai-change-implementation-prompt.md")"
expected_version="$(<"$rollback_home/.codex/.gov-version")"

printf 'detailed flow v2\n' >"$rollback_repo/global/ai-change-implementation-prompt.md"
printf '1.2.0\n' >"$rollback_repo/VERSION"
git -C "$rollback_repo" add global/ai-change-implementation-prompt.md VERSION
git -C "$rollback_repo" commit -q -m "chore: release 1.2.0"
run_distribution "$rollback_repo" "$rollback_home"
HOME="$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback >"$rollback_home/rollback.out" 2>&1

if [[ "$(<"$rollback_home/.codex/AGENTS.md")" == "$expected_agents" ]]; then
  printf 'PASS rollback-restores-agents-as-group\n'
else
  printf 'FAIL rollback-restores-agents-as-group\n' >&2
  failures=$((failures + 1))
fi
if [[ "$(<"$rollback_home/.codex/ai-change-implementation-prompt.md")" == "$expected_prompt" ]]; then
  printf 'PASS rollback-restores-prompt-as-group\n'
else
  printf 'FAIL rollback-restores-prompt-as-group\n' >&2
  failures=$((failures + 1))
fi
if [[ "$(<"$rollback_home/.codex/.gov-version")" == "$expected_version" ]]; then
  printf 'PASS rollback-restores-version-as-group\n'
else
  printf 'FAIL rollback-restores-version-as-group\n' >&2
  failures=$((failures + 1))
fi

expect_same_content() {
  local label="$1"
  local expected_file="$2"
  local actual_file="$3"

  if [[ -f "$actual_file" ]] && cmp -s "$expected_file" "$actual_file"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

expect_symlink_to() {
  local label="$1"
  local expected_target="$2"
  local link_path="$3"

  if [[ -L "$link_path" && "$(readlink "$link_path")" == "$expected_target" ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

# 治理仓自身的工作区级入口：根 AGENTS.md 必须是 global/AGENTS.md 的软链。
# 少了它，在本仓干活时（特别是分发尚未跑过、WorkBuddy 用户级规则还不存在时）
# AI 读不到这套规则，等于治理仓自己不受治理。
expect_symlink_to repo-root-agents-symlink "global/AGENTS.md" "$ROOT_DIR/AGENTS.md"

targets_repo="$(make_fixture targets)"
targets_home="$TEST_ROOT/targets/home"
run_distribution "$targets_repo" "$targets_home"

canonical="$targets_home/.codex/AGENTS.md"
expect_same_content canonical-agents "$targets_repo/global/AGENTS.md" "$canonical"
expect_same_content canonical-prompt \
  "$targets_repo/global/ai-change-implementation-prompt.md" \
  "$targets_home/.codex/ai-change-implementation-prompt.md"
expect_same_content canonical-checker \
  "$targets_repo/scripts/check-commit-attribution.sh" \
  "$targets_home/.codex/check-commit-attribution.sh"

expect_symlink_to link-claude-code "$canonical" "$targets_home/.claude/CLAUDE.md"
expect_symlink_to link-pi "$canonical" "$targets_home/.pi/agent/AGENTS.md"
expect_symlink_to link-opencode "$canonical" "$targets_home/.config/opencode/AGENTS.md"
expect_symlink_to link-dsh "$canonical" "$targets_home/.dsh/AGENTS.md"
expect_symlink_to link-commandcode "$canonical" "$targets_home/.commandcode/AGENTS.md"

workbuddy_rule="$targets_home/.workbuddy-ai/rules/agent-governance.md"
if [[ -f "$workbuddy_rule" ]] && grep -q '^alwaysApply: true$' "$workbuddy_rule"; then
  printf 'PASS workbuddy-rule-frontmatter\n'
else
  printf 'FAIL workbuddy-rule-frontmatter\n' >&2
  failures=$((failures + 1))
fi

workbuddy_body="$TEST_ROOT/workbuddy-body.md"
awk '/^---$/ { n++; next } n == 2 { if (!started) { if ($0 == "") next; started = 1 } print }' \
  "$workbuddy_rule" >"$workbuddy_body" 2>/dev/null || true
expect_same_content workbuddy-rule-body-matches-agents "$targets_repo/global/AGENTS.md" "$workbuddy_body"

if [[ -L "$workbuddy_rule" ]]; then
  printf 'FAIL workbuddy-rule-is-generated-file (unexpected symlink)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS workbuddy-rule-is-generated-file\n'
fi

snapshots_before="$(ls -1d "$targets_home/.codex/.gov-backup"/*/ 2>/dev/null | wc -l | tr -d ' ')"
run_distribution "$targets_repo" "$targets_home"
snapshots_after="$(ls -1d "$targets_home/.codex/.gov-backup"/*/ 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$snapshots_before" == "$snapshots_after" && "$snapshots_before" -gt 0 ]]; then
  printf 'PASS idempotent-rerun-creates-no-snapshot\n'
else
  printf 'FAIL idempotent-rerun-creates-no-snapshot (before=%s after=%s)\n' "$snapshots_before" "$snapshots_after" >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%d distribution checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All distribution checks passed.\n'
