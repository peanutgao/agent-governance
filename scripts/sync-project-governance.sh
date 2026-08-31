#!/usr/bin/env bash
set -euo pipefail

# sync-project-governance.sh
#
# 将 agent-governance 的公共项目快照同步到一个或多个独立项目仓库。
# 只写 AI-GOVERNANCE.md 和 commit 检查脚本，不读取或移动项目源代码。

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_DIR/VERSION"
SNAPSHOT_TEMPLATE="$REPO_DIR/templates/project/AI-GOVERNANCE.md"
CHECKER_TEMPLATE="$REPO_DIR/templates/project/scripts/check-commit-attribution.sh"
TEMP_DIR="$(mktemp -d /tmp/agent-governance-sync.XXXXXX)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

usage() {
  cat >&2 <<'USAGE'
用法:
  sync-project-governance.sh --repo <project-repository> [--repo <project-repository> ...]
USAGE
}

fail() {
  printf 'Project governance sync failed: %s\n' "$1" >&2
  exit 1
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  fail "sha256sum or shasum is required"
}

version="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid governance VERSION: $version"
[[ -f "$SNAPSHOT_TEMPLATE" ]] || fail "missing project snapshot template"
[[ -f "$CHECKER_TEMPLATE" ]] || fail "missing attribution checker template"

repos=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      repos+=("$2")
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

(( ${#repos[@]} > 0 )) || { usage; exit 2; }

rendered_snapshot="$TEMP_DIR/AI-GOVERNANCE.md"
sed "s/__BASELINE_VERSION__/$version/g" "$SNAPSHOT_TEMPLATE" >"$TEMP_DIR/AI-GOVERNANCE-without-hash.md"
snapshot_hash="$(sha256_file "$TEMP_DIR/AI-GOVERNANCE-without-hash.md")"
sed "s/__BASELINE_HASH__/$snapshot_hash/g" "$TEMP_DIR/AI-GOVERNANCE-without-hash.md" >"$rendered_snapshot"

project_roots=()
for requested_repo in "${repos[@]}"; do
  [[ -d "$requested_repo" ]] || fail "project repository does not exist: $requested_repo"
  project_dir="$(cd "$requested_repo" && pwd)"
  project_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$project_root" ]] || fail "not a Git repository: $project_dir"
  [[ "$project_root" != "$REPO_DIR" ]] || fail "agent-governance cannot sync itself"

  for existing_root in "${project_roots[@]}"; do
    [[ "$existing_root" != "$project_root" ]] || fail "duplicate project repository: $project_root"
  done

  for target in "AI-GOVERNANCE.md" "scripts/check-commit-attribution.sh"; do
    if [[ -n "$(git -C "$project_root" status --porcelain -- "$target")" ]]; then
      fail "$project_root/$target has uncommitted changes; refusing to overwrite"
    fi
  done

  if [[ -e "$project_root/scripts" && ! -d "$project_root/scripts" ]]; then
    fail "$project_root/scripts exists but is not a directory"
  fi
  project_roots+=("$project_root")
done

for project_root in "${project_roots[@]}"; do
  mkdir -p "$project_root/scripts"

  snapshot_target="$project_root/AI-GOVERNANCE.md"
  checker_target="$project_root/scripts/check-commit-attribution.sh"

  if [[ -f "$snapshot_target" ]] && cmp -s "$rendered_snapshot" "$snapshot_target"; then
    printf 'UNCHANGED %s\n' "$snapshot_target"
  else
    cp "$rendered_snapshot" "$snapshot_target"
    printf 'UPDATED %s\n' "$snapshot_target"
  fi

  if [[ -f "$checker_target" ]] && cmp -s "$CHECKER_TEMPLATE" "$checker_target"; then
    printf 'UNCHANGED %s\n' "$checker_target"
  else
    cp "$CHECKER_TEMPLATE" "$checker_target"
    chmod +x "$checker_target"
    printf 'UPDATED %s\n' "$checker_target"
  fi
done

printf 'Project governance sync complete: baseline %s (%s).\n' "$version" "$snapshot_hash"
