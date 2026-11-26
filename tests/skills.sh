#!/usr/bin/env bash
set -euo pipefail
py_cmd=python3
case "$(uname -s)" in
  MINGW*|MSYS*) py_cmd=python; export PYTHONUTF8=1 ;;
esac
PYTHONDONTWRITEBYTECODE=1 exec "$py_cmd" "$(dirname "${BASH_SOURCE[0]}")/skills.py"
