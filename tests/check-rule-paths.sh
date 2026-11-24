#!/usr/bin/env bash
# 规则路径可达性检查的测试。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-rule-paths.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0
report() {
  local label="$1" ok="$2"
  if [[ "$ok" == 1 ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

make_fixture() {
  local name="$1"
  local repo="$TEST_ROOT/$name"
  mkdir -p "$repo/scripts" "$repo/global" "$repo/templates/project"
  cp "$ROOT_DIR/scripts/check-rule-paths.sh" "$repo/scripts/check-rule-paths.sh"
  printf 'placeholder\n' >"$repo/templates/project/AI-GOVERNANCE.md"
  printf 'placeholder\n' >"$repo/README.md"
  printf 'placeholder\n' >"$repo/onboarding.md"
  printf '%s\n' "$repo"
}

# 1. 存在的路径应当通过。
repo="$(make_fixture existing)"
mkdir -p "$repo/home-shim"
printf '见 `%s` 与 `%s`。\n' "$HOME" "$HOME/." >"$repo/global/AGENTS.md"
if bash "$repo/scripts/check-rule-paths.sh" >/dev/null 2>&1; then
  report reachable-passes 1
else
  report reachable-passes 0
fi

# 2. 不存在的绝对路径必须被拦下。
repo="$(make_fixture missing)"
printf '见 `~/definitely-not-here-9f3a/AGENTS.md`。\n' >"$repo/global/AGENTS.md"
if bash "$repo/scripts/check-rule-paths.sh" >"$TEST_ROOT/missing.out" 2>&1; then
  report missing-fails 0
else
  grep -q 'definitely-not-here-9f3a' "$TEST_ROOT/missing.out" && report missing-fails 1 || report missing-fails 0
fi

# 3. --list 只列不判，即使路径不存在也退出 0。
repo="$(make_fixture list)"
printf '见 `~/definitely-not-here-9f3a/AGENTS.md`。\n' >"$repo/global/AGENTS.md"
if bash "$repo/scripts/check-rule-paths.sh" --list >/dev/null 2>&1; then
  report list-mode-exits-zero 1
else
  report list-mode-exits-zero 0
fi

# 4. 占位示例前缀不参与判定。
repo="$(make_fixture exempt)"
printf '见 `/path/to/project/AGENTS.md`。\n' >"$repo/global/AGENTS.md"
if bash "$repo/scripts/check-rule-paths.sh" >/dev/null 2>&1; then
  report exempt-prefix-skipped 1
else
  report exempt-prefix-skipped 0
fi

if (( failures > 0 )); then
  printf '%d rule-path check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'All rule-path checks passed.\n'
