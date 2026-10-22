#!/usr/bin/env bash

set -euo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$RUNTIME_ROOT/platform/repositories/lib.sh"

utc_now() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

work_item_dir() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid workspace id: $1"
  [[ "$2" =~ ^[A-Z][A-Z0-9-]*$ ]] || die "invalid work-item id: $2"
  printf '%s/workspaces/%s/%s\n' "$RUNTIME_ROOT" "$1" "$2"
}

require_work_item() {
  local directory
  directory="$(work_item_dir "$1" "$2")"
  [[ -f "$directory/meta.json" ]] || die "work item not found: $1/$2"
  printf '%s\n' "$directory"
}

record_history() {
  local directory="$1"
  shift
  printf '%s  %s\n' "$(utc_now)" "$*" >>"$directory/history.log"
}

update_runtime_state() {
  local meta="$1"
  local status="$2"
  local worktree="$3"
  local container_id="$4"
  local actor="$5"
  local temporary="${meta}.tmp"
  local timestamp
  timestamp="$(utc_now)"
  jq \
    --arg status "$status" \
    --arg worktree "$worktree" \
    --arg container_id "$container_id" \
    --arg actor "$actor" \
    --arg timestamp "$timestamp" \
    '.runtime.status = $status
     | .runtime.worktree = (if $worktree == "" then null else $worktree end)
     | .runtime.containerId = (if $container_id == "" then null else $container_id end)
     | .resume.lastUpdatedBy = $actor
     | .resume.lastUpdatedAt = $timestamp' \
    "$meta" >"$temporary"
  mv "$temporary" "$meta"
}
