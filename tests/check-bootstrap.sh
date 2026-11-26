#!/usr/bin/env bash
# 引导脚本语法、Python 编译、PowerShell ASCII 约束与规则仓库卫生回归测试。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

py_cmd=python3
case "$(uname -s)" in
  MINGW*|MSYS*) py_cmd=python; export PYTHONUTF8=1 ;;
esac

# 1. 全部 Shell 脚本与钩子语法检查。
syntax_ok=1
for file in "$ROOT_DIR"/scripts/gov "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/scripts/internal/*.sh "$ROOT_DIR"/.githooks/* "$ROOT_DIR"/tests/*.sh; do
  [[ -f "$file" ]] || continue
  if ! bash -n "$file" 2>&1; then
    printf '  syntax error: %s\n' "$file" >&2
    syntax_ok=0
  fi
done
[[ "$syntax_ok" == 1 ]] && pass all-shell-scripts-syntax || fail all-shell-scripts-syntax

# 2. Python 脚本语法编译检查（无副作用不落 __pycache__，不依赖调用方 CWD）。
if "$py_cmd" -B - "$ROOT_DIR" <<'PY'
import ast, pathlib, sys
root = pathlib.Path(sys.argv[1])
for rel in ("scripts/internal/skills.py", "scripts/internal/skills_store.py", "scripts/internal/init_project_governance.py", "tests/skills.py"):
    path = root / rel
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
then
  pass python-scripts-parse
else
  fail python-scripts-parse
fi

# 3. bootstrap.ps1 必须纯 ASCII（PowerShell 5.1 无 BOM UTF-8 安全）且含本地仓库根校验。
if "$py_cmd" -B - "$ROOT_DIR/scripts/bootstrap.ps1" <<'PY'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
non_ascii = [b for b in raw if b >= 0x80]
if non_ascii:
    raise SystemExit(f"bootstrap.ps1 contains {len(non_ascii)} non-ASCII byte(s)")
text = raw.decode("ascii")
for token in ("Resolve-LocalBootstrapScript", "Test-RuntimeReady", "VERSION", "$govScript", "'gov'"):
    if token not in text:
        raise SystemExit(f"bootstrap.ps1 missing required guard: {token}")
PY
then
  pass bootstrap-ps1-ascii-and-guards
else
  fail bootstrap-ps1-ascii-and-guards
fi

# 4. gov install / bootstrap.sh 参数错误必须失败关闭。
set +e
bash "$ROOT_DIR/scripts/gov" install --unknown >/dev/null 2>&1
install_bad_code=$?
bash "$ROOT_DIR/scripts/bootstrap.sh" --unknown >/dev/null 2>&1
bootstrap_bad_code=$?
set -e
[[ "$install_bad_code" -eq 2 ]] && pass install-rejects-extra-args || fail install-rejects-extra-args
[[ "$bootstrap_bad_code" -eq 1 ]] && pass bootstrap-rejects-extra-args || fail bootstrap-rejects-extra-args

# 5. 规则正文字节预算与关键文档卫生不变量（防陈旧引用回流与隐私入仓）。
agents_bytes="$(wc -c <"$ROOT_DIR/global/AGENTS.md" | tr -d '[:space:]')"
tpl_bytes="$(wc -c <"$ROOT_DIR/templates/project/AI-GOVERNANCE.md" | tr -d '[:space:]')"
(( agents_bytes <= 24000 )) && pass global-agents-within-24000-bytes || fail "global-agents-within-24000-bytes ($agents_bytes)"
(( tpl_bytes <= 23500 )) && pass template-within-23500-bytes || fail "template-within-23500-bytes ($tpl_bytes)"

if grep -rnE 'global/ai-change-implementation-prompt\.md|global/git-hooks|~/\.codex/git-hooks|hengqin|三仓|grill-with-docs|fill_fillable_fields|PDF skill' \
  "$ROOT_DIR/AGENTS.md" "$ROOT_DIR/README.md" "$ROOT_DIR/onboarding.md" \
  "$ROOT_DIR/global" "$ROOT_DIR/scripts" "$ROOT_DIR/skills" "$ROOT_DIR/templates" >/dev/null 2>&1; then
  fail no-stale-references-or-leaks
else
  pass no-stale-references-or-leaks
fi

if [[ -n "$(git -C "$ROOT_DIR" ls-files .workbuddy-ai)" ]]; then
  fail personal-memory-not-tracked
else
  pass personal-memory-not-tracked
fi

if (( failures > 0 )); then
  printf '%d bootstrap/hygiene check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'All bootstrap and hygiene checks passed.\n'
