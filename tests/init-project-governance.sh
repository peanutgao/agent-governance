#!/usr/bin/env bash
# 端到端测试：轻量项目治理脚手架（单端 / 多端 Monorepo / --add-app / sync 互操作 / Spec 与归属门禁）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOV_SCRIPT="$ROOT_DIR/scripts/gov"

PY_CMD=python3
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PY_CMD=python; export PYTHONUTF8=1 ;;
esac
export PYTHONDONTWRITEBYTECODE=1

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/agent-governance-kit-test.XXXXXX")"
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "${2:-}" >&2; failures=$((failures + 1)); }

# 1. 静态语法检查（bash -n + py_compile，不污染源码 __pycache__）
syntax_ok=1
for shf in \
  "$GOV_SCRIPT" \
  "$ROOT_DIR"/templates/project/kit/scripts/governance/*.sh \
  "$ROOT_DIR"/templates/project/kit/.githooks/*; do
  bash -n "$shf" 2>"$TEST_ROOT/sh-err.out" || { cat "$TEST_ROOT/sh-err.out" >&2; syntax_ok=0; }
done
PYTHONPYCACHEPREFIX="$TEST_ROOT/pycache" "$PY_CMD" -m py_compile \
  "$ROOT_DIR/scripts/internal/init_project_governance.py" \
  "$ROOT_DIR/templates/project/kit/scripts/governance/check-spec-sync.py" 2>"$TEST_ROOT/py-err.out" || { cat "$TEST_ROOT/py-err.out" >&2; syntax_ok=0; }
[[ "$syntax_ok" == 1 ]] && pass syntax-bash-and-python || fail syntax-bash-and-python

# 2. 拒绝在治理仓自身内部初始化 + dry-run 不写入
if bash "$GOV_SCRIPT" project init --target "$ROOT_DIR" >/dev/null 2>&1; then
  fail refuse-self-target
else
  pass refuse-self-target
fi

DRY_DIR="$TEST_ROOT/dry-app"
if bash "$GOV_SCRIPT" project init --target "$DRY_DIR" --dry-run >/dev/null 2>&1 && [[ ! -e "$DRY_DIR" ]]; then
  pass dry-run-no-writes
else
  fail dry-run-no-writes
fi

# 3. 单端初始化 + 既有文件不覆盖 + 与 scripts/gov project sync 字节一致互操作
WS_ROOT="$TEST_ROOT/workspace"
APP_DIR="$WS_ROOT/demo-app"
mkdir -p "$APP_DIR"
printf '# Keep existing README\n' >"$APP_DIR/AGENTS.md"

if bash "$GOV_SCRIPT" project init --target "$APP_DIR" --project-name "DemoApp" >/dev/null &&
   grep -q "Keep existing README" "$APP_DIR/AGENTS.md" &&
   [[ -f "$APP_DIR/CLAUDE.md" && -f "$APP_DIR/.github/CODEOWNERS" && -f "$APP_DIR/AI-GOVERNANCE.md" &&
      -f "$APP_DIR/scripts/governance/check-spec-sync.py" && -f "$APP_DIR/scripts/governance/check-commit-attribution.sh" ]] &&
   bash "$GOV_SCRIPT" project sync --check --root "$WS_ROOT" --repos "demo-app" >/dev/null; then
  pass single-app-init-preserves-existing-and-sync-interop
else
  fail single-app-init-preserves-existing-and-sync-interop
fi

# 已初始化后禁止重复 init
if bash "$GOV_SCRIPT" project init --target "$APP_DIR" >/dev/null 2>&1; then
  fail refuse-repeat-init
else
  pass refuse-repeat-init
fi

# 4. 本地 commit-msg 钩子、install-hooks 保护 Husky、unborn HEAD、Spec-Exempt、scissors、单测豁免、分叉 merge-base、Todo ready-to-close
git -C "$APP_DIR" init -q
git -C "$APP_DIR" config user.name "Alice Dev"
git -C "$APP_DIR" config user.email "alice@example.com"

git -C "$APP_DIR" config --local core.hooksPath ".husky"
if bash "$APP_DIR/scripts/governance/install-hooks.sh" >/dev/null 2>&1; then
  fail install-hooks-protects-existing
else
  bash "$APP_DIR/scripts/governance/install-hooks.sh" --force >/dev/null
  pass install-hooks-protects-existing
fi

mkdir -p "$APP_DIR/src"
printf 'export const v = 1;\n' >"$APP_DIR/src/app.ts"
git -C "$APP_DIR" add .
if git -C "$APP_DIR" commit -q -m "feat: no spec" >/dev/null 2>&1; then
  fail unborn-head-spec-gate
else
  pass unborn-head-spec-gate
fi

cat >"$TEST_ROOT/scissors.txt" <<'EOF'
feat: try fake exempt in diff
# ------------------------ >8 ------------------------
Spec-Exempt: L1-bug | reason=fake
EOF
if "$PY_CMD" "$APP_DIR/scripts/governance/check-spec-sync.py" --root "$APP_DIR" --staged --message "$TEST_ROOT/scissors.txt" >/dev/null 2>&1; then
  fail scissors-bypass-blocked
else
  pass scissors-bypass-blocked
fi

mkdir -p "$APP_DIR/docs/specs/Core"
printf '# Core\n' >"$APP_DIR/docs/specs/Core/init.md"
git -C "$APP_DIR" add docs/specs/Core/init.md
git -C "$APP_DIR" commit -q -m "feat: bootstrap core" && pass initial-commit-with-spec || fail initial-commit-with-spec

printf 'export const v2 = 2;\n' >>"$APP_DIR/src/app.ts"
git -C "$APP_DIR" add src/app.ts
git -C "$APP_DIR" commit -q -m $'fix: null guard\n\nSpec-Exempt: L1-bug | reason=restore spec' && pass l1-bugfix-spec-exempt || fail l1-bugfix-spec-exempt

printf 'export const t = 1;\n' >"$APP_DIR/src/app.test.ts"
git -C "$APP_DIR" add src/app.test.ts
git -C "$APP_DIR" commit -q -m "test: add unit test" && pass test-file-exempt || fail test-file-exempt

MAIN_BRANCH="$(git -C "$APP_DIR" branch --show-current)"
git -C "$APP_DIR" checkout -q -b feature-doc
printf '# readme\n' >"$APP_DIR/README.md"
git -C "$APP_DIR" add README.md
git -C "$APP_DIR" commit -q -m "docs: readme"

git -C "$APP_DIR" checkout -q "$MAIN_BRANCH"
printf 'export const m = 1;\n' >"$APP_DIR/src/main_only.ts"
git -C "$APP_DIR" add src/main_only.ts
git -C "$APP_DIR" commit -q -m $'fix: main hotfix\n\nSpec-Exempt: L1-bug | reason=hotfix'

if "$PY_CMD" "$APP_DIR/scripts/governance/check-spec-sync.py" --root "$APP_DIR" --range "${MAIN_BRANCH}..feature-doc" >/dev/null; then
  pass diverged-pr-merge-base-range
else
  fail diverged-pr-merge-base-range
fi

cat >"$APP_DIR/docs/todos/001.md" <<'EOF'
# Task
- **Status**: `in-progress`
- [ ] wip
EOF
git -C "$APP_DIR" add docs/todos/001.md
"$PY_CMD" "$APP_DIR/scripts/governance/check-spec-sync.py" --root "$APP_DIR" --staged >/dev/null && pass todo-in-progress-passes || fail todo-in-progress-passes

sed 's/in-progress/ready-to-close/' "$APP_DIR/docs/todos/001.md" >"$APP_DIR/docs/todos/001.tmp"
mv "$APP_DIR/docs/todos/001.tmp" "$APP_DIR/docs/todos/001.md"
git -C "$APP_DIR" add docs/todos/001.md
if "$PY_CMD" "$APP_DIR/scripts/governance/check-spec-sync.py" --root "$APP_DIR" --staged >/dev/null 2>&1; then
  fail todo-ready-to-close-blocks
else
  pass todo-ready-to-close-blocks
fi

# 5. 多端 Monorepo（--apps、根多端路由表、--add-app、重叠校验、按端 Spec 隔离、共享契约、锁文件与 Markdown 排除）
MONO_DIR="$TEST_ROOT/test-project"
if bash "$GOV_SCRIPT" project init --target "$MONO_DIR" --project-name "test-project" \
     --apps "test-project-backend,test-project-client-ios,test-project-admin" >/dev/null &&
   grep -q 'test-project-client-ios/AGENTS.md' "$MONO_DIR/AGENTS.md" &&
   [[ -f "$MONO_DIR/docs/overview.md" && -f "$MONO_DIR/docs/contracts/README.md" &&
      -f "$MONO_DIR/test-project-backend/AGENTS.md" && -f "$MONO_DIR/test-project-client-ios/CLAUDE.md" &&
      -f "$MONO_DIR/test-project-admin/docs/architecture/tech-stack.md" ]]; then
  pass monorepo-init-and-root-routing-table
else
  fail monorepo-init-and-root-routing-table
fi

if bash "$GOV_SCRIPT" project init --target "$MONO_DIR" --add-app "test-project-frontend" --dry-run >/dev/null &&
   [[ ! -e "$MONO_DIR/test-project-frontend" ]] &&
   bash "$GOV_SCRIPT" project init --target "$MONO_DIR" --add-app "test-project-frontend" >/dev/null &&
   [[ -f "$MONO_DIR/test-project-frontend/AGENTS.md" ]] &&
   ! bash "$GOV_SCRIPT" project init --target "$MONO_DIR" --add-app "test-project-backend/sub" >/dev/null 2>&1 &&
   ! bash "$GOV_SCRIPT" project init --target "$MONO_DIR" --add-app "test-project-frontend" >/dev/null 2>&1; then
  pass monorepo-add-app-and-overlap-guards
else
  fail monorepo-add-app-and-overlap-guards
fi

git -C "$MONO_DIR" init -q
git -C "$MONO_DIR" config user.name "Alice Dev"
git -C "$MONO_DIR" config user.email "alice@example.com"
mkdir -p "$MONO_DIR/docs/specs/Core"
printf '# Shared\n' >"$MONO_DIR/docs/specs/Core/init.md"
git -C "$MONO_DIR" add .
git -C "$MONO_DIR" commit -q -m "feat: init monorepo"

# 锁文件与子端 README 不触发 Spec 门禁
printf '{}\n' >"$MONO_DIR/test-project-admin/package-lock.json"
printf '# Admin\n' >"$MONO_DIR/test-project-admin/README.md"
git -C "$MONO_DIR" add test-project-admin/package-lock.json test-project-admin/README.md
"$PY_CMD" "$MONO_DIR/scripts/governance/check-spec-sync.py" --root "$MONO_DIR" --staged >/dev/null && pass monorepo-lockfile-and-readme-excluded || fail monorepo-lockfile-and-readme-excluded
git -C "$MONO_DIR" reset -q HEAD

# 双端同时改代码：仅改 backend 端内 Spec 应拦截 ios；改顶层 docs/contracts/ 放行
mkdir -p "$MONO_DIR/test-project-backend/src" "$MONO_DIR/test-project-client-ios/Sources" "$MONO_DIR/test-project-backend/docs/specs/Order"
printf 'public class Order {}\n' >"$MONO_DIR/test-project-backend/src/Order.java"
printf 'public struct Home {}\n' >"$MONO_DIR/test-project-client-ios/Sources/Home.swift"
printf '# Backend Order\n' >"$MONO_DIR/test-project-backend/docs/specs/Order/o.md"
git -C "$MONO_DIR" add test-project-backend/src/Order.java test-project-client-ios/Sources/Home.swift test-project-backend/docs/specs/Order/o.md
if "$PY_CMD" "$MONO_DIR/scripts/governance/check-spec-sync.py" --root "$MONO_DIR" --staged >/dev/null 2>&1; then
  fail monorepo-per-scope-spec-isolation
else
  printf '{"openapi":"3.1.0"}\n' >"$MONO_DIR/docs/contracts/openapi.json"
  git -C "$MONO_DIR" add docs/contracts/openapi.json
  "$PY_CMD" "$MONO_DIR/scripts/governance/check-spec-sync.py" --root "$MONO_DIR" --staged >/dev/null && pass monorepo-per-scope-spec-isolation-and-shared-contract || fail monorepo-per-scope-spec-isolation-and-shared-contract
fi

if (( failures > 0 )); then
  printf '%d init-project-governance test(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'All init-project-governance tests passed.\n'
