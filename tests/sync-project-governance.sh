#!/usr/bin/env bash
# 项目快照生成器测试：生成、渲染字节上限、幂等、--check 漂移、跨版本双同步写入循环、远端落后拦截。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/internal/sync-project-governance.sh"
GOV="$ROOT_DIR/scripts/gov"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-project-sync.XXXXXX")"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

unset PROJECT_GOVERNANCE_ROOT PROJECT_GOVERNANCE_REPOS

failures=0
version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
repos=(proj-backend proj-desktop proj-admin)

# 未传 --root 且未设环境变量时必须明确拒绝（不再回退硬编码个人目录）。
set +e
bash "$SCRIPT" >"$TEST_ROOT/no-root.out" 2>&1
no_root_code=$?
set -e
if [[ "$no_root_code" -eq 2 ]]; then
  printf 'PASS missing-root-rejected\n'
else
  printf 'FAIL missing-root-rejected (expected 2, got %s)\n' "$no_root_code" >&2
  failures=$((failures + 1))
fi

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
  rendered_bytes="$(wc -c <"$file" | tr -d '[:space:]')"
  if (( rendered_bytes > 24000 )); then
    printf 'FAIL %s rendered-bytes-limit (%s > 24000)\n' "$repo" "$rendered_bytes" >&2
    failures=$((failures + 1))
  fi
done
printf 'PASS rendered-snapshot-within-24000-bytes\n'

if bash "$SCRIPT" --check --root "$TEST_ROOT" --repos "$(IFS=,; echo "${repos[*]}")" >"$TEST_ROOT/check-ok.out" 2>&1; then
  printf 'PASS check clean\n'
else
  printf 'FAIL check clean\n' >&2
  cat "$TEST_ROOT/check-ok.out" >&2
  failures=$((failures + 1))
fi

printf 'drift\n' >>"$TEST_ROOT/proj-desktop/AI-GOVERNANCE.md"
if bash "$SCRIPT" --check --root "$TEST_ROOT" >"$TEST_ROOT/check-drift.out" 2>&1; then
  printf 'FAIL check drift (expected failure)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS check drift\n'
fi

git -C "$TEST_ROOT/proj-desktop" init -q
if bash "$SCRIPT" --root "$TEST_ROOT" >"$TEST_ROOT/refuses-local-changes.out" 2>&1 ||
  ! grep -q '未提交的人工改动' "$TEST_ROOT/refuses-local-changes.out" ||
  ! grep -q '^drift$' "$TEST_ROOT/proj-desktop/AI-GOVERNANCE.md"; then
  printf 'FAIL refuses uncommitted project snapshot\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS refuses uncommitted project snapshot\n'
fi

# 自动发现：跳过治理仓自身，保留目录名内部空格，只纳管含 .git / 快照 / 项目入口的子目录。
discover_root="$TEST_ROOT/discover"
discover_repo="$discover_root/agent-governance"
mkdir -p "$discover_repo/global" "$discover_repo/scripts/internal" "$discover_repo/templates/project"
cp "$GOV" "$discover_repo/scripts/gov"
cp "$SCRIPT" "$discover_repo/scripts/internal/sync-project-governance.sh"
cp "$ROOT_DIR/scripts/internal/check-version-bump.sh" "$discover_repo/scripts/internal/check-version-bump.sh"
cp "$ROOT_DIR/scripts/internal/check-rule-paths.sh" "$discover_repo/scripts/internal/check-rule-paths.sh"
cp "$ROOT_DIR/templates/project/AI-GOVERNANCE.md" "$discover_repo/templates/project/AI-GOVERNANCE.md"
cp "$ROOT_DIR/VERSION" "$discover_repo/VERSION"
printf '* text=auto eol=lf\n' >"$discover_repo/.gitattributes"
printf 'entry\n' >"$discover_repo/AGENTS.md"
git -C "$discover_repo" init -q
git -C "$discover_repo" config user.name "Joseph Koh"
git -C "$discover_repo" config user.email "joseph@example.com"
git -C "$discover_repo" add .
git -C "$discover_repo" commit -q -m "chore: fixture"

mkdir -p "$discover_root/included-agents" "$discover_root/included-snapshot" "$discover_root/My App" "$discover_root/not-a-repo"
printf '# entry\n' >"$discover_root/included-agents/AGENTS.md"
printf '# snapshot\n' >"$discover_root/included-snapshot/AI-GOVERNANCE.md"
printf '# space repo\n' >"$discover_root/My App/AGENTS.md"
printf 'unrelated\n' >"$discover_root/not-a-repo/notes.txt"

if bash "$discover_repo/scripts/gov" project sync --root "$discover_root" >"$TEST_ROOT/discover.out" 2>&1; then
  if [[ -f "$discover_root/included-agents/AI-GOVERNANCE.md" &&
    -f "$discover_root/included-snapshot/AI-GOVERNANCE.md" &&
    -f "$discover_root/My App/AI-GOVERNANCE.md" &&
    ! -e "$discover_repo/AI-GOVERNANCE.md" &&
    ! -e "$discover_root/not-a-repo/AI-GOVERNANCE.md" ]]; then
    printf 'PASS auto-discovery-skips-self-and-supports-spaces\n'
  else
    printf 'FAIL auto-discovery-skips-self-and-supports-spaces\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'FAIL auto-discovery-skips-self-and-supports-spaces\n' >&2
  cat "$TEST_ROOT/discover.out" >&2
  failures=$((failures + 1))
fi

# 显式把治理仓自身传给 --repos 也必须拒绝。
if bash "$discover_repo/scripts/gov" project sync --root "$discover_root" --repos agent-governance >"$TEST_ROOT/reject-self.out" 2>&1; then
  printf 'FAIL reject-self-repo\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS reject-self-repo\n'
