#!/usr/bin/env bash
# sync-project-governance.sh — 从模板生成项目仓库的 AI-GOVERNANCE.md 快照
#
# 用法:
#   bash scripts/gov project sync --root <workspace-root> [--repos <a,b>] [--check]
#
# 环境变量:
#   PROJECT_GOVERNANCE_ROOT   等价于 --root
#   PROJECT_GOVERNANCE_REPOS  等价于 --repos（逗号分隔；默认自动发现候选子目录）
#
# 行为:
#   1. 从 templates/project/AI-GOVERNANCE.md 渲染 baseline-version
#   2. 按校验方案计算 baseline-content-sha256（header 的 hash 字段先还原为占位符）
#   3. 写入各目标仓 AI-GOVERNANCE.md；--check 只比较，不写入，不一致时退出 1
#
# 该脚本只改由治理仓生成的快照，不改各仓 AGENTS.md、specs 或业务代码。
set -euo pipefail

_self="${BASH_SOURCE[0]:-}"
[[ -f "$_self" ]] || _self="$0"
REPO_DIR="$(cd "$(dirname "$_self")/../.." && pwd)"
TEMPLATE="$REPO_DIR/templates/project/AI-GOVERNANCE.md"
VERSION_FILE="$REPO_DIR/VERSION"
TARGET_ROOT="${PROJECT_GOVERNANCE_ROOT:-}"
# 目标仓库默认由 --root 目录下「含 .git、AI-GOVERNANCE.md、AGENTS.md 或 CLAUDE.md」的子目录自动发现。
# 可用 --repos 或 PROJECT_GOVERNANCE_REPOS（逗号分隔）显式指定，避免把具体项目写进治理仓。
REPOS=()
REPOS_EXPLICIT=0

# 计算哈希时把 header 的 hash 字段还原为这个固定占位符。它是本脚本与
# templates/project/AI-GOVERNANCE.md 正文（第 9 行）共同约定的常量，改一处必须改另一处；
# tests/sync-project-governance.sh 会核对渲染结果。
PLACEHOLDER="416fd18874c6a253af427226a890c03d0b35da8c2d33ceaec46be376de67ef1d"

mode="write"

usage() {
  cat >&2 <<'USAGE'
用法:
  bash scripts/gov project sync --root <path>                  # 生成/更新目标仓快照
  bash scripts/gov project sync --check --root <path>          # 只校验，不写入
  bash scripts/gov project sync --root <path> --repos <a,b>    # 显式指定仓库名（默认自动发现）

环境变量:
  PROJECT_GOVERNANCE_ROOT                     # 等价于 --root
  PROJECT_GOVERNANCE_REPOS                    # 等价于 --repos
USAGE
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  elif command -v python >/dev/null 2>&1; then
    python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  else
    printf '错误: 缺少 SHA-256 计算工具（需要 sha256sum、shasum 或 python）。\n' >&2
    return 1
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --root)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      TARGET_ROOT="$2"
      shift 2
      ;;
    --repos)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      IFS=',' read -r -a REPOS <<<"$2"
      REPOS_EXPLICIT=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$TARGET_ROOT" ]]; then
  printf '错误: 必须通过 --root 或 PROJECT_GOVERNANCE_ROOT 指定目标项目根目录。\n' >&2
  usage
  exit 2
fi
[[ -f "$TEMPLATE" ]] || { printf '错误: 缺少模板 %s\n' "$TEMPLATE" >&2; exit 1; }
[[ -f "$VERSION_FILE" ]] || { printf '错误: 缺少 VERSION %s\n' "$VERSION_FILE" >&2; exit 1; }
[[ -d "$TARGET_ROOT" ]] || { printf '错误: 目标根目录不存在 %s\n' "$TARGET_ROOT" >&2; exit 1; }
TARGET_ROOT="$(cd -P "$TARGET_ROOT" && pwd)"

# 未显式指定仓库时，从目标根目录下自动发现候选仓库。
# 判据是「已有快照、或是 Git 仓、或已有项目级 AI 约束入口」——三者覆盖续同步、
# 首次同步和已接入但还没快照的项目，同时不会把无关目录意外纳管。
if [[ "$REPOS_EXPLICIT" == 0 ]]; then
  if [[ -n "${PROJECT_GOVERNANCE_REPOS:-}" ]]; then
    IFS=',' read -r -a REPOS <<<"$PROJECT_GOVERNANCE_REPOS"
  else
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      REPOS+=("$candidate")
    done < <(
      find "$TARGET_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
        while IFS= read -r dir; do
          [[ "$dir" -ef "$REPO_DIR" ]] && continue
          if [[ -e "$dir/.git" || -f "$dir/AI-GOVERNANCE.md" ||
            -f "$dir/AGENTS.md" || -f "$dir/CLAUDE.md" ]]; then
            basename "$dir"
          fi
        done | LC_ALL=C sort
    )
  fi
