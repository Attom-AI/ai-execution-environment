#!/usr/bin/env bash

set -euo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$RUNTIME_ROOT/platform/repositories/lib.sh"

work_item_dir() {
  printf '%s/workspaces/%s/%s\n' "$RUNTIME_ROOT" "$1" "$2"
}

require_work_item() {
  local directory
  directory="$(work_item_dir "$1" "$2")"
  [[ -f "$directory/meta.json" ]] || die "work item not found: $1/$2"
  printf '%s\n' "$directory"
}

update_runtime_state() {
  local meta="$1"
  local status="$2"
  local worktree="$3"
  local branch="$4"
  local temporary
  temporary="${meta}.tmp"
  jq \
    --arg status "$status" \
    --arg worktree "$worktree" \
    --arg branch "$branch" \
    '.status = $status
     | .runtime.worktree = (if $worktree == "" then null else $worktree end)
     | .runtime.branch = (if $branch == "" then null else $branch end)' \
    "$meta" >"$temporary"
  mv "$temporary" "$meta"
}
