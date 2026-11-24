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
  ! grep -q '未提交或未跟踪内容' "$TEST_ROOT/refuses-local-changes.out" ||
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
