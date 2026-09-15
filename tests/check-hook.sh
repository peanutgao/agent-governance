#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-hook.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

REPO="$TEST_ROOT/repo"
mkdir -p "$REPO/.githooks" "$REPO/scripts"
cp "$ROOT_DIR/.githooks/commit-msg" "$REPO/.githooks/commit-msg"
cp "$ROOT_DIR/scripts/check-commit-attribution.sh" "$REPO/scripts/check-commit-attribution.sh"
chmod +x "$REPO/.githooks/commit-msg" "$REPO/scripts/check-commit-attribution.sh"

git init -q "$REPO"
git -C "$REPO" config user.name "Joseph Koh"
git -C "$REPO" config user.email "joseph@example.com"
git -C "$REPO" config core.hooksPath .githooks

printf 'first\n' >"$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m "docs: update agent workflow"

printf 'second\n' >>"$REPO/file.txt"
git -C "$REPO" add file.txt
set +e
git -C "$REPO" commit -q -m $'docs: update workflow\n\nCo-Authored-By: Bot <bot@example.invalid>'
forbidden_commit_code=$?
set -e

if [[ "$forbidden_commit_code" -ne 1 ]]; then
  printf 'FAIL forbidden commit (expected exit 1, got %s)\n' "$forbidden_commit_code" >&2
  exit 1
fi

printf 'third\n' >>"$REPO/file.txt"
git -C "$REPO" add file.txt
set +e
git -C "$REPO" commit -q -m 'docs: 记录 AI 生成披露的拦截规则'
policy_commit_code=$?
set -e

if [[ "$policy_commit_code" -ne 0 ]]; then
  printf 'FAIL policy-describing commit (expected exit 0, got %s)\n' "$policy_commit_code" >&2
  exit 1
fi

printf 'PASS generic agent wording accepted by hook\n'
printf 'PASS policy-describing wording accepted by governance hook\n'
printf 'PASS forbidden attribution rejected by hook\n'
printf 'All hook checks passed.\n'
