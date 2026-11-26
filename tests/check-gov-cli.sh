#!/usr/bin/env bash
# 统一 CLI 入口 scripts/gov 的路由、参数失败关闭与 scripts/ 顶层目录卫生测试。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOV="$ROOT_DIR/scripts/gov"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-gov-cli.XXXXXX")"
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "${2:-}" >&2; failures=$((failures + 1)); }

expect_code() {
  local label="$1" expected="$2"
  shift 2
  local actual
  set +e
  "$@" >"$TEST_ROOT/$label.out" 2>&1
  actual=$?
  set -e
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected exit $expected, got $actual"
    cat "$TEST_ROOT/$label.out" >&2 || true
  fi
}

# 1. scripts/ 顶层只保留 4 个公开入口 + internal/ 目录，避免平铺脚本回流（忽略 macOS .DS_Store）。
actual_entries="$(
  find "$ROOT_DIR/scripts" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' -exec basename {} \; |
    LC_ALL=C sort | tr '\n' ','
)"
expected_entries="bootstrap.ps1,bootstrap.sh,check-commit-attribution.sh,gov,internal,"
if [[ "$actual_entries" == "$expected_entries" ]]; then
  pass scripts-top-level-layout
else
  fail scripts-top-level-layout "got '$actual_entries', expected '$expected_entries'"
fi

# 2. 帮助输出退出 0。
expect_code help-flag 0 bash "$GOV" --help
expect_code help-short 0 bash "$GOV" -h
expect_code help-subcmd 0 bash "$GOV" help
expect_code install-help 0 bash "$GOV" install --help
expect_code distribute-help 0 bash "$GOV" distribute --help
expect_code check-help 0 bash "$GOV" check --help
expect_code check-all-help 0 bash "$GOV" check all --help
expect_code check-version-help 0 bash "$GOV" check version --help
expect_code project-help 0 bash "$GOV" project --help
expect_code test-help 0 bash "$GOV" test --help

# 3. 缺参、空子命令、未知子命令与多余参数全部失败关闭（退出 2）。
expect_code missing-cmd 2 bash "$GOV"
expect_code empty-cmd 2 bash "$GOV" ""
expect_code unknown-cmd 2 bash "$GOV" unknown-cmd
expect_code install-extra-arg 2 bash "$GOV" install --unknown
expect_code distribute-empty-arg 2 bash "$GOV" distribute ""
expect_code check-empty-sub 2 bash "$GOV" check ""
expect_code check-all-extra-arg 2 bash "$GOV" check all --unknown
expect_code check-version-extra-arg 2 bash "$GOV" check version --unknown
expect_code check-unknown-sub 2 bash "$GOV" check unknown-sub
expect_code project-missing-sub 2 bash "$GOV" project
expect_code project-unknown-sub 2 bash "$GOV" project unknown-sub
expect_code test-extra-arg 2 bash "$GOV" test --unknown

# 4. 各子命令真实路由连通（只读/dry-run/隔离 HOME，无副作用）。
expect_code route-check-paths-list 0 bash "$GOV" check paths --list
expect_code route-check-attribution-policy 0 bash "$GOV" check attribution --print-policy
expect_code route-check-attr-alias 0 bash "$GOV" check attr --print-policy
expect_code route-skills-help 0 bash "$GOV" skills --help
expect_code route-project-sync-help 0 bash "$GOV" project sync --help

fake_home="$TEST_ROOT/fake-home"
mkdir -p "$fake_home"
dist_ok=0
case "$(uname -s)" in
  MINGW*|MSYS*)
    fake_win_home="$(cygpath -w "$fake_home")"
    if env -u CLAUDE_CONFIG_DIR -u PI_CODING_AGENT_DIR -u XDG_CONFIG_HOME -u OPENCODE_CONFIG_DIR \
      -u DSH_HOME -u WORKBUDDY_CONFIG_DIR -u AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS \
      HOME="$fake_home" USERPROFILE="$fake_win_home" \
      bash "$GOV" distribute --list-targets >"$TEST_ROOT/dist-targets.out" 2>&1 &&
      grep -q 'AGENTS.md' "$TEST_ROOT/dist-targets.out"; then
      dist_ok=1
    fi
    ;;
  *)
    if env -u CLAUDE_CONFIG_DIR -u PI_CODING_AGENT_DIR -u XDG_CONFIG_HOME -u OPENCODE_CONFIG_DIR \
      -u DSH_HOME -u WORKBUDDY_CONFIG_DIR -u AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS \
      HOME="$fake_home" \
      bash "$GOV" distribute --list-targets >"$TEST_ROOT/dist-targets.out" 2>&1 &&
      grep -q 'AGENTS.md' "$TEST_ROOT/dist-targets.out"; then
      dist_ok=1
    fi
    ;;
esac
if [[ "$dist_ok" == 1 ]]; then
  pass route-distribute-list-targets
else
  fail route-distribute-list-targets
  cat "$TEST_ROOT/dist-targets.out" >&2 || true
fi

dry_dir="$TEST_ROOT/dry-project"
if bash "$GOV" project init --target "$dry_dir" --dry-run >"$TEST_ROOT/dry-init.out" 2>&1 &&
  [[ ! -e "$dry_dir" ]]; then
  pass route-project-init-dry-run
else
  fail route-project-init-dry-run
  cat "$TEST_ROOT/dry-init.out" >&2 || true
fi

if (( failures > 0 )); then
  printf '%d gov CLI check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'All gov CLI checks passed.\n'
