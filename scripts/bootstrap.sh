#!/usr/bin/env bash
set -euo pipefail

repo_url=https://github.com/peanutgao/agent-governance.git
state_dir="$HOME/.local/share/agent-governance/bootstrap"
python_command=python3
runtime_stage=

fail() {
  printf '部署失败: %s\n' "$*" >&2
  exit 1
}

runtime_ready() {
  local git_path
  git_path="$(command -v git)" || return 1
  if [[ "$(uname -s)" == Darwin && "$git_path" == /usr/bin/git ]]; then
    xcode-select -p >/dev/null 2>&1 || return 1
  fi
  git --version >/dev/null 2>&1 &&
    "$python_command" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1 &&
    node -e 'let [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || major === 22 && minor >= 20 ? 0 : 1)' >/dev/null 2>&1 &&
    npm --version >/dev/null 2>&1
}

install_runtime() {
  local target checksum hash_output
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) target=osx-arm64; checksum=500f5074feb8d02c4296ef9921c3650ed2874171805a9fbb8fbb53896433646b ;;
    Darwin:x86_64) target=osx-64; checksum=0426ecdc41636d369f57b8fe6acbf4385a69eca45b56d9ee7d3a840a9965d44f ;;
    Linux:aarch64) target=linux-aarch64; checksum=e705ffeed90ce0659eb546e4b1e1028c9eaf0bc9cc854867b19ac5ce0ba5852f ;;
    Linux:x86_64) target=linux-64; checksum=8761c382127e6363bd9e0a2451aa3ef90d071a79133f736e2f759a3bf13040dd ;;
    *) fail '无法自动安装此架构的 Git、Python 和 Node.js。' ;;
  esac

  runtime_stage="$(mktemp -d "$state_dir/runtime.XXXXXX")"
  local archive="$runtime_stage/micromamba.tar.bz2"
  printf '正在准备 Git、Python 和 Node.js/npm…\n'
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    "https://conda.anaconda.org/conda-forge/$target/micromamba-2.9.0-0.tar.bz2" -o "$archive"
  if command -v sha256sum >/dev/null; then
    hash_output="$(sha256sum < "$archive")"
  else
    hash_output="$(shasum -a 256 < "$archive")"
  fi
  [[ "${hash_output%% *}" == "$checksum" ]] || fail '运行时安装包摘要不匹配。'
  tar -xjf "$archive" -C "$runtime_stage" bin/micromamba
  MAMBA_ROOT_PREFIX="$runtime_stage/cache" "$runtime_stage/bin/micromamba" --no-rc create --yes \
    --no-shortcuts --override-channels --channel https://conda.anaconda.org/conda-forge \
    --prefix "$runtime_stage/env" git 'python=3.12' 'nodejs=24'
  export PATH="$runtime_stage/env/bin:$PATH"
  runtime_ready || fail '新建运行时无法运行。'
  ln -sfn "$runtime_stage/env" "$state_dir/runtime"
  runtime_stage=
}

cleanup() {
  [[ -z "$runtime_stage" ]] || rm -rf -- "$runtime_stage"
  rmdir "$state_dir/.lock" 2>/dev/null || true
}

main() {
  [[ $# == 0 ]] || fail '用法: bash scripts/bootstrap.sh'
  case "$(uname -s)" in
    Darwin|Linux) ;;
    MINGW*|MSYS*)
      python_command=python
      state_dir="$(cygpath -u "$USERPROFILE")/.local/share/agent-governance/bootstrap"
      ;;
    *) fail '此系统请使用对应的新设备部署入口。' ;;
  esac
  command -v curl >/dev/null || fail '需要 curl。'
  local orig_umask
  orig_umask="$(umask)"
  umask 077
  mkdir -p "$state_dir"
  mkdir "$state_dir/.lock" || fail "已有部署在运行，或上次未正常退出: $state_dir/.lock"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! runtime_ready; then
    [[ "$python_command" != python ]] || fail "请使用 PowerShell 入口准备 Windows 运行时。"
    if [[ -d "$state_dir/runtime/bin" ]]; then
      export PATH="$state_dir/runtime/bin:$PATH"
      runtime_ready || fail "已保存的运行时不可用: $state_dir/runtime"
    else
      install_runtime
    fi
  fi

  # The public remote needs no saved credentials.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_CONFIG_PARAMETERS
  export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=

  local checkout="$state_dir/repo"
  if [[ -e "$checkout" || -L "$checkout" ]]; then
    [[ ! -L "$checkout" && -d "$checkout/.git" ]] || fail "部署目录已被占用: $checkout"
    [[ "$(git -C "$checkout" remote get-url origin)" == "$repo_url" ]] || fail "部署目录的 origin 不匹配: $checkout"
    [[ "$(git -C "$checkout" symbolic-ref --quiet --short HEAD)" == main ]] || fail "部署目录需要处于 main 分支: $checkout"
    local changes
    changes="$(git -C "$checkout" status --porcelain)"
    [[ -z "$changes" ]] || fail "部署目录有本地改动: $checkout"
    git -C "$checkout" -c core.hooksPath=/dev/null pull --ff-only origin main
  else
    git -c core.hooksPath=/dev/null clone --branch main --config core.autocrlf=false "$repo_url" "$checkout"
  fi
  local current published
  current="$(git -C "$checkout" rev-parse HEAD)"
  published="$(git -C "$checkout" rev-parse refs/remotes/origin/main)"
  [[ "$current" == "$published" ]] || fail "部署目录与 origin/main 不一致: $checkout"

  # 恢复调用方原有 umask，避免把 077 权限泄露给下游分发的共享入口（如 OrbStack work/CLAUDE.md）。
  umask "$orig_umask"
  bash "$checkout/scripts/gov" install
}

main "$@"