fi

# 仅裁剪首尾空白（保留目录名内部空格），拒绝带路径分隔符的名字，避免 --repos 越界写入。
normalized=()
if (( ${#REPOS[@]} > 0 )); then
  for repo in "${REPOS[@]}"; do
    repo="${repo#"${repo%%[![:space:]]*}"}"
    repo="${repo%"${repo##*[![:space:]]}"}"
    [[ -n "$repo" ]] || continue
    if [[ "$repo" == */* || "$repo" == "." || "$repo" == ".." ]]; then
      printf '错误: 仓库名不能包含路径分隔符: %s\n' "$repo" >&2
      exit 1
    fi
    normalized+=("$repo")
  done
fi
if (( ${#normalized[@]} == 0 )); then
  printf '错误: 在 %s 下没有发现候选仓库（需含 .git、AI-GOVERNANCE.md、AGENTS.md 或 CLAUDE.md）；用 --repos 显式指定。\n' "$TARGET_ROOT" >&2
  exit 1
fi
REPOS=("${normalized[@]}")

real_repositories=0

# 判断一个已存在的快照是不是「本脚本上次生成、但还没被提交」的产物。
# 判据是它自我声明的 baseline-content-sha256 与自身内容一致（把 hash 字段还原为
# 固定占位符后重算）。自洽说明它就是脚本写的，没有夹带人工改动，可以安全覆盖；
# 不自洽说明被人改过，必须停下来让人处理。
snapshot_is_generated() {
  local file="$1"
  local stated actual
  [[ -f "$file" ]] || return 1
  stated="$(awk '/^> baseline-content-sha256: /{print $3; exit}' "$file" | tr -d '\r')"
  [[ -n "$stated" ]] || return 1
  actual="$(
    sed "s/^> baseline-content-sha256: .*/> baseline-content-sha256: $PLACEHOLDER/" "$file" |
      sha256_stdin
  )"
  [[ "$stated" == "$actual" ]]
}

for repo in "${REPOS[@]}"; do
  repo_path="$TARGET_ROOT/$repo"
  dest="$repo_path/AI-GOVERNANCE.md"
  if [[ "$repo_path" -ef "$REPO_DIR" ]]; then
    printf '错误: 禁止把项目治理快照写入治理仓自身: %s\n' "$repo_path" >&2
    exit 1
  fi
  if [[ -L "$repo_path" || ! -d "$repo_path" || -L "$dest" || ( -e "$dest" && ! -f "$dest" ) ]]; then
    printf '错误: 目标仓库或快照类型不安全: %s\n' "$dest" >&2
    exit 1
  fi
  if [[ "$mode" == write ]] &&
    { [[ -e "$repo_path/.git" || -L "$repo_path/.git" ]] ||
      git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; }; then
    real_repositories=1
    project_status="$(git -C "$repo_path" status --porcelain --untracked-files=all -- AI-GOVERNANCE.md)"
    if [[ -n "$project_status" ]]; then
      # 未提交的快照若是自洽的脚本产物（上次同步写了但没提交），可以覆盖；
      # 否则是人工改动，拒绝覆盖。
      if ! snapshot_is_generated "$dest"; then
        printf '错误: 快照有未提交的人工改动，拒绝覆盖: %s\n' "$dest" >&2
        printf '      若确认要丢弃本地改动，先 git checkout -- %s\n' "$dest" >&2
        exit 1
      fi
    elif [[ -f "$dest" ]] && ! git -C "$repo_path" ls-files --error-unmatch -- AI-GOVERNANCE.md >/dev/null 2>&1; then
      printf '错误: 快照未被 Git 跟踪，拒绝覆盖: %s\n' "$dest" >&2
      exit 1
    fi
  fi
done

if [[ "$real_repositories" == 1 ]]; then
  release_commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
  bash "$REPO_DIR/scripts/internal/check-version-bump.sh"
  if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
    if ! git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null; then
      printf '错误: 无法 fetch origin，拒绝同步可能过时的治理基线。\n' >&2
      exit 1
    fi
  fi
  release_ref="$(git -C "$REPO_DIR" symbolic-ref --quiet refs/remotes/origin/HEAD || true)"
  release_ref="${release_ref:-refs/remotes/origin/main}"
  if ! git -C "$REPO_DIR" merge-base --is-ancestor "$release_commit" "$release_ref" 2>/dev/null; then
    printf '错误: 当前治理提交尚未进入已获取的 origin 默认分支，拒绝同步项目。\n' >&2
    exit 1
  fi
  behind="$(git -C "$REPO_DIR" rev-list --count "$release_commit..$release_ref")"
  if (( behind > 0 )); then
    printf '错误: 本地治理仓落后 %s %d 个提交，会同步旧版快照。先 git pull。\n' "$release_ref" "$behind" >&2
    exit 1
  fi
fi

tmp_base="${TMPDIR:-/tmp}"
tmp_base="${tmp_base%/}"
tmp_dir="$(mktemp -d "$tmp_base/agent-governance-sync.XXXXXX")"
staged_file=
cleanup() {
  [[ -z "$staged_file" ]] || rm -f "$staged_file"
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ "$real_repositories" == 1 ]]; then
  git -C "$REPO_DIR" show "$release_commit:VERSION" >"$tmp_dir/VERSION"
  version_source="$tmp_dir/VERSION"
else
  version_source="$VERSION_FILE"
fi
version="$(sed -n '1p' "$version_source")"
if [[ "$(awk 'END { print NR }' "$version_source")" != 1 ||
  ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf '错误: VERSION 必须只包含一行严格的 SemVer。\n' >&2
  exit 1
fi

# 先把版本号写进 header 与边界标记；hash 字段暂时保留占位符。
if [[ "$real_repositories" == 1 ]]; then
  git -C "$REPO_DIR" show "$release_commit:templates/project/AI-GOVERNANCE.md" >"$tmp_dir/template.md"
  TEMPLATE="$tmp_dir/template.md"
fi
sed "s/__BASELINE_VERSION__/$version/g" "$TEMPLATE" >"$tmp_dir/rendered.md"

# 计算哈希时，header 的 hash 字段必须还原为固定占位符（与 check 脚本同一方案）。
sed "s/^> baseline-content-sha256: .*/> baseline-content-sha256: $PLACEHOLDER/" \
  "$tmp_dir/rendered.md" >"$tmp_dir/hash-input.md"
hash="$(sha256_stdin <"$tmp_dir/hash-input.md")"

# 只替换 header 的 hash 字段；正文里解释哈希方案的那一行保持占位符原文。
awk -v hash="$hash" '
  /^> baseline-content-sha256: / {
    print "> baseline-content-sha256: " hash
    next
  }
  { print }
' "$tmp_dir/rendered.md" >"$tmp_dir/final.md"

# 检查渲染结果里没有残留占位符（版本/哈希都替换完毕）。
if grep -q '__BASELINE_' "$tmp_dir/final.md"; then
  printf '错误: 渲染结果仍有未替换的占位符:\n' >&2
  grep -n '__BASELINE_' "$tmp_dir/final.md" >&2 || true
  exit 1
fi

mismatch=0
for repo in "${REPOS[@]}"; do
  dest="$TARGET_ROOT/$repo/AI-GOVERNANCE.md"
  if [[ "$mode" == "check" ]]; then
    if [[ ! -f "$dest" ]]; then
      printf '不一致: %s 不存在\n' "$dest" >&2
      mismatch=1
    elif ! cmp -s "$tmp_dir/final.md" "$dest"; then
      printf '不一致: %s 与模板 %s 生成结果不同\n' "$dest" "$version" >&2
      mismatch=1
    else
      printf '✓ %s\n' "$dest"
    fi
  elif ! cmp -s "$tmp_dir/final.md" "$dest"; then
    # 写前再校验一次：仍然只允许覆盖「自洽的脚本产物」。前置循环已经放行过一次，
    # 这里防的是两个循环之间被人改动，而不是重复拒绝自己的产物。
    if [[ "$real_repositories" == 1 ]] && git -C "$TARGET_ROOT/$repo" rev-parse --git-dir >/dev/null 2>&1; then
      project_status="$(git -C "$TARGET_ROOT/$repo" status --porcelain --untracked-files=all -- AI-GOVERNANCE.md)"
      if [[ -n "$project_status" ]] && ! snapshot_is_generated "$dest"; then
        printf '错误: 快照在同步期间被人工修改: %s\n' "$dest" >&2
        exit 1
      fi
    fi
    staged_file="$(mktemp "$TARGET_ROOT/$repo/.governance.XXXXXX")"
    cp -p "$tmp_dir/final.md" "$staged_file"
    if [[ -L "$TARGET_ROOT/$repo" || -L "$dest" || ( -e "$dest" && ! -f "$dest" ) ]]; then
      printf '错误: 快照路径在同步期间变化: %s\n' "$dest" >&2
      exit 1
    fi
    mv -f "$staged_file" "$dest"
    staged_file=
    printf '已更新: %s\n' "$dest"
  fi
done

if [[ "$mode" == "check" ]]; then
  if (( mismatch > 0 )); then
    printf '==> 项目治理快照校验未通过；运行 bash scripts/gov project sync 重新生成。\n' >&2
    exit 1
  fi
  printf '==> 项目治理快照与模板一致 (baseline-version=%s)\n' "$version"
else
  printf '==> 项目治理快照已更新 (baseline-version=%s)\n' "$version"
fi
