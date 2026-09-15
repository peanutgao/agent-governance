#!/usr/bin/env bash
set -euo pipefail

# 治理仓全部测试的唯一入口。CI 与本地都用它，避免「加了一个套件但没人跑」。
# 注意：scripts/distribute.sh 的门禁刻意不调用本脚本（会递归），它自己维护
# 非递归的套件清单。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUITES=(
  tests/check-commit-attribution.sh
  tests/check-hook.sh
  tests/check-version-bump.sh
  tests/distribute.sh
)

failures=0

for suite in "${SUITES[@]}"; do
  printf '== %s ==\n' "$suite"
  if ! bash "$ROOT_DIR/$suite"; then
    failures=$((failures + 1))
  fi
  printf '\n'
done

if (( failures > 0 )); then
  printf '%d test suite(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'All %d test suites passed.\n' "${#SUITES[@]}"
