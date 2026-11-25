#!/usr/bin/env bash
set -euo pipefail

# 隔离宿主机环境变量，避免外部工具目录配置或保留策略污染测试夹具。
unset CLAUDE_CONFIG_DIR PI_CODING_AGENT_DIR XDG_CONFIG_HOME OPENCODE_CONFIG_DIR \
  DSH_HOME WORKBUDDY_CONFIG_DIR OMP_PROFILE PI_PROFILE PI_CONFIG_DIR \
  AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS AGENT_GOVERNANCE_BACKUP_KEEP

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-distribute.XXXXXX")"
native_windows=0
case "$(uname -s)" in
  MINGW*|MSYS*)
    native_windows=1
    TEST_ROOT="$(cygpath -u "$(cygpath -w "$TEST_ROOT")")"
    ;;
esac

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

failures=0

with_home() {
  local home="$1"
  shift
  if [[ "$native_windows" == 1 ]]; then
    local win_home
    win_home="$(cygpath -w "$home")"
    HOME="$home" USERPROFILE="$win_home" "$@"
  else
    HOME="$home" "$@"
  fi
}

make_fixture() {
  local name="$1"
  local repo="$TEST_ROOT/$name/repo"

  mkdir -p "$repo/global/git-hooks" "$repo/.github" "$repo/.githooks" "$repo/scripts" "$repo/tests" "$repo/templates/project" "$repo/skills/local/ai-change-flow/references"
  git init -q "$repo"
  git -C "$repo" config user.name "Joseph Koh"
  git -C "$repo" config user.email "joseph@example.com"
  mkdir -p "$TEST_ROOT/empty-hooks"
  git -C "$repo" config core.hooksPath "$TEST_ROOT/empty-hooks"

  printf 'global rules v1\n' >"$repo/global/AGENTS.md"
  printf 'skill flow v1\n' >"$repo/skills/local/ai-change-flow/references/full-flow.md"
  printf 'global commit-msg hook\n' >"$repo/global/git-hooks/commit-msg"
  printf 'global chain helper\n' >"$repo/global/git-hooks/_chain"
  printf 'global pre-commit hook\n' >"$repo/global/git-hooks/pre-commit"
  printf 'global pre-push hook\n' >"$repo/global/git-hooks/pre-push"
  printf 'owners\n' >"$repo/.github/CODEOWNERS"
  printf 'hook\n' >"$repo/.githooks/commit-msg"
  printf 'readme\n' >"$repo/README.md"
  printf 'onboarding\n' >"$repo/onboarding.md"
  printf 'attribution checker\n' >"$repo/scripts/check-commit-attribution.sh"
  printf 'project template\n' >"$repo/templates/project/AI-GOVERNANCE.md"
  printf 'project sync\n' >"$repo/scripts/sync-project-governance.sh"
  cp "$ROOT_DIR/scripts/check-version-bump.sh" "$repo/scripts/check-version-bump.sh"
  cp "$ROOT_DIR/scripts/check-rule-paths.sh" "$repo/scripts/check-rule-paths.sh"
  cp "$ROOT_DIR/scripts/distribute.sh" "$repo/scripts/distribute.sh"
  printf 'baseline tests\n' >"$repo/tests/placeholder.sh"
  printf '1.0.0\n' >"$repo/VERSION"
  printf '* text=auto eol=lf\n' >"$repo/.gitattributes"
  printf '# pointer\nSee `global/AGENTS.md`.\n' >"$repo/AGENTS.md"

  git -C "$repo" add .
  git -C "$repo" commit -q -m "chore: baseline"
  printf '%s\n' "$repo"
}

run_distribution() {
  local repo="$1"
  local home="$2"
  mkdir -p "$home"
  with_home "$home" bash "$repo/scripts/distribute.sh" >"$home/distribute.out" 2>&1
}

