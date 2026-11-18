#!/usr/bin/env bash
# 项目快照生成器测试：生成、幂等、--check 检出漂移。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/sync-project-governance.sh"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-project-sync.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0
version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
repos=(hengqin-backend hengqin-desktop hengqin-admin)

for repo in "${repos[@]}"; do
  mkdir -p "$TEST_ROOT/$repo"
done

if ! bash "$SCRIPT" --root "$TEST_ROOT" >"$TEST_ROOT/generate.out" 2>&1; then
  printf 'FAIL generate\n' >&2
  cat "$TEST_ROOT/generate.out" >&2
  failures=$((failures + 1))
else
  printf 'PASS generate\n'
fi

for repo in "${repos[@]}"; do
  file="$TEST_ROOT/$repo/AI-GOVERNANCE.md"
  if [[ ! -f "$file" ]]; then
    printf 'FAIL %s missing\n' "$repo" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! grep -q "^> baseline-version: ${version}$" "$file"; then
    printf 'FAIL %s version header\n' "$repo" >&2
    failures=$((failures + 1))
  fi
  if grep -q '__BASELINE_' "$file"; then
    printf 'FAIL %s unresolved placeholder\n' "$repo" >&2
    failures=$((failures + 1))
  fi
  if ! grep -q '不得披露 AI 参与' "$file"; then
    printf 'FAIL %s missing non-disclosure rule\n' "$repo" >&2
    failures=$((failures + 1))
  fi
  if grep -q 'AI 参与只能记录' "$file"; then
    printf 'FAIL %s still contains old disclosure rule\n' "$repo" >&2
    failures=$((failures + 1))
  fi
done

if bash "$SCRIPT" --check --root "$TEST_ROOT" >"$TEST_ROOT/check-ok.out" 2>&1; then
  printf 'PASS check clean\n'
else
  printf 'FAIL check clean\n' >&2
  cat "$TEST_ROOT/check-ok.out" >&2
  failures=$((failures + 1))
fi

printf 'drift\n' >>"$TEST_ROOT/hengqin-desktop/AI-GOVERNANCE.md"
if bash "$SCRIPT" --check --root "$TEST_ROOT" >"$TEST_ROOT/check-drift.out" 2>&1; then
  printf 'FAIL check drift (expected failure)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS check drift\n'
fi

if (( failures > 0 )); then
  printf '%d sync-project-governance checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All sync-project-governance checks passed.\n'
