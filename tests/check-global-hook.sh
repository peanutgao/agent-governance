#!/usr/bin/env bash
set -euo pipefail

# 全局 commit-msg 钩子（~/.codex/git-hooks/commit-msg）的回归测试。
#
# 覆盖三件事：
#   1. 归属检查真的会在 git commit 时拦下（不是只有脚本存在）；
#   2. 仓库自己的 .git/hooks/* 不会被全局 core.hooksPath 静默顶掉（链式转发）；
#   3. 检查器缺失时失败关闭，不静默放行。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/agent-governance-global-hook.XXXXXX)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# 按生产布局搭一份安装目录：<root>/git-hooks/* + <root>/check-commit-attribution.sh
# 钩子优先找同级的 ../check-commit-attribution.sh，因此不依赖真实 $HOME。
install_root="$TEST_ROOT/install"
mkdir -p "$install_root/git-hooks"
cp "$ROOT_DIR/global/git-hooks/commit-msg" "$install_root/git-hooks/commit-msg"
cp "$ROOT_DIR/global/git-hooks/_chain" "$install_root/git-hooks/_chain"
cp "$ROOT_DIR/global/git-hooks/pre-commit" "$install_root/git-hooks/pre-commit"
cp "$ROOT_DIR/global/git-hooks/pre-push" "$install_root/git-hooks/pre-push"
cp "$ROOT_DIR/scripts/check-commit-attribution.sh" "$install_root/check-commit-attribution.sh"
chmod +x "$install_root/git-hooks/commit-msg" \
  "$install_root/git-hooks/_chain" \
  "$install_root/git-hooks/pre-commit" \
  "$install_root/git-hooks/pre-push"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.name "Joseph Koh"
  git -C "$repo" config user.email "joseph@example.com"
  git -C "$repo" config core.hooksPath "$install_root/git-hooks"
  printf 'first\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
}

commit_with() {
  local repo="$1"
  local message="$2"
  git -C "$repo" commit -q -m "$message"
}

expect_commit_ok() {
  local label="$1"
  local repo="$2"
  local message="$3"

  if commit_with "$repo" "$message" >"$TEST_ROOT/$label.out" 2>&1; then
    pass "$label"
  else
    fail "$label (expected success)"
    cat "$TEST_ROOT/$label.out" >&2
  fi
}

expect_commit_blocked() {
  local label="$1"
  local repo="$2"
  local message="$3"
  local code

  set +e
  commit_with "$repo" "$message" >"$TEST_ROOT/$label.out" 2>&1
  code=$?
  set -e

  if [[ "$code" -eq 0 ]]; then
    fail "$label (expected rejection)"
    cat "$TEST_ROOT/$label.out" >&2
  else
    pass "$label"
  fi
}

# --- 1. 基本放行 / 拦截 ----------------------------------------------------
repo="$TEST_ROOT/repo"
make_repo "$repo"
expect_commit_ok global-hook-allows-clean-commit "$repo" "docs: update agent workflow"

printf 'second\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
expect_commit_blocked global-hook-blocks-co-author-trailer "$repo" \
  $'docs: update workflow\n\nCo-Authored-By: Claude Code <noreply@anthropic.com>'

expect_commit_blocked global-hook-blocks-chinese-disclosure "$repo" 'docs: 由 AI 生成的工作流说明'

expect_commit_ok global-hook-allows-plain-wording "$repo" 'docs: 修复 AI 模块的空指针'

# --- 2. 链式转发：仓库自己的钩子仍然执行 -----------------------------------
chain_repo="$TEST_ROOT/chain-repo"
make_repo "$chain_repo"
mkdir -p "$chain_repo/.git/hooks"
printf '#!/usr/bin/env bash\nprintf "chain-msg\\n" >>"$MARKER_FILE"\n' >"$chain_repo/.git/hooks/commit-msg"
printf '#!/usr/bin/env bash\nprintf "chain-pre\\n" >>"$MARKER_FILE"\n' >"$chain_repo/.git/hooks/pre-commit"
chmod +x "$chain_repo/.git/hooks/commit-msg" "$chain_repo/.git/hooks/pre-commit"
marker="$TEST_ROOT/chain.marker"
: >"$marker"

set +e
MARKER_FILE="$marker" commit_with "$chain_repo" "docs: chained hooks" >"$TEST_ROOT/chain.out" 2>&1
chain_code=$?
set -e

if [[ "$chain_code" -ne 0 ]]; then
  fail repo-hooks-chain-runs "(commit failed)"
  cat "$TEST_ROOT/chain.out" >&2
else
  if grep -q '^chain-msg$' "$marker"; then
    pass repo-hook-commit-msg-still-runs
  else
    fail repo-hook-commit-msg-still-runs
  fi
  if grep -q '^chain-pre$' "$marker"; then
    pass repo-hook-pre-commit-still-runs
  else
    fail repo-hook-pre-commit-still-runs
  fi
fi

# --- 3. 仓库钩子拒绝时退出码要透传 -----------------------------------------
reject_repo="$TEST_ROOT/reject-repo"
make_repo "$reject_repo"
mkdir -p "$reject_repo/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"$reject_repo/.git/hooks/commit-msg"
chmod +x "$reject_repo/.git/hooks/commit-msg"

set +e
commit_with "$reject_repo" "docs: repo hook rejects" >"$TEST_ROOT/reject.out" 2>&1
reject_code=$?
set -e
if [[ "$reject_code" -ne 0 ]]; then
  pass repo-hook-rejection-propagates
else
  fail repo-hook-rejection-propagates
fi

# --- 4. 检查器缺失时失败关闭 -----------------------------------------------
broken_root="$TEST_ROOT/broken"
mkdir -p "$broken_root/git-hooks"
cp "$ROOT_DIR/global/git-hooks/commit-msg" "$broken_root/git-hooks/commit-msg"
chmod +x "$broken_root/git-hooks/commit-msg"

broken_repo="$TEST_ROOT/broken-repo"
mkdir -p "$broken_repo"
git init -q "$broken_repo"
git -C "$broken_repo" config user.name "Joseph Koh"
git -C "$broken_repo" config user.email "joseph@example.com"
git -C "$broken_repo" config core.hooksPath "$broken_root/git-hooks"
printf 'x\n' >"$broken_repo/file.txt"
git -C "$broken_repo" add file.txt

set +e
HOME="$TEST_ROOT/empty-home" commit_with "$broken_repo" "docs: missing checker" \
  >"$TEST_ROOT/broken.out" 2>&1
broken_code=$?
set -e
if [[ "$broken_code" -ne 0 ]]; then
  pass missing-checker-fails-closed
else
  fail missing-checker-fails-closed
fi

if (( failures > 0 )); then
  printf '%d global hook checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All global hook checks passed.\n'
