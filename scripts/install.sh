#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  printf '用法: bash scripts/install.sh\n' >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_command=python3
case "$(uname -s)" in
  MINGW*|MSYS*) python_command=python; export PYTHONUTF8=1 ;;
esac
"$python_command" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else "安装需要 Python 3.9 或更新版本。")'
bash "$script_dir/distribute.sh"
exec "$python_command" "$script_dir/skills.py" sync
