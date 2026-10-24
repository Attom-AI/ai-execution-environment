#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 [status|list]
  $0 resize <pool-size>
  $0 add [count]
  $0 allocate <workspace-id> <work-item-id> [--slot <slot>] [--no-container] [--start-point <ref>]
  $0 release (<slot> | <workspace-id> <work-item-id>) [--remove-worktree]
  $0 recreate (<slot> | <workspace-id> <work-item-id>) [--start-point <ref>]
  $0 cleanup [--dry-run]
EOF
}

resolve_target_meta() {
  local first="$1"
  local second="${2:-}"
  if [[ "$first" =~ ^[1-9][0-9]*$ && -z "$second" ]]; then
    local meta
    meta="$(find_meta_by_slot "$first")" || die "slot $first is not assigned to any work item"
    printf '%s\n' "$meta"
  elif [[ -n "$first" && -n "$second" ]]; then
    local directory
    directory="$(require_work_item "$first" "$second")"
    printf '%s/meta.json\n' "$directory"
  else
    usage
    exit 2
  fi
}

list_label_containers() {
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter "label=ai.execution-environment.runtime" --format '{{.ID}}' 2>/dev/null || true
  fi
}

cmd_status() {
  local size
  size="$(runtime_pool_size)"
  local max_slot="$size"
  local meta
  local s

  while IFS= read -r meta; do
    s="$(jq -r '.runtime.poolSlot // empty' "$meta")"
    if [[ "$s" =~ ^[0-9]+$ ]] && ((s > max_slot)); then
      max_slot="$s"
    fi
  done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null)

  local running_count=0
  local stopped_count=0
  local reserved_count=0
  local free_count=0
  local rows=()
  local known_containers=()
  local slot

  for ((slot = 1; slot <= max_slot; slot++)); do
    local matches=()
    while IFS= read -r meta; do
      s="$(jq -r '.runtime.poolSlot // empty' "$meta")"
      [[ "$s" == "$slot" ]] && matches+=("$meta")
    done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)

    if [[ "${#matches[@]}" -eq 0 ]]; then
      if ((slot <= size)); then
        free_count=$((free_count + 1))
        rows+=("$(printf '%-5s %-18s %-16s %-24s %-14s %s' "$slot" "free" "-" "-" "-" "-")")
      fi
    elif [[ "${#matches[@]}" -gt 1 ]]; then
      rows+=("$(printf '%-5s %-18s %-16s %-24s %-14s %s' "$slot" "conflict" "-" "multiple" "multiple" "-")")
    else
      meta="${matches[0]}"
      local workspace work_item worktree container_id c_status state
      workspace="$(jq -r '.workspace' "$meta")"
      work_item="$(jq -r '.workItem' "$meta")"
      worktree="$(jq -r '.runtime.worktree // "-"' "$meta")"
      container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
      if [[ -n "$container_id" ]]; then
        known_containers+=("$container_id")
        c_status="$(inspect_container_status "$container_id")"
        case "$c_status" in
          running)
            state="running"
            running_count=$((running_count + 1))
            ;;
          missing)
            state="missing-container"
            stopped_count=$((stopped_count + 1))
            ;;
          *)
            state="stopped"
            stopped_count=$((stopped_count + 1))
            ;;
        esac
      else
        state="reserved"
        reserved_count=$((reserved_count + 1))
        container_id="-"
      fi
      if ((slot > size)); then
        state="${state}(over-cap)"
      fi
      rows+=("$(printf '%-5s %-18s %-16s %-24s %-14s %s' "$slot" "$state" "$container_id" "$workspace" "$work_item" "$worktree")")
    fi
  done

  local cid
  while IFS= read -r cid; do
    [[ -n "$cid" ]] || continue
    local is_known=0
    local k
    for k in "${known_containers[@]+"${known_containers[@]}"}"; do
      if [[ "$k" == "$cid"* || "$cid" == "$k"* ]]; then
        is_known=1
        break
      fi
    done
    if [[ "$is_known" -eq 0 ]]; then
      rows+=("$(printf '%-5s %-18s %-16s %-24s %-14s %s' "-" "orphaned-container" "$cid" "-" "-" "-")")
    fi
  done < <(list_label_containers)

  printf 'Pool capacity: %s slots (%s running, %s stopped, %s reserved, %s free)\n' \
    "$size" "$running_count" "$stopped_count" "$reserved_count" "$free_count"
  printf '%-5s %-18s %-16s %-24s %-14s %s\n' SLOT STATE CONTAINER WORKSPACE WORK-ITEM WORKTREE
  local row
  for row in "${rows[@]}"; do
    printf '%s\n' "$row"
  done
}

