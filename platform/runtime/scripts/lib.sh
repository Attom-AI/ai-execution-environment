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
  local requested_slot="${2:-}"
  local current_slot
  local size
  local slot
  local meta
  local allocated
  current_slot="$(jq -r '.runtime.poolSlot // empty' "$current_meta")"
  size="$(runtime_pool_size)"

  if [[ -n "$requested_slot" ]]; then
    [[ "$requested_slot" =~ ^[1-9][0-9]*$ && "$requested_slot" -le "$size" ]] \
      || die "requested runtime pool slot $requested_slot is out of range (1..$size)"
    while IFS= read -r meta; do
      [[ "$meta" == "$current_meta" ]] && continue
      allocated="$(jq -r '.runtime.poolSlot // empty' "$meta")"
      if [[ "$allocated" == "$requested_slot" ]]; then
        die "runtime pool slot $requested_slot is already assigned to $(jq -r '"\(.workspace)/\(.workItem)"' "$meta")"
      fi
    done < <(find "$RUNTIME_ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null)
    printf '%s\n' "$requested_slot"
    return 0
  fi

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

  die "runtime pool is full ($size containers); stop does not free a slot, close or release a work item first"
}

set_runtime_pool_size() {
  local new_size="$1"
  [[ "$new_size" =~ ^[1-9][0-9]*$ ]] || die "pool size must be a positive integer: $new_size"
  local meta
  local slot
  while IFS= read -r meta; do
    slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
    if [[ -n "$slot" && "$slot" =~ ^[0-9]+$ ]] && ((slot > new_size)); then
      die "cannot shrink pool size to $new_size: slot $slot is allocated to $(jq -r '"\(.workspace)/\(.workItem)"' "$meta")"
    fi
  done < <(find "$RUNTIME_ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null)

  local env_file="$RUNTIME_ROOT/.env"
  local temporary="${env_file}.tmp"
  if [[ ! -f "$env_file" && -f "$RUNTIME_ROOT/platform/install/templates/.env.example" ]]; then
    cp "$RUNTIME_ROOT/platform/install/templates/.env.example" "$env_file"
  fi
  if [[ -f "$env_file" ]] && grep -Eq '^RUNTIME_POOL_SIZE=' "$env_file"; then
    sed -E "s/^RUNTIME_POOL_SIZE=.*/RUNTIME_POOL_SIZE=$new_size/" "$env_file" >"$temporary"
    mv "$temporary" "$env_file"
  else
    printf 'RUNTIME_POOL_SIZE=%s\n' "$new_size" >>"$env_file"
  fi
}

inspect_container_status() {
  local container_id="${1:-}"
  if [[ -z "$container_id" ]]; then
    printf 'none\n'
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
    docker inspect -f '{{.State.Status}}' "$container_id"
  else
    printf 'missing\n'
  fi
}

worktree_git_state() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'missing\n'
    return 0
  fi
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'invalid\n'
    return 0
  fi
  if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
    printf 'dirty\n'
  else
    printf 'clean\n'
  fi
}

find_meta_by_slot() {
  local target_slot="$1"
  local found_meta=""
  local meta
  local slot
  while IFS= read -r meta; do
    slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
    if [[ "$slot" == "$target_slot" ]]; then
      [[ -z "$found_meta" ]] || die "runtime pool slot $target_slot is assigned to multiple work items"
      found_meta="$meta"
    fi
  done < <(find "$RUNTIME_ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)
  [[ -n "$found_meta" ]] || return 1
  printf '%s\n' "$found_meta"
}
