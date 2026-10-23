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
  local pool_slot="$5"
  local actor="$6"
  local temporary="${meta}.tmp"
  local timestamp
  timestamp="$(utc_now)"
  jq \
    --arg status "$status" \
    --arg worktree "$worktree" \
    --arg container_id "$container_id" \
    --arg pool_slot "$pool_slot" \
    --arg actor "$actor" \
    --arg timestamp "$timestamp" \
    '.runtime.status = $status
     | .runtime.worktree = (if $worktree == "" then null else $worktree end)
     | .runtime.containerId = (if $container_id == "" then null else $container_id end)
     | .runtime.poolSlot = (if $pool_slot == "" then null else ($pool_slot | tonumber) end)
     | .resume.lastUpdatedBy = $actor
     | .resume.lastUpdatedAt = $timestamp' \
    "$meta" >"$temporary"
  mv "$temporary" "$meta"
}

runtime_pool_size() {
  local size="${RUNTIME_POOL_SIZE:-}"
  if [[ -z "$size" && -f "$RUNTIME_ROOT/.env" ]]; then
    size="$(sed -nE 's/^RUNTIME_POOL_SIZE=([0-9]+)$/\1/p' "$RUNTIME_ROOT/.env" | tail -n 1)"
  fi
  size="${size:-5}"
  [[ "$size" =~ ^[1-9][0-9]*$ ]] || die "RUNTIME_POOL_SIZE must be a positive integer"
  printf '%s\n' "$size"
}

acquire_pool_lock() {
  local lock_root="$RUNTIME_ROOT/.local/state/runtime"
  local lock="$lock_root/pool.lock"
  mkdir -p "$lock_root"
  for _ in {1..50}; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s\n' "$lock"
      return 0
    fi
    sleep 0.1
  done
  die "runtime pool is busy; retry after the current start operation finishes"
}

claim_pool_slot() {
  local current_meta="$1"
  local current_slot
  local size
  local slot
  local meta
  local allocated
  current_slot="$(jq -r '.runtime.poolSlot // empty' "$current_meta")"
  size="$(runtime_pool_size)"

  if [[ -n "$current_slot" ]]; then
    [[ "$current_slot" =~ ^[1-9][0-9]*$ && "$current_slot" -le "$size" ]] \
      || die "work item has invalid runtime pool slot: $current_slot"
    while IFS= read -r meta; do
      [[ "$meta" == "$current_meta" ]] && continue
      allocated="$(jq -r '.runtime.poolSlot // empty' "$meta")"
      [[ "$allocated" != "$current_slot" ]] \
        || die "runtime pool slot $current_slot is assigned to multiple work items"
    done < <(find "$RUNTIME_ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null)
    printf '%s\n' "$current_slot"
    return 0
  fi

  for ((slot = 1; slot <= size; slot++)); do
    allocated=0
    while IFS= read -r meta; do
      [[ "$(jq -r '.runtime.poolSlot // empty' "$meta")" == "$slot" ]] && allocated=1
    done < <(find "$RUNTIME_ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null)
    if [[ "$allocated" -eq 0 ]]; then
      printf '%s\n' "$slot"
      return 0
    fi
  done

  die "runtime pool is full ($size containers); stop does not free a slot, close a work item first"
}
