#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/internal/check-version-bump.sh"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-version-bump.XXXXXX")"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0

make_fixture() {
  local name="$1"
  local initial_version="$2"
  local candidate_version="$3"
  local repo="$TEST_ROOT/$name"

  mkdir -p "$repo/global" "$repo/.github" "$repo/.githooks" "$repo/scripts/internal" "$repo/tests" "$repo/templates/project" "$repo/skills/local/ai-change-flow/references"
  git init -q "$repo"
  git -C "$repo" config user.name "Joseph Koh"
  git -C "$repo" config user.email "joseph@example.com"

  printf 'baseline global rules\n' >"$repo/global/AGENTS.md"
  printf 'baseline skill flow\n' >"$repo/skills/local/ai-change-flow/references/full-flow.md"
  printf 'baseline owners\n' >"$repo/.github/CODEOWNERS"
  printf 'baseline hook\n' >"$repo/.githooks/commit-msg"
  printf 'baseline readme\n' >"$repo/README.md"
  printf 'baseline onboarding\n' >"$repo/onboarding.md"
  printf 'baseline attribution checker\n' >"$repo/scripts/check-commit-attribution.sh"
  printf 'baseline project template\n' >"$repo/templates/project/AI-GOVERNANCE.md"
  printf 'baseline project sync\n' >"$repo/scripts/internal/sync-project-governance.sh"
  printf 'baseline distributor\n' >"$repo/scripts/internal/distribute.sh"
  printf 'baseline bootstrap\n' >"$repo/scripts/bootstrap.sh"
  cp "$ROOT_DIR/scripts/gov" "$repo/scripts/gov"
  cp "$CHECKER" "$repo/scripts/internal/check-version-bump.sh"
  cp "$ROOT_DIR/scripts/internal/check-rule-paths.sh" "$repo/scripts/internal/check-rule-paths.sh"
  printf 'baseline tests\n' >"$repo/tests/placeholder.sh"
  printf '%s\n' "$initial_version" >"$repo/VERSION"
  printf '* text=auto eol=lf\n' >"$repo/.gitattributes"
  printf '# pointer\nSee `global/AGENTS.md`.\n' >"$repo/AGENTS.md"

  git -C "$repo" add .
  git -C "$repo" commit -q -m "chore: baseline"

  printf 'changed global rules\n' >"$repo/global/AGENTS.md"
  git -C "$repo" add global/AGENTS.md
  git -C "$repo" commit -q -m "docs: change global rules"

  if [[ "$candidate_version" == "$initial_version" ]]; then
    # 制造一次真正触碰 VERSION 的提交（补上/去掉尾换行），使 previous_version == current_version
    # 均满足 SemVer 格式校验，从而真正命中单调递增比较。
    printf '%s' "$initial_version" >"$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" commit -q --amend -m "chore: baseline"
  fi
  printf '%s\n' "$candidate_version" >"$repo/VERSION"
  git -C "$repo" add VERSION
  git -C "$repo" commit -q -m "chore: update version"

  printf '%s\n' "$repo"
}

expect_version_result() {
  local label="$1"
  local expected_code="$2"
  local repo="$3"
  local expected_msg="${4:-}"
  local actual_code

  if (cd "$repo" && bash scripts/gov check version) >"$TEST_ROOT/$label.out" 2>&1; then
    actual_code=0
  else
    actual_code=$?
  fi

  if [[ "$actual_code" -eq "$expected_code" ]] &&
    [[ -z "$expected_msg" || "$(grep -c "$expected_msg" "$TEST_ROOT/$label.out" || true)" -gt 0 ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected exit %s, got %s)\n' "$label" "$expected_code" "$actual_code" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

valid_repo="$(make_fixture valid 1.0.0 1.0.1)"
same_version_repo="$(make_fixture same-version 1.0.0 1.0.0)"
trailing_space_repo="$(make_fixture trailing-space 1.0.0 '1.0.0 ')"
invalid_format_repo="$(make_fixture invalid-format 1.0.0 1.0)"
non_monotonic_repo="$(make_fixture non-monotonic 1.2.0 1.1.9)"
extra_text_repo="$(make_fixture extra-text 1.0.0 '1.0.1 extra')"

expect_version_result valid 0 "$valid_repo"
expect_version_result same-version 1 "$same_version_repo" '递增'
expect_version_result trailing-space 1 "$trailing_space_repo" 'SemVer'
expect_version_result invalid-format 1 "$invalid_format_repo" 'SemVer'
expect_version_result non-monotonic 1 "$non_monotonic_repo" '递增'
expect_version_result extra-text 1 "$extra_text_repo" 'SemVer'

# 改 global 规则不 bump 必须拒绝
printf 'unreleased rule\n' >>"$valid_repo/global/AGENTS.md"
git -C "$valid_repo" add global/AGENTS.md
git -C "$valid_repo" commit -q -m 'docs: edit rule without version bump'
expect_version_result changed-rules-without-version 1 "$valid_repo"

# 改 skills/ 详细流程不 bump 必须拒绝
skills_repo="$(make_fixture skills-bump 1.0.0 1.0.1)"
printf 'unreleased skill flow\n' >>"$skills_repo/skills/local/ai-change-flow/references/full-flow.md"
git -C "$skills_repo" add skills/local/ai-change-flow/references/full-flow.md
git -C "$skills_repo" commit -q -m 'docs: edit skill flow without version bump'
expect_version_result changed-skills-without-version 1 "$skills_repo"

# 改 scripts/bootstrap.sh 不 bump 必须拒绝
script_repo="$(make_fixture script-bump 1.0.0 1.0.1)"
printf 'unreleased bootstrap\n' >>"$script_repo/scripts/bootstrap.sh"
git -C "$script_repo" add scripts/bootstrap.sh
git -C "$script_repo" commit -q -m 'fix: edit bootstrap without version bump'
expect_version_result changed-script-without-version 1 "$script_repo"

if (( failures > 0 )); then
  printf '%d version checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All version checks passed.\n'
