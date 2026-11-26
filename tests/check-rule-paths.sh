#!/usr/bin/env bash
# 规则路径可达性检查的测试（覆盖默认静态仓内模式、真实仓库自检、--installed 模式与豁免清单）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-rule-paths.XXXXXX")"

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
  mkdir -p "$repo/scripts/internal" "$repo/global" "$repo/templates/project" "$repo/skills/local/ai-change-flow/references"
  cp "$ROOT_DIR/scripts/gov" "$repo/scripts/gov"
  cp "$ROOT_DIR/scripts/internal/check-rule-paths.sh" "$repo/scripts/internal/check-rule-paths.sh"
  printf 'placeholder\n' >"$repo/AGENTS.md"
  printf 'placeholder\n' >"$repo/global/AGENTS.md"
  printf 'placeholder\n' >"$repo/templates/project/AI-GOVERNANCE.md"
  printf 'placeholder\n' >"$repo/README.md"
  printf 'placeholder\n' >"$repo/onboarding.md"
  printf 'placeholder\n' >"$repo/skills/README.md"
  printf 'placeholder\n' >"$repo/skills/local/ai-change-flow/SKILL.md"
  printf 'placeholder\n' >"$repo/skills/local/ai-change-flow/references/full-flow.md"
  printf '%s\n' "$repo"
}

# 1. 真实仓库必须通过默认静态模式，且确实校验了多条仓内路径（不能 0 匹配空过）。
if bash "$ROOT_DIR/scripts/gov" check paths >"$TEST_ROOT/real-repo.out" 2>&1 &&
  grep -Eq '规则内 [1-9][0-9]* 条仓内路径引用全部可达' "$TEST_ROOT/real-repo.out"; then
  report real-repo-static-paths 1
else
  cat "$TEST_ROOT/real-repo.out" >&2 || true
  report real-repo-static-paths 0
fi

# 2. 合法仓内相对路径、Skill 内 references/ 相对路径与 Markdown 锚点链接应当通过且计数 > 0。
repo="$(make_fixture valid-repo)"
printf '主规则见 `global/AGENTS.md`、脚本见 `scripts/gov`，说明见 [指南](onboarding.md#section)。\n' >"$repo/AGENTS.md"
printf '正文见 `references/full-flow.md`。\n' >"$repo/skills/local/ai-change-flow/SKILL.md"
if bash "$repo/scripts/gov" check paths >"$TEST_ROOT/valid-repo.out" 2>&1 &&
  grep -Eq '规则内 [4-9]|[1-9][0-9]+ 条仓内路径引用全部可达' "$TEST_ROOT/valid-repo.out"; then
  report valid-repo-paths-pass 1
else
  cat "$TEST_ROOT/valid-repo.out" >&2 || true
  report valid-repo-paths-pass 0
fi

# 3. 仓内不存在的相对路径与断链必须被拦下。
repo="$(make_fixture missing-repo)"
printf '过时引用 `global/ai-change-implementation-prompt.md` 与 [坏链](does-not-exist.md)。\n' >"$repo/AGENTS.md"
printf '正文见 `references/missing-flow.md`。\n' >"$repo/skills/local/ai-change-flow/SKILL.md"
if bash "$repo/scripts/gov" check paths >"$TEST_ROOT/missing-repo.out" 2>&1; then
  report missing-repo-paths-fail 0
else
  if grep -q 'global/ai-change-implementation-prompt.md' "$TEST_ROOT/missing-repo.out" &&
    grep -q 'does-not-exist.md' "$TEST_ROOT/missing-repo.out" &&
    grep -q 'references/missing-flow.md' "$TEST_ROOT/missing-repo.out"; then
    report missing-repo-paths-fail 1
  else
    cat "$TEST_ROOT/missing-repo.out" >&2
    report missing-repo-paths-fail 0
  fi
fi

# 4. --list 只列不判，即使路径不存在也退出 0 且输出该路径。
if bash "$repo/scripts/gov" check paths --list >"$TEST_ROOT/list.out" 2>&1 &&
  grep -q 'global/ai-change-implementation-prompt.md' "$TEST_ROOT/list.out"; then
  report list-mode-exits-zero 1
else
  report list-mode-exits-zero 0
fi

# 5. --installed 模式：在隔离 HOME 下，已存在路径通过、豁免路径（不存在于磁盘）跳过且计数 > 0。
repo="$(make_fixture installed-ok)"
fake_home="$TEST_ROOT/fake-home-ok"
mkdir -p "$fake_home/.codex"
printf 'ok\n' >"$fake_home/.codex/AGENTS.md"
printf '见 `~/.codex/AGENTS.md`、`$HOME/.codex/AGENTS.md`、~/.codex/AGENTS.md（真源）、~/.codex/AGENTS.md(copy)；豁免 `~/.claude/settings.json` 与 `~/.codex/ai-change-implementation-prompt.md`。\n' \
  >"$repo/global/AGENTS.md"
if HOME="$fake_home" bash "$repo/scripts/gov" check paths --installed >"$TEST_ROOT/inst-ok.out" 2>&1 &&
  grep -q '规则内 2 条本机绝对路径引用全部可达' "$TEST_ROOT/inst-ok.out"; then
  report installed-reachable-and-exempt 1
else
  cat "$TEST_ROOT/inst-ok.out" >&2 || true
  report installed-reachable-and-exempt 0
fi

# 6. --installed 模式：不存在的非豁免 ~/ 路径必须被拦下。
repo="$(make_fixture installed-missing)"
fake_home_miss="$TEST_ROOT/fake-home-miss"
mkdir -p "$fake_home_miss"
printf '见 `~/definitely-not-here-9f3a/AGENTS.md`。\n' >"$repo/global/AGENTS.md"
if HOME="$fake_home_miss" bash "$repo/scripts/gov" check paths --installed >"$TEST_ROOT/inst-miss.out" 2>&1; then
  report installed-missing-fails 0
else
  grep -q 'definitely-not-here-9f3a' "$TEST_ROOT/inst-miss.out" &&
    report installed-missing-fails 1 || report installed-missing-fails 0
fi

if (( failures > 0 )); then
  printf '%d rule-path check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'All rule-path checks passed.\n'