fi

# 未提交但自洽的脚本产物在「新版本再次同步」时必须通过前置检查与写入循环二次校验。
resync_repo="$TEST_ROOT/resync-repo"
mkdir -p "$resync_repo/global" "$resync_repo/scripts/internal" "$resync_repo/templates/project" \
  "$resync_repo/tests" "$resync_repo/.github" "$resync_repo/.githooks" "$resync_repo/skills/local/ai-change-flow"
printf 'global rules\n' >"$resync_repo/global/AGENTS.md"
printf 'tests\n' >"$resync_repo/tests/placeholder.sh"
printf 'owners\n' >"$resync_repo/.github/CODEOWNERS"
printf 'hook\n' >"$resync_repo/.githooks/commit-msg"
printf 'readme\n' >"$resync_repo/README.md"
printf 'onboarding\n' >"$resync_repo/onboarding.md"
printf 'skill\n' >"$resync_repo/skills/local/ai-change-flow/SKILL.md"
printf 'checker\n' >"$resync_repo/scripts/check-commit-attribution.sh"
printf 'distributor\n' >"$resync_repo/scripts/internal/distribute.sh"
cp "$GOV" "$resync_repo/scripts/gov"
cp "$SCRIPT" "$resync_repo/scripts/internal/sync-project-governance.sh"
cp "$ROOT_DIR/scripts/internal/check-version-bump.sh" "$resync_repo/scripts/internal/check-version-bump.sh"
cp "$ROOT_DIR/scripts/internal/check-rule-paths.sh" "$resync_repo/scripts/internal/check-rule-paths.sh"
cp "$ROOT_DIR/templates/project/AI-GOVERNANCE.md" "$resync_repo/templates/project/AI-GOVERNANCE.md"
printf '1.0.0\n' >"$resync_repo/VERSION"
printf '* text=auto eol=lf\n' >"$resync_repo/.gitattributes"
printf 'entry\n' >"$resync_repo/AGENTS.md"
git -C "$resync_repo" init -q
git -C "$resync_repo" config user.name "Joseph Koh"
git -C "$resync_repo" config user.email "joseph@example.com"
git -C "$resync_repo" add .
git -C "$resync_repo" commit -q -m "chore: fixture 1.0.0"
git -C "$resync_repo" update-ref refs/remotes/origin/main HEAD
git -C "$resync_repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

mkdir -p "$resync_repo/target/proj-a"
git -C "$resync_repo/target/proj-a" init -q
git -C "$resync_repo/target/proj-a" config user.name "Joseph Koh"
git -C "$resync_repo/target/proj-a" config user.email "joseph@example.com"
printf 'v0\n' >"$resync_repo/target/proj-a/AI-GOVERNANCE.md"
git -C "$resync_repo/target/proj-a" add .
git -C "$resync_repo/target/proj-a" commit -q -m "chore: seed"

if ! bash "$resync_repo/scripts/gov" project sync --root "$resync_repo/target" --repos proj-a >"$TEST_ROOT/resync1.out" 2>&1; then
  printf 'FAIL first-resync\n' >&2
  cat "$TEST_ROOT/resync1.out" >&2
  failures=$((failures + 1))
fi
first_hash="$(awk '/^> baseline-content-sha256: /{print $3}' "$resync_repo/target/proj-a/AI-GOVERNANCE.md")"

# 推进治理基线到 1.0.1（不提交 proj-a 的 1.0.0 快照），迫使第二次同步真正进入写入循环。
printf '\n<!-- bump 1.0.1 -->\n' >>"$resync_repo/templates/project/AI-GOVERNANCE.md"
printf '1.0.1\n' >"$resync_repo/VERSION"
git -C "$resync_repo" add templates/project/AI-GOVERNANCE.md VERSION
git -C "$resync_repo" commit -q -m "chore: release 1.0.1"
git -C "$resync_repo" update-ref refs/remotes/origin/main HEAD

if bash "$resync_repo/scripts/gov" project sync --root "$resync_repo/target" --repos proj-a >"$TEST_ROOT/resync2.out" 2>&1; then
  second_hash="$(awk '/^> baseline-content-sha256: /{print $3}' "$resync_repo/target/proj-a/AI-GOVERNANCE.md")"
  if [[ -n "$first_hash" && -n "$second_hash" && "$first_hash" != "$second_hash" ]] &&
    grep -q '^> baseline-version: 1.0.1$' "$resync_repo/target/proj-a/AI-GOVERNANCE.md"; then
    printf 'PASS uncommitted-generated-snapshot-overwritable-across-versions\n'
  else
    printf 'FAIL uncommitted-generated-snapshot-overwritable-across-versions (hash or version unchanged)\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'FAIL uncommitted-generated-snapshot-overwritable-across-versions\n' >&2
  cat "$TEST_ROOT/resync2.out" >&2
  failures=$((failures + 1))
fi

# 本地治理仓落后 origin/main 时必须拒绝同步旧版快照。
git -C "$resync_repo" checkout -q HEAD~1
if bash "$resync_repo/scripts/gov" project sync --root "$resync_repo/target" --repos proj-a >"$TEST_ROOT/behind.out" 2>&1; then
  printf 'FAIL reject-behind-origin-main\n' >&2
  failures=$((failures + 1))
elif grep -q '落后' "$TEST_ROOT/behind.out"; then
  printf 'PASS reject-behind-origin-main\n'
else
  printf 'FAIL reject-behind-origin-main (unexpected error)\n' >&2
  cat "$TEST_ROOT/behind.out" >&2
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
