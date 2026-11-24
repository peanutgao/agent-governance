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

if ! bash "$SCRIPT" --root "$TEST_ROOT" --repos "$(IFS=,; echo "${repos[*]}")" >"$TEST_ROOT/generate.out" 2>&1; then
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

if bash "$SCRIPT" --check --root "$TEST_ROOT" --repos "$(IFS=,; echo "${repos[*]}")" >"$TEST_ROOT/check-ok.out" 2>&1; then
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

git -C "$TEST_ROOT/hengqin-desktop" init -q
if bash "$SCRIPT" --root "$TEST_ROOT" >"$TEST_ROOT/refuses-local-changes.out" 2>&1 ||
  ! grep -q '未提交的人工改动' "$TEST_ROOT/refuses-local-changes.out" ||
  ! grep -q '^drift$' "$TEST_ROOT/hengqin-desktop/AI-GOVERNANCE.md"; then
  printf 'FAIL refuses uncommitted project snapshot\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS refuses uncommitted project snapshot\n'
fi

# 自动发现：不传 --repos 时，从目标根目录下挑出含 .git / 快照 / 项目入口的子目录。
# 用独立夹具仓，避免依赖被测算仓自身工作树是否干净。
discover_repo="$TEST_ROOT/discover-repo"
mkdir -p "$discover_repo/global" "$discover_repo/scripts" "$discover_repo/templates/project"
cp "$SCRIPT" "$discover_repo/scripts/sync-project-governance.sh"
cp "$ROOT_DIR/scripts/check-version-bump.sh" "$discover_repo/scripts/check-version-bump.sh"
cp "$ROOT_DIR/scripts/check-rule-paths.sh" "$discover_repo/scripts/check-rule-paths.sh"
cp "$ROOT_DIR/templates/project/AI-GOVERNANCE.md" "$discover_repo/templates/project/AI-GOVERNANCE.md"
cp "$ROOT_DIR/VERSION" "$discover_repo/VERSION"
printf 'entry\n' >"$discover_repo/AGENTS.md"
git -C "$discover_repo" init -q
git -C "$discover_repo" config user.name "Joseph Koh"
git -C "$discover_repo" config user.email "joseph@example.com"
git -C "$discover_repo" add .
git -C "$discover_repo" commit -q -m "chore: fixture"

discover_root="$TEST_ROOT/discover"
mkdir -p "$discover_root/included-agents" "$discover_root/included-snapshot" "$discover_root/not-a-repo"
printf '# entry\n' >"$discover_root/included-agents/AGENTS.md"
printf '# snapshot\n' >"$discover_root/included-snapshot/AI-GOVERNANCE.md"
printf 'unrelated\n' >"$discover_root/not-a-repo/notes.txt"

if bash "$discover_repo/scripts/sync-project-governance.sh" --root "$discover_root" >"$TEST_ROOT/discover.out" 2>&1; then
  if [[ -f "$discover_root/included-agents/AI-GOVERNANCE.md" &&
    -f "$discover_root/included-snapshot/AI-GOVERNANCE.md" &&
    ! -e "$discover_root/not-a-repo/AI-GOVERNANCE.md" ]]; then
    printf 'PASS auto-discovery\n'
  else
    printf 'FAIL auto-discovery selection\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'FAIL auto-discovery\n' >&2
  cat "$TEST_ROOT/discover.out" >&2
  failures=$((failures + 1))
fi

# 未提交但自洽的脚本产物必须可以覆盖：否则「上次同步写了但没提交」会把
# 后续同步永久挡住。这里模拟该状态：生成后不提交，再同步一次。
resync_repo="$TEST_ROOT/resync-repo"
mkdir -p "$resync_repo/global" "$resync_repo/scripts" "$resync_repo/templates/project" \
  "$resync_repo/tests" "$resync_repo/.github" "$resync_repo/.githooks"
printf 'global rules\n' >"$resync_repo/global/AGENTS.md"
printf 'tests\n' >"$resync_repo/tests/placeholder.sh"
printf 'owners\n' >"$resync_repo/.github/CODEOWNERS"
printf 'hook\n' >"$resync_repo/.githooks/commit-msg"
printf 'readme\n' >"$resync_repo/README.md"
printf 'onboarding\n' >"$resync_repo/onboarding.md"
printf 'checker\n' >"$resync_repo/scripts/check-commit-attribution.sh"
printf 'distributor\n' >"$resync_repo/scripts/distribute.sh"
cp "$SCRIPT" "$resync_repo/scripts/sync-project-governance.sh"
cp "$ROOT_DIR/scripts/check-version-bump.sh" "$resync_repo/scripts/check-version-bump.sh"
cp "$ROOT_DIR/scripts/check-rule-paths.sh" "$resync_repo/scripts/check-rule-paths.sh"
cp "$ROOT_DIR/templates/project/AI-GOVERNANCE.md" "$resync_repo/templates/project/AI-GOVERNANCE.md"
cp "$ROOT_DIR/VERSION" "$resync_repo/VERSION"
printf 'entry\n' >"$resync_repo/AGENTS.md"
git -C "$resync_repo" init -q
git -C "$resync_repo" config user.name "Joseph Koh"
git -C "$resync_repo" config user.email "joseph@example.com"
git -C "$resync_repo" add .
git -C "$resync_repo" commit -q -m "chore: fixture"
# 夹具补一个 origin/main 引用，满足「治理提交已进入默认分支」的前置检查。
git -C "$resync_repo" update-ref refs/remotes/origin/main HEAD
git -C "$resync_repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

mkdir -p "$resync_repo/target/proj-a"
git -C "$resync_repo/target/proj-a" init -q
printf 'v1\n' >"$resync_repo/target/proj-a/AI-GOVERNANCE.md"
git -C "$resync_repo/target/proj-a" add .
git -C "$resync_repo/target/proj-a" commit -q -m "chore: seed"

bash "$resync_repo/scripts/sync-project-governance.sh" --root "$resync_repo/target" --repos proj-a >/dev/null 2>&1 || true
first_hash="$(awk '/^> baseline-content-sha256: /{print $3}' "$resync_repo/target/proj-a/AI-GOVERNANCE.md")"
# 此时工作树有未提交的快照，且它是脚本产物。
if bash "$resync_repo/scripts/sync-project-governance.sh" --root "$resync_repo/target" --repos proj-a >"$TEST_ROOT/resync.out" 2>&1; then
  printf 'PASS uncommitted-generated-snapshot-overwritable\n'
else
  printf 'FAIL uncommitted-generated-snapshot-overwritable\n' >&2
  cat "$TEST_ROOT/resync.out" >&2
  failures=$((failures + 1))
fi

# 目录下完全没有候选仓库时必须失败退出，而不是静默生成零个快照。
mkdir -p "$TEST_ROOT/empty-root"
if bash "$SCRIPT" --root "$TEST_ROOT/empty-root" >"$TEST_ROOT/empty.out" 2>&1; then
  printf 'FAIL empty-root-fails\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS empty-root-fails\n'
fi

if (( failures > 0 )); then
  printf '%d sync-project-governance checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All sync-project-governance checks passed.\n'