expect_failure() {
  local label="$1"
  shift
  local actual_code

  set +e
  "$@" >"$TEST_ROOT/$label.out" 2>&1
  actual_code=$?
  set -e

  if [[ "$actual_code" -ne 0 ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (expected failure)\n' "$label" >&2
    cat "$TEST_ROOT/$label.out" >&2
    failures=$((failures + 1))
  fi
}

expect_same_content() {
  local label="$1"
  local expected_file="$2"
  local actual_file="$3"

  if [[ -f "$actual_file" ]] && cmp -s "$expected_file" "$actual_file"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

expect_symlink_or_copy() {
  local label="$1"
  local expected_target="$2"
  local link_path="$3"

  if [[ "$native_windows" == 1 ]]; then
    expect_same_content "$label" "$expected_target" "$link_path"
  elif [[ -L "$link_path" && "$(readlink "$link_path")" == "$expected_target" ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

# 1. 远端 fetch 失败必须失败关闭，不安装旧规则。
remote_failure_repo="$(make_fixture remote-failure)"
remote_failure_home="$TEST_ROOT/remote-failure/home"
git -C "$remote_failure_repo" remote add origin "$TEST_ROOT/remote-failure/missing-remote"
expect_failure remote-fetch-fails-closed run_distribution "$remote_failure_repo" "$remote_failure_home"
if [[ -e "$remote_failure_home/.codex/AGENTS.md" ]]; then
  printf 'FAIL remote-fetch-does-not-install (stale rules were installed)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS remote-fetch-does-not-install\n'
fi

# 2. POSIX 软链目标防护。
if [[ "$native_windows" == 0 ]]; then
  symlink_repo="$(make_fixture symlink-target)"
  symlink_home="$TEST_ROOT/symlink-target/home"
  mkdir -p "$symlink_home/.codex"
  printf 'sensitive sentinel\n' >"$symlink_home/outside.txt"
  ln -s "$symlink_home/outside.txt" "$symlink_home/.codex/AGENTS.md"
  expect_failure managed-symlink-rejected run_distribution "$symlink_repo" "$symlink_home"
  if [[ "$(<"$symlink_home/outside.txt")" == 'sensitive sentinel' ]]; then
    printf 'PASS managed-symlink-target-unchanged\n'
  else
    printf 'FAIL managed-symlink-target-unchanged\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'SKIP managed-symlink-rejected (windows)\n'
fi

# 3. 整组快照回滚 + 历史旧快照（较少目标）回滚 + 篡改快照拒绝。
rollback_repo="$(make_fixture rollback)"
rollback_home="$TEST_ROOT/rollback/home"
run_distribution "$rollback_repo" "$rollback_home"

printf 'global rules v2\n' >"$rollback_repo/global/AGENTS.md"
printf '1.1.0\n' >"$rollback_repo/VERSION"
git -C "$rollback_repo" add global/AGENTS.md VERSION
git -C "$rollback_repo" commit -q -m "chore: release 1.1.0"
run_distribution "$rollback_repo" "$rollback_home"
expected_agents="$(<"$rollback_home/.codex/AGENTS.md")"
expected_checker="$(<"$rollback_home/.codex/check-commit-attribution.sh")"
expected_version="$(<"$rollback_home/.codex/.gov-version")"

printf 'attribution checker v2\n' >"$rollback_repo/scripts/check-commit-attribution.sh"
printf '1.2.0\n' >"$rollback_repo/VERSION"
git -C "$rollback_repo" add scripts/check-commit-attribution.sh VERSION
git -C "$rollback_repo" commit -q -m "chore: release 1.2.0"
run_distribution "$rollback_repo" "$rollback_home"
with_home "$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback >"$rollback_home/rollback.out" 2>&1

if [[ "$(<"$rollback_home/.codex/AGENTS.md")" == "$expected_agents" ]]; then
  printf 'PASS rollback-restores-agents-as-group\n'
else
  printf 'FAIL rollback-restores-agents-as-group\n' >&2
  failures=$((failures + 1))
fi
if [[ "$(<"$rollback_home/.codex/check-commit-attribution.sh")" == "$expected_checker" ]]; then
  printf 'PASS rollback-restores-checker-as-group\n'
else
  printf 'FAIL rollback-restores-checker-as-group\n' >&2
  failures=$((failures + 1))
fi
if [[ "$(<"$rollback_home/.codex/.gov-version")" == "$expected_version" ]]; then
  printf 'PASS rollback-restores-version-as-group\n'
else
  printf 'FAIL rollback-restores-version-as-group\n' >&2
  failures=$((failures + 1))
fi

# 模拟更早版本快照（仅包含前 2 条受管路径），仍应可安全回滚，不因新增目标失败。
subset_snap="$rollback_home/.codex/.gov-backup/99990101-000000-00000000"
mkdir -p "$subset_snap"
printf 'from older schema\n' >"$subset_snap/0"
printf '1.0.5\n' >"$subset_snap/1"
printf '0\t%s\tpresent\n1\t%s\tpresent\n' \
  "$rollback_home/.codex/AGENTS.md" "$rollback_home/.codex/.gov-version" >"$subset_snap/manifest"
if with_home "$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback >"$TEST_ROOT/subset-rollback.out" 2>&1 &&
  [[ "$(<"$rollback_home/.codex/AGENTS.md")" == 'from older schema' ]] &&
  [[ "$(<"$rollback_home/.codex/.gov-version")" == '1.0.5' ]]; then
  printf 'PASS rollback-supports-older-target-subset\n'
else
  printf 'FAIL rollback-supports-older-target-subset\n' >&2
  cat "$TEST_ROOT/subset-rollback.out" >&2 || true
  failures=$((failures + 1))
fi

# 篡改 manifest 加入非受管路径（如 settings.json）必须被白名单拒绝。
printf '0\t%s\tabsent\n' "$rollback_home/.claude/settings.json" >"$subset_snap/manifest"
mkdir -p "$rollback_home/.claude"
printf '{"keep":true}\n' >"$rollback_home/.claude/settings.json"
expect_failure rollback-rejects-unmanaged-path \
  with_home "$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback
if [[ "$(<"$rollback_home/.claude/settings.json")" == '{"keep":true}' ]]; then
  printf 'PASS rollback-preserves-unmanaged-settings\n'
else
  printf 'FAIL rollback-preserves-unmanaged-settings\n' >&2
  failures=$((failures + 1))
fi

# 预检原子性：若快照包含已退役路径且该路径被替换成软链，必须在写前整组拒绝，不得半回滚前项。
if [[ "$native_windows" == 0 ]]; then
  printf 'atomic sentinel\n' >"$rollback_home/.codex/AGENTS.md"
  printf 'new retired content\n' >"$subset_snap/1"
  printf '0\t%s\tpresent\n1\t%s\tpresent\n' \
    "$rollback_home/.codex/AGENTS.md" "$rollback_home/.codex/ai-change-implementation-prompt.md" >"$subset_snap/manifest"
  ln -s "$rollback_home/.claude/settings.json" "$rollback_home/.codex/ai-change-implementation-prompt.md"
  expect_failure rollback-prechecks-retired-symlink \
    with_home "$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback
  rm -f "$rollback_home/.codex/ai-change-implementation-prompt.md"
  if [[ "$(<"$rollback_home/.codex/AGENTS.md")" == 'atomic sentinel' ]]; then
    printf 'PASS rollback-no-partial-write-on-retired-symlink\n'
  else
    printf 'FAIL rollback-no-partial-write-on-retired-symlink\n' >&2
    failures=$((failures + 1))
  fi
fi
rm -rf "$subset_snap"

# 4. 治理仓自身的工作区级入口：根 AGENTS.md 必须是指针，不能是软链或真源副本。
if [[ -f "$ROOT_DIR/AGENTS.md" && ! -L "$ROOT_DIR/AGENTS.md" ]] &&
  grep -q 'global/AGENTS.md' "$ROOT_DIR/AGENTS.md" &&
  ! grep -q '^## 变更分级' "$ROOT_DIR/AGENTS.md"; then
  printf 'PASS repo-root-agents-pointer\n'
else
  printf 'FAIL repo-root-agents-pointer（根 AGENTS.md 必须是指针文件，不能是软链或真源副本）\n' >&2
  failures=$((failures + 1))
fi

# 5. 全部分发目标落地检查（含 Zed、Amp、Copilot、OrbStack work/CLAUDE.md）。
targets_repo="$(make_fixture targets)"
targets_home="$TEST_ROOT/targets/home"
run_distribution "$targets_repo" "$targets_home"

canonical="$targets_home/.codex/AGENTS.md"
expect_same_content canonical-agents "$targets_repo/global/AGENTS.md" "$canonical"
expect_same_content canonical-checker \
  "$targets_repo/scripts/check-commit-attribution.sh" \
  "$targets_home/.codex/check-commit-attribution.sh"
expect_same_content canonical-hook-commit-msg \
  "$targets_repo/global/git-hooks/commit-msg" \
  "$targets_home/.codex/git-hooks/commit-msg"
expect_same_content copy-work-claude "$targets_repo/global/AGENTS.md" "$targets_home/Documents/work/CLAUDE.md"
expect_same_content copy-copilot "$targets_repo/global/AGENTS.md" "$targets_home/.copilot/copilot-instructions.md"

if [[ -x "$targets_home/.codex/git-hooks/commit-msg" && -x "$targets_home/.codex/git-hooks/pre-commit" ]]; then
  printf 'PASS global-hooks-executable\n'
else
  printf 'FAIL global-hooks-executable\n' >&2
  failures=$((failures + 1))
fi

if with_home "$targets_home" git config --global --get core.hooksPath >/dev/null 2>&1; then
  printf 'FAIL distribution-must-not-mask-native-hooks\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS distribution-does-not-mask-native-hooks\n'
fi

expect_symlink_or_copy link-claude-code "$canonical" "$targets_home/.claude/CLAUDE.md"
expect_symlink_or_copy link-pi "$canonical" "$targets_home/.pi/agent/AGENTS.md"
expect_symlink_or_copy link-opencode "$canonical" "$targets_home/.config/opencode/AGENTS.md"
expect_symlink_or_copy link-dsh "$canonical" "$targets_home/.dsh/AGENTS.md"
expect_symlink_or_copy link-commandcode "$canonical" "$targets_home/.commandcode/AGENTS.md"
expect_symlink_or_copy link-omp "$canonical" "$targets_home/.omp/agent/AGENTS.md"
expect_symlink_or_copy link-zed "$canonical" "$targets_home/.config/zed/AGENTS.md"
expect_symlink_or_copy link-amp "$canonical" "$targets_home/.config/amp/AGENTS.md"

workbuddy_rule="$targets_home/.workbuddy-ai/rules/agent-governance.md"
if [[ -f "$workbuddy_rule" ]] && grep -q '^alwaysApply: true$' "$workbuddy_rule"; then
  printf 'PASS workbuddy-rule-frontmatter\n'
else
  printf 'FAIL workbuddy-rule-frontmatter\n' >&2
  failures=$((failures + 1))
fi

workbuddy_body="$TEST_ROOT/workbuddy-body.md"
awk '/^---$/ { n++; next } n == 2 { if (!started) { if ($0 == "") next; started = 1 } print }' \
  "$workbuddy_rule" >"$workbuddy_body" 2>/dev/null || true
expect_same_content workbuddy-rule-body-matches-agents "$targets_repo/global/AGENTS.md" "$workbuddy_body"

if [[ -L "$workbuddy_rule" ]]; then
  printf 'FAIL workbuddy-rule-is-generated-file (unexpected symlink)\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS workbuddy-rule-is-generated-file\n'
fi

# 6. 幂等重跑不新建快照。
snapshots_before="$(ls -1d "$targets_home/.codex/.gov-backup"/[0-9]*/ 2>/dev/null | wc -l | tr -d ' ')"
run_distribution "$targets_repo" "$targets_home"
snapshots_after="$(ls -1d "$targets_home/.codex/.gov-backup"/[0-9]*/ 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$snapshots_before" == "$snapshots_after" && "$snapshots_before" -gt 0 ]]; then
  printf 'PASS idempotent-rerun-creates-no-snapshot\n'
else
  printf 'FAIL idempotent-rerun-creates-no-snapshot (before=%s after=%s)\n' "$snapshots_before" "$snapshots_after" >&2
  failures=$((failures + 1))
fi

# 7. 退役路径：--check 必须检出未退役孤儿文件；分发必须迁走并留备份。
retired_file="$targets_home/.codex/ai-change-implementation-prompt.md"
printf 'stale flow from an older release\n' >"$retired_file"
set +e
with_home "$targets_home" bash "$targets_repo/scripts/distribute.sh" --check >"$TEST_ROOT/check-retired.out" 2>&1
check_retired_code=$?
set -e
if [[ "$check_retired_code" -ne 0 ]] && grep -q '未退役' "$TEST_ROOT/check-retired.out"; then
  printf 'PASS check-detects-lingering-retired-path\n'
else
  printf 'FAIL check-detects-lingering-retired-path (exit %s)\n' "$check_retired_code" >&2
  cat "$TEST_ROOT/check-retired.out" >&2
  failures=$((failures + 1))
fi

run_distribution "$targets_repo" "$targets_home"
if [[ ! -e "$retired_file" ]] &&
  grep -rqs 'stale flow from an older release' "$targets_home/.codex/.gov-backup/retired-"*; then
  printf 'PASS retired-path-removed-with-backup\n'
else
  printf 'FAIL retired-path-removed-with-backup\n' >&2
  failures=$((failures + 1))
fi

# 8. --check 一致性、手工修改和旧版本号检测。
with_home "$targets_home" bash "$targets_repo/scripts/distribute.sh" --check >"$TEST_ROOT/check-clean.out" 2>&1
check_clean_code=$?
if [[ "$check_clean_code" -eq 0 ]]; then
  printf 'PASS check-reports-clean-install\n'
else
  printf 'FAIL check-reports-clean-install (exit %s)\n' "$check_clean_code" >&2
  cat "$TEST_ROOT/check-clean.out" >&2
  failures=$((failures + 1))
fi

printf '# hand edited\n' >>"$targets_home/.codex/AGENTS.md"
set +e
with_home "$targets_home" bash "$targets_repo/scripts/distribute.sh" --check >"$TEST_ROOT/check-drift.out" 2>&1
check_drift_code=$?
set -e
if [[ "$check_drift_code" -ne 0 ]] && grep -q '不一致' "$TEST_ROOT/check-drift.out"; then
  printf 'PASS check-detects-hand-edited-copy\n'
else
  printf 'FAIL check-detects-hand-edited-copy (exit %s)\n' "$check_drift_code" >&2
  cat "$TEST_ROOT/check-drift.out" >&2
  failures=$((failures + 1))
fi

printf '0.9.0\n' >"$targets_home/.codex/.gov-version"
set +e
with_home "$targets_home" bash "$targets_repo/scripts/distribute.sh" --check >"$TEST_ROOT/check-version.out" 2>&1
check_version_code=$?
set -e
if [[ "$check_version_code" -ne 0 ]] && grep -q '版本' "$TEST_ROOT/check-version.out"; then
  printf 'PASS check-detects-stale-version\n'
else
  printf 'FAIL check-detects-stale-version (exit %s)\n' "$check_version_code" >&2
  cat "$TEST_ROOT/check-version.out" >&2
  failures=$((failures + 1))
fi

# 9. 字节长度门禁拒绝超过 24000 字节的 AGENTS.md。
oversize_repo="$(make_fixture oversize)"
oversize_home="$TEST_ROOT/oversize/home"
head -c 25000 /dev/zero | tr '\0' 'a' >"$oversize_repo/global/AGENTS.md"
printf '1.0.1\n' >"$oversize_repo/VERSION"
git -C "$oversize_repo" add global/AGENTS.md VERSION
git -C "$oversize_repo" commit -q -m "chore: oversize rules"
expect_failure reject-oversize-agents-bytes run_distribution "$oversize_repo" "$oversize_home"

# 10. 快照保留上限裁剪旧快照，且保留 retired-* 备份。
retain_repo="$(make_fixture retain)"
retain_home="$TEST_ROOT/retain/home"
mkdir -p "$retain_home/.codex"
printf 'old retired\n' >"$retain_home/.codex/ai-change-implementation-prompt.md"
for step in 1 2 3 4; do
  printf 'global rules step %s\n' "$step" >"$retain_repo/global/AGENTS.md"
  printf '1.0.%s\n' "$step" >"$retain_repo/VERSION"
  git -C "$retain_repo" add global/AGENTS.md VERSION
  git -C "$retain_repo" commit -q -m "chore: step $step"
  AGENT_GOVERNANCE_BACKUP_KEEP=2 run_distribution "$retain_repo" "$retain_home"
done
kept_count="$(ls -1d "$retain_home/.codex/.gov-backup"/[0-9]*/ 2>/dev/null | wc -l | tr -d ' ')"
retired_kept="$(ls -1d "$retain_home/.codex/.gov-backup"/retired-*/ 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$kept_count" -eq 2 && "$retired_kept" -ge 1 ]]; then
  printf 'PASS backup-retention-prunes-old-and-keeps-retired\n'
else
  printf 'FAIL backup-retention-prunes-old-and-keeps-retired (kept=%s retired=%s)\n' "$kept_count" "$retired_kept" >&2
  failures=$((failures + 1))
fi

# 11. 路径安全边界 + 自定义工具配置目录（CLAUDE_CONFIG_DIR / OPENCODE_CONFIG_DIR）。
mkdir -p "$TEST_ROOT/unsafe-home"
unsafe_home="$TEST_ROOT/unsafe-home"
expect_failure reject-parent-traversal with_home "$unsafe_home" env DSH_HOME="$unsafe_home/../outside" \
  bash "$targets_repo/scripts/distribute.sh" --list-targets
expect_failure reject-copy-link-collision with_home "$unsafe_home" env DSH_HOME="$unsafe_home/.CODEX" \
  bash "$targets_repo/scripts/distribute.sh" --list-targets
expect_failure reject-nested-target with_home "$unsafe_home" env DSH_HOME="$unsafe_home/.codex/AGENTS.md" \
  bash "$targets_repo/scripts/distribute.sh" --list-targets

custom_env_home="$TEST_ROOT/custom-env-home"
mkdir -p "$custom_env_home"
if with_home "$custom_env_home" env CLAUDE_CONFIG_DIR="$custom_env_home/.custom-claude" \
  OPENCODE_CONFIG_DIR="$custom_env_home/.custom-opencode" \
  bash "$targets_repo/scripts/distribute.sh" --list-targets >"$TEST_ROOT/custom-env.out" 2>&1 &&
  grep -q "$custom_env_home/.custom-claude/CLAUDE.md" "$TEST_ROOT/custom-env.out" &&
  grep -q "$custom_env_home/.custom-opencode/AGENTS.md" "$TEST_ROOT/custom-env.out"; then
  printf 'PASS honors-custom-tool-config-dirs\n'
else
  printf 'FAIL honors-custom-tool-config-dirs\n' >&2
  cat "$TEST_ROOT/custom-env.out" >&2 || true
  failures=$((failures + 1))
fi

if [[ "$native_windows" == 0 ]]; then
  mkdir -p "$unsafe_home/.codex" "$TEST_ROOT/unsafe-outside"
  ln -s "$TEST_ROOT/unsafe-outside" "$unsafe_home/.workbuddy-ai"
  expect_failure reject-parent-symlink run_distribution "$targets_repo" "$unsafe_home"
  rm -f "$unsafe_home/.workbuddy-ai"
  printf 'do not overwrite\n' >"$TEST_ROOT/unsafe-outside/sentinel"
  ln -s "$TEST_ROOT/unsafe-outside/sentinel" "$unsafe_home/.codex/.gov-version"
  expect_failure reject-version-symlink run_distribution "$targets_repo" "$unsafe_home"
  if ! grep -q '\.gov-version' "$unsafe_home/distribute.out" ||
    [[ "$(<"$TEST_ROOT/unsafe-outside/sentinel")" != 'do not overwrite' ]]; then
    printf 'FAIL symlink-version-was-not-the-rejection-reason\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'SKIP posix-parent-and-version-symlink-tests (windows)\n'
fi

# 12. 旧全局 core.hooksPath 迁移（含绝对路径与字面 ~/ 写法）。
mount_repo="$(make_fixture mount)"
mount_home="$TEST_ROOT/mount/home"
run_distribution "$mount_repo" "$mount_home"
with_home "$mount_home" git config --global core.hooksPath "$mount_home/.codex/git-hooks"
expect_failure check-rejects-legacy-hook-override with_home "$mount_home" \
  bash "$mount_repo/scripts/distribute.sh" --check
run_distribution "$mount_repo" "$mount_home"
if with_home "$mount_home" git config --global --get core.hooksPath >/dev/null 2>&1; then
  printf 'FAIL legacy-global-override-survived-migration\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS legacy-global-override-migrated\n'
fi

# 字面 ~/.codex/git-hooks/（带波浪线与尾斜杠）也必须自动迁移成功。
with_home "$mount_home" git config --global core.hooksPath '~/.codex/git-hooks/'
run_distribution "$mount_repo" "$mount_home"
if with_home "$mount_home" git config --global --get core.hooksPath >/dev/null 2>&1; then
  printf 'FAIL legacy-tilde-override-survived-migration\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS legacy-tilde-override-migrated\n'
fi

native_repo="$TEST_ROOT/native-repo"
with_home "$mount_home" git init -q "$native_repo"
mkdir -p "$native_repo/.git/hooks"
printf '#!/usr/bin/env bash\nprintf "native prepare hook\\n"\nexit 17\n' >"$native_repo/.git/hooks/prepare-commit-msg"
chmod +x "$native_repo/.git/hooks/prepare-commit-msg"
status=0
with_home "$mount_home" git -C "$native_repo" hook run prepare-commit-msg -- COMMIT_EDITMSG message \
  >"$TEST_ROOT/native-hook.out" 2>&1 || status=$?
if [[ "$status" == 17 ]] && grep -q 'native prepare hook' "$TEST_ROOT/native-hook.out"; then
  printf 'PASS git-selects-native-project-hook-after-migration\n'
else
  printf 'FAIL git-selects-native-project-hook-after-migration\n' >&2
  failures=$((failures + 1))
fi

included="$mount_home/included.gitconfig"
with_home "$mount_home" git config --file "$included" core.hooksPath "$mount_home/custom-hooks"
with_home "$mount_home" git config --global include.path "$included"
run_distribution "$mount_repo" "$mount_home"
[[ "$(with_home "$mount_home" git config --global --includes --get core.hooksPath)" == "$mount_home/custom-hooks" ]]
with_home "$mount_home" git config --file "$included" core.hooksPath '~/.codex/git-hooks'
expect_failure check-rejects-included-legacy-alias with_home "$mount_home" \
  bash "$mount_repo/scripts/distribute.sh" --check
[[ "$(with_home "$mount_home" git config --file "$included" --get core.hooksPath)" == '~/.codex/git-hooks' ]]
with_home "$mount_home" git config --global --unset include.path
if [[ "$native_windows" == 0 ]]; then
  chmod -x "$mount_home/.codex/git-hooks/commit-msg"
  expect_failure check-rejects-missing-executable-bit with_home "$mount_home" \
    bash "$mount_repo/scripts/distribute.sh" --check
else
  printf 'SKIP check-rejects-missing-executable-bit (windows)\n'
fi

latest_backup="$(ls -1d "$rollback_home/.codex/.gov-backup"/[0-9]*/ | LC_ALL=C sort | tail -1)"
expected_sentinel='preserve on damaged rollback'
printf '%s\n' "$expected_sentinel" >"$rollback_home/.codex/AGENTS.md"
rm -f "$latest_backup/1"
expect_failure reject-incomplete-backup with_home "$rollback_home" bash "$rollback_repo/scripts/distribute.sh" --rollback
[[ "$(<"$rollback_home/.codex/AGENTS.md")" == "$expected_sentinel" ]]

if (( failures > 0 )); then
  printf '%d distribution checks failed.\n' "$failures" >&2
  exit 1
fi

printf 'All distribution checks passed.\n'
