#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check-version-bump.sh"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-version-bump.XXXXXX)"

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

  mkdir -p "$repo/global" "$repo/.github" "$repo/.githooks" "$repo/scripts" "$repo/tests"
  git init -q "$repo"
  git -C "$repo" config user.name "Joseph Koh"
  git -C "$repo" config user.email "joseph@example.com"

  printf 'baseline global rules\n' >"$repo/global/AGENTS.md"
  printf 'baseline detailed flow\n' >"$repo/global/ai-change-implementation-prompt.md"
  printf 'baseline owners\n' >"$repo/.github/CODEOWNERS"
  printf 'baseline hook\n' >"$repo/.githooks/commit-msg"
  printf 'baseline readme\n' >"$repo/README.md"
  printf 'baseline onboarding\n' >"$repo/onboarding.md"
  printf 'baseline attribution checker\n' >"$repo/scripts/check-commit-attribution.sh"
  printf 'baseline distributor\n' >"$repo/scripts/distribute.sh"
  cp "$CHECKER" "$repo/scripts/check-version-bump.sh"
  printf 'baseline tests\n' >"$repo/tests/placeholder.sh"
  printf '%s\n' "$initial_version" >"$repo/VERSION"

  git -C "$repo" add .
  git -C "$repo" commit -q -m "chore: baseline"

  printf 'changed global rules\n' >"$repo/global/AGENTS.md"
  git -C "$repo" add global/AGENTS.md
  git -C "$repo" commit -q -m "docs: change global rules"

  printf '%s\n' "$candidate_version" >"$repo/VERSION"
  git -C "$repo" add VERSION
  git -C "$repo" commit -q -m "chore: update version"

  printf '%s\n' "$repo"
}

expect_version_result() {
  local label="$1"
  local expected_code="$2"
  local repo="$3"
  local actual_code

  if (cd "$repo" && bash scripts/check-version-bump.sh) >"$TEST_ROOT/$label.out" 2>&1; then
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

valid_repo="$(make_fixture valid 1.0.0 1.0.1)"
same_version_repo="$(make_fixture same-version 1.0.0 '1.0.0 ')"
invalid_format_repo="$(make_fixture invalid-format 1.0.0 1.0)"
non_monotonic_repo="$(make_fixture non-monotonic 1.2.0 1.1.9)"
extra_text_repo="$(make_fixture extra-text 1.0.0 '1.0.1 extra')"

expect_version_result valid 0 "$valid_repo"
expect_version_result same-version 1 "$same_version_repo"
expect_version_result invalid-format 1 "$invalid_format_repo"
expect_version_result non-monotonic 1 "$non_monotonic_repo"
expect_version_result extra-text 1 "$extra_text_repo"

if (( failures > 0 )); then
  printf '%d version checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All version checks passed.\n'