cmd_resize() {
  [[ "$#" -eq 1 ]] || { usage; exit 2; }
  local new_size="$1"
  set_runtime_pool_size "$new_size"
  printf 'resized runtime pool to %s slots\n' "$new_size"
}

cmd_add() {
  local delta="${1:-1}"
  [[ "$#" -le 1 ]] || { usage; exit 2; }
  [[ "$delta" =~ ^[1-9][0-9]*$ ]] || die "slot increment must be a positive integer: $delta"
  local current new_size
  current="$(runtime_pool_size)"
  new_size=$((current + delta))
  set_runtime_pool_size "$new_size"
  printf 'added %s slot(s); runtime pool size is now %s\n' "$delta" "$new_size"
}

cmd_allocate() {
  [[ "$#" -ge 2 ]] || { usage; exit 2; }
  local workspace="$1"
  local work_item="$2"
  shift 2
  local requested_slot=""
  local no_container=0
  local start_point=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --slot) requested_slot="${2:-}"; shift 2 ;;
      --no-container) no_container=1; shift ;;
      --start-point) start_point="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done

  local directory meta
  directory="$(require_work_item "$workspace" "$work_item")"
  meta="$directory/meta.json"
  if [[ -z "$requested_slot" && "$no_container" -eq 1 ]]; then
    requested_slot="$(claim_pool_slot "$meta")"
  fi

  local args=("$workspace" "$work_item")
  [[ -z "$requested_slot" ]] || args+=(--slot "$requested_slot")
  [[ -z "$start_point" ]] || args+=(--start-point "$start_point")
  [[ "$no_container" -eq 0 ]] || args+=(--no-container)
  "$ROOT/platform/runtime/scripts/start.sh" "${args[@]}"
}

cmd_release() {
  [[ "$#" -ge 1 ]] || { usage; exit 2; }
  local remove_worktree=0
  local positional=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --remove-worktree) remove_worktree=1; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  local meta
  if [[ "${#positional[@]}" -eq 1 ]]; then
    meta="$(resolve_target_meta "${positional[0]}")"
  elif [[ "${#positional[@]}" -eq 2 ]]; then
    meta="$(resolve_target_meta "${positional[0]}" "${positional[1]}")"
  else
    usage
    exit 2
  fi

  local directory workspace work_item worktree container_id pool_slot project_id project repository_path
  directory="$(dirname "$meta")"
  workspace="$(jq -r '.workspace' "$meta")"
  work_item="$(jq -r '.workItem' "$meta")"
  worktree="$(jq -r '.runtime.worktree // empty' "$meta")"
  container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
  pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"

  if [[ "$remove_worktree" -eq 1 && -n "$worktree" && -e "$ROOT/$worktree" ]]; then
    if [[ "$(worktree_git_state "$ROOT/$worktree")" == dirty ]]; then
      die "worktree has uncommitted changes; commit or clean it before releasing with --remove-worktree: $worktree"
    fi
  fi

  if [[ -n "$container_id" ]]; then
    if command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
      docker rm -f "$container_id" >/dev/null
    elif ! command -v docker >/dev/null 2>&1; then
      die "docker is required to remove runtime container $container_id"
    fi
  fi

  local new_worktree="$worktree"
  local new_status="stopped"
  if [[ "$remove_worktree" -eq 1 && -n "$worktree" ]]; then
    if [[ -e "$ROOT/$worktree" ]]; then
      validate_projects
      project_id="$(jq -r '.project' "$meta")"
      project="$(project_by_id "$project_id")" || die "project not found: $project_id"
      repository_path="$(jq -r '.repository.path' <<<"$project")"
      git -C "$ROOT/$repository_path" worktree remove "$ROOT/$worktree"
    fi
    new_worktree=""
    new_status="stopped"
  elif [[ -n "$worktree" && -e "$ROOT/$worktree" ]]; then
    new_status="worktree-ready"
  else
    new_worktree=""
    new_status="stopped"
  fi

  update_runtime_state "$meta" "$new_status" "$new_worktree" "" "" slot-release
  "$ROOT/platform/context/scripts/snapshot.sh" "$workspace" "$work_item" create --reason slot-release >/dev/null 2>&1 || true
  record_history "$directory" "runtime slot released (pool-slot=${pool_slot:-none} container=${container_id:-none} worktree=${new_worktree:-removed})"
  printf 'released slot %s from %s/%s\n' "${pool_slot:-none}" "$workspace" "$work_item"
}

cmd_recreate() {
  [[ "$#" -ge 1 ]] || { usage; exit 2; }
  local start_point=""
  local positional=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --start-point) start_point="${2:-}"; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  local meta
  if [[ "${#positional[@]}" -eq 1 ]]; then
    meta="$(resolve_target_meta "${positional[0]}")"
  elif [[ "${#positional[@]}" -eq 2 ]]; then
    meta="$(resolve_target_meta "${positional[0]}" "${positional[1]}")"
  else
    usage
    exit 2
  fi

  local workspace work_item pool_slot
  workspace="$(jq -r '.workspace' "$meta")"
  work_item="$(jq -r '.workItem' "$meta")"
  pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"

  local args=("$workspace" "$work_item" --recreate-container)
  [[ -z "$pool_slot" ]] || args+=(--slot "$pool_slot")
  [[ -z "$start_point" ]] || args+=(--start-point "$start_point")
  "$ROOT/platform/runtime/scripts/start.sh" "${args[@]}"
}

cmd_cleanup() {
  local dry_run=0
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      *) usage; exit 2 ;;
    esac
  done

  local cleaned=0
  local meta
  local active_containers=()

  while IFS= read -r meta; do
    local directory workspace work_item stage worktree container_id pool_slot c_status
    directory="$(dirname "$meta")"
    workspace="$(jq -r '.workspace' "$meta")"
    work_item="$(jq -r '.workItem' "$meta")"
    stage="$(jq -r '.lifecycleStage' "$meta")"
    worktree="$(jq -r '.runtime.worktree // empty' "$meta")"
    container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
    pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"

    if [[ "$stage" == closed && ( -n "$container_id" || -n "$pool_slot" ) ]]; then
      cleaned=$((cleaned + 1))
      if [[ "$dry_run" -eq 1 ]]; then
        printf '[dry-run] would clear stale slot/container on closed work item %s/%s (slot=%s container=%s)\n' \
          "$workspace" "$work_item" "${pool_slot:-none}" "${container_id:-none}"
      else
        if [[ -n "$container_id" ]] && command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
          docker rm -f "$container_id" >/dev/null
        fi
        update_runtime_state "$meta" stopped "" "" "" slot-cleanup
        record_history "$directory" "cleaned stale slot/container from closed work item"
        printf 'cleaned stale slot/container from closed work item %s/%s\n' "$workspace" "$work_item"
      fi
      continue
    fi

    if [[ -n "$container_id" ]]; then
      c_status="$(inspect_container_status "$container_id")"
      if [[ "$c_status" == missing ]]; then
        cleaned=$((cleaned + 1))
        if [[ "$dry_run" -eq 1 ]]; then
          printf '[dry-run] would clear missing container %s from %s/%s (slot=%s)\n' \
            "$container_id" "$workspace" "$work_item" "${pool_slot:-none}"
        else
          local next_status="stopped"
          [[ -n "$worktree" && -e "$ROOT/$worktree" ]] && next_status="worktree-ready"
          update_runtime_state "$meta" "$next_status" "$worktree" "" "$pool_slot" slot-cleanup
          record_history "$directory" "cleared missing container $container_id (slot=${pool_slot:-none} retained)"
          printf 'cleared missing container %s from %s/%s\n' "$container_id" "$workspace" "$work_item"
        fi
      else
        active_containers+=("$container_id")
      fi
    fi
  done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)

  local cid
  while IFS= read -r cid; do
    [[ -n "$cid" ]] || continue
    local is_active=0
    local k
    for k in "${active_containers[@]+"${active_containers[@]}"}"; do
      if [[ "$k" == "$cid"* || "$cid" == "$k"* ]]; then
        is_active=1
        break
      fi
    done
    if [[ "$is_active" -eq 0 ]]; then
      cleaned=$((cleaned + 1))
      if [[ "$dry_run" -eq 1 ]]; then
        printf '[dry-run] would remove orphaned runtime container %s\n' "$cid"
      else
        docker rm -f "$cid" >/dev/null
        printf 'removed orphaned runtime container %s\n' "$cid"
      fi
    fi
  done < <(list_label_containers)

  local lock_dir="$ROOT/.local/state/runtime/pool.lock"
  if [[ -d "$lock_dir" ]]; then
    cleaned=$((cleaned + 1))
    if [[ "$dry_run" -eq 1 ]]; then
      printf '[dry-run] would remove stale runtime pool lock %s\n' "$lock_dir"
    else
      rmdir "$lock_dir" 2>/dev/null || true
      printf 'removed stale runtime pool lock\n'
    fi
  fi

  if [[ "$cleaned" -eq 0 ]]; then
    printf 'no slot cleanup needed\n'
  fi
}

subcommand="${1:-status}"
[[ "$#" -eq 0 ]] || shift

case "$subcommand" in
  status|list) cmd_status "$@" ;;
  resize) cmd_resize "$@" ;;
  add) cmd_add "$@" ;;
  allocate) cmd_allocate "$@" ;;
  release) cmd_release "$@" ;;
  recreate) cmd_recreate "$@" ;;
  cleanup) cmd_cleanup "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
