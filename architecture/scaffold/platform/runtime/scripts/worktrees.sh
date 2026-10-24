#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 [list] [--active | --inactive | --orphaned | --dirty]
  $0 inspect (<worktree-name> | <workspace-id>/<work-item-id> | <workspace-id> <work-item-id>)
  $0 repair
  $0 cleanup [--inactive] [--dry-run]
EOF
}

derive_worktree_rel() {
  local workspace="$1"
  local work_item="$2"
  local wt_id
  wt_id="$(printf '%s-%s' "$workspace" "$work_item" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
  printf 'worktrees/%s\n' "${wt_id%-}"
}

find_meta_for_worktree() {
  local wt_rel="$1"
  local meta
  local recorded
  local ws
  local wi
  local derived
  while IFS= read -r meta; do
    recorded="$(jq -r '.runtime.worktree // empty' "$meta")"
    ws="$(jq -r '.workspace' "$meta")"
    wi="$(jq -r '.workItem' "$meta")"
    derived="$(derive_worktree_rel "$ws" "$wi")"
    if [[ "$recorded" == "$wt_rel" || "$derived" == "$wt_rel" ]]; then
      printf '%s\n' "$meta"
      return 0
    fi
  done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)
  return 1
}

classify_worktree() {
  local wt_rel="$1"
  local meta="${2:-}"
  local abs_path=""
  abs_path="$(resolve_safe_worktree_abspath "$wt_rel" || true)"
  if [[ -z "$abs_path" ]]; then
    printf 'invalid\n'
    return 0
  fi

  if [[ -z "$meta" ]]; then
    printf 'orphaned\n'
    return 0
  fi

  local stage runtime_status recorded
  stage="$(jq -r '.lifecycleStage' "$meta")"
  runtime_status="$(jq -r '.runtime.status // "stopped"' "$meta")"
  recorded="$(jq -r '.runtime.worktree // empty' "$meta")"

  if [[ "$stage" == closed ]]; then
    printf 'orphaned\n'
    return 0
  fi

  if [[ ! -e "$abs_path" ]]; then
    if [[ -n "$recorded" ]]; then
      printf 'missing\n'
    else
      printf 'inactive\n'
    fi
    return 0
  fi

  case "$runtime_status" in
    running|worktree-ready)
      printf 'active\n'
      ;;
    *)
      printf 'inactive\n'
      ;;
  esac
}

collect_worktree_relpaths() {
  local paths=()
  local dir
  local meta
  local wt

  if [[ -d "$ROOT/worktrees" ]]; then
    while IFS= read -r dir; do
      paths+=("worktrees/$(basename "$dir")")
    done < <(find "$ROOT/worktrees" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)
  fi

  while IFS= read -r meta; do
    wt="$(jq -r '.runtime.worktree // empty' "$meta")"
    [[ -n "$wt" ]] && paths+=("$wt")
  done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)

  if [[ "${#paths[@]}" -gt 0 ]]; then
    printf '%s\n' "${paths[@]}" | LC_ALL=C sort -u
  fi
}

is_configured_repo_root() {
  local candidate_real="$1"
  local repo_path configured_real
  while IFS= read -r repo_path; do
    [[ -n "$repo_path" && -d "$ROOT/$repo_path/.git" ]] || continue
    configured_real="$(
      if cd "$ROOT/$repo_path" 2>/dev/null; then
        pwd -P
      fi
    )"
    if [[ -n "$configured_real" && "$candidate_real" == "$configured_real" ]]; then
      return 0
    fi
  done < <(jq -r '.projects[].repository.path' "$PROJECTS_MANIFEST" 2>/dev/null || true)
  return 1
}

find_repo_for_worktree_dir() {
  local abs_path="$1"
  if [[ -f "$abs_path/.git" ]]; then
    local gitdir
    gitdir="$(sed -n 's/^gitdir: //p' "$abs_path/.git")"
    if [[ -n "$gitdir" ]]; then
      local resolved
      if [[ "$gitdir" == /* ]]; then
        resolved="$gitdir"
      else
        resolved="$abs_path/$gitdir"
      fi
      local repo_root=""
      repo_root="$(
        if cd "$(dirname "$resolved")/../.." 2>/dev/null; then
          pwd -P
        fi
      )"
      if [[ -n "$repo_root" && -d "$repo_root/.git" ]] && is_configured_repo_root "$repo_root"; then
        printf '%s\n' "$repo_root"
        return 0
      fi
      return 1
    fi
  fi

  local repo_path repo_real
  while IFS= read -r repo_path; do
    [[ -n "$repo_path" && -d "$ROOT/$repo_path/.git" ]] || continue
    if git -C "$ROOT/$repo_path" worktree list --porcelain 2>/dev/null | grep -Fxq "worktree $abs_path"; then
      repo_real="$(cd "$ROOT/$repo_path" && pwd -P)"
      printf '%s\n' "$repo_real"
      return 0
    fi
  done < <(jq -r '.projects[].repository.path' "$PROJECTS_MANIFEST" 2>/dev/null || true)

  return 1
}

cmd_list() {
  local filter=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --active) filter="active"; shift ;;
      --inactive) filter="inactive"; shift ;;
      --orphaned) filter="orphaned"; shift ;;
      --dirty) filter="dirty"; shift ;;
      *) usage; exit 2 ;;
    esac
  done

  printf '%-32s %-10s %-8s %-5s %-26s %s\n' WORKTREE STATE GIT SLOT WORK-ITEM BRANCH
  local found=0
  local wt_rel

  while IFS= read -r wt_rel; do
    [[ -n "$wt_rel" ]] || continue
    local meta=""
    meta="$(find_meta_for_worktree "$wt_rel" || true)"
    local state git_state slot item_ref branch abs_path=""
    state="$(classify_worktree "$wt_rel" "$meta")"
    abs_path="$(resolve_safe_worktree_abspath "$wt_rel" || true)"
    if [[ -n "$abs_path" ]]; then
      git_state="$(worktree_git_state "$abs_path")"
    else
      git_state="invalid"
    fi

    if [[ -n "$meta" ]]; then
      slot="$(jq -r '.runtime.poolSlot // "-"' "$meta")"
      item_ref="$(jq -r '"\(.workspace)/\(.workItem)"' "$meta")"
      branch="$(jq -r '.design.branch // "-"' "$meta")"
    else
      slot="-"
      item_ref="-"
      branch="-"
    fi

    if [[ -n "$abs_path" && -d "$abs_path" ]] && git -C "$abs_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local live_branch
      live_branch="$(git -C "$abs_path" branch --show-current 2>/dev/null || true)"
      [[ -z "$live_branch" ]] || branch="$live_branch"
    fi

    if [[ -n "$filter" ]]; then
      if [[ "$filter" == dirty ]]; then
        [[ "$git_state" == dirty ]] || continue
      else
        [[ "$state" == "$filter" ]] || continue
      fi
    fi

    found=1
    printf '%-32s %-10s %-8s %-5s %-26s %s\n' \
      "$wt_rel" "$state" "$git_state" "$slot" "$item_ref" "$branch"
  done < <(collect_worktree_relpaths)

  [[ "$found" -eq 1 ]] || printf 'no worktrees\n'
}

cmd_inspect() {
  [[ "$#" -ge 1 && "$#" -le 2 ]] || { usage; exit 2; }
  local wt_rel=""
  local meta=""

  if [[ "$#" -eq 2 ]]; then
    local dir
    dir="$(require_work_item "$1" "$2")"
    meta="$dir/meta.json"
    wt_rel="$(jq -r '.runtime.worktree // empty' "$meta")"
    [[ -n "$wt_rel" ]] || wt_rel="$(derive_worktree_rel "$1" "$2")"
  elif [[ "$1" == */* && "$1" != worktrees/* ]]; then
    local ws="${1%%/*}"
    local wi="${1#*/}"
    local dir
    dir="$(require_work_item "$ws" "$wi")"
    meta="$dir/meta.json"
    wt_rel="$(jq -r '.runtime.worktree // empty' "$meta")"
    [[ -n "$wt_rel" ]] || wt_rel="$(derive_worktree_rel "$ws" "$wi")"
  else
    if [[ "$1" == worktrees/* ]]; then
      wt_rel="$1"
    else
      wt_rel="worktrees/$1"
    fi
    meta="$(find_meta_for_worktree "$wt_rel" || true)"
  fi

  local abs_path=""
  abs_path="$(resolve_safe_worktree_abspath "$wt_rel" || true)"
  [[ -n "$abs_path" ]] || die "invalid worktree path: $wt_rel"
  local state git_state link_mode="unregistered" branch="-"
  state="$(classify_worktree "$wt_rel" "$meta")"
  git_state="$(worktree_git_state "$abs_path")"

  if [[ -f "$abs_path/.git" ]]; then
    local gitdir_line
    gitdir_line="$(sed -n 's/^gitdir: //p' "$abs_path/.git")"
    if [[ "$gitdir_line" == /* ]]; then
      link_mode="absolute"
    elif [[ -n "$gitdir_line" ]]; then
      link_mode="relative"
    fi
  fi

  if [[ -d "$abs_path" ]] && git -C "$abs_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(git -C "$abs_path" branch --show-current 2>/dev/null || printf 'detached')"
  elif [[ -n "$meta" ]]; then
    branch="$(jq -r '.design.branch // "-"' "$meta")"
  fi

  printf 'Worktree:        %s\n' "$wt_rel"
  printf 'State:           %s\n' "$state"
  printf 'Git status:      %s\n' "$git_state"
  printf 'Link mode:       %s\n' "$link_mode"
  printf 'Branch:          %s\n' "$branch"
  if [[ -n "$meta" ]]; then
    local cid cstatus
    cid="$(jq -r '.runtime.containerId // empty' "$meta")"
    cstatus="$(inspect_container_status "$cid")"
    printf 'Work item:       %s/%s\n' "$(jq -r '.workspace' "$meta")" "$(jq -r '.workItem' "$meta")"
    printf 'Lifecycle stage: %s\n' "$(jq -r '.lifecycleStage' "$meta")"
    printf 'Runtime status:  %s\n' "$(jq -r '.runtime.status' "$meta")"
    printf 'Pool slot:       %s\n' "$(jq -r '.runtime.poolSlot // "-"' "$meta")"
    printf 'Container:       %s (%s)\n' "${cid:--}" "$cstatus"
  else
    printf 'Work item:       none\n'
  fi

  if [[ "$git_state" == dirty ]]; then
    printf 'Uncommitted changes:\n'
    git -C "$abs_path" status --short | sed 's/^/  /'
  fi
}

cmd_repair() {
  validate_projects
  local repaired=0
  local wt_dir
  if [[ -d "$ROOT/worktrees" ]]; then
    while IFS= read -r wt_dir; do
      [[ -f "$wt_dir/.git" ]] || continue
      local gitdir_line repo_dir wt_real
      gitdir_line="$(sed -n 's/^gitdir: //p' "$wt_dir/.git")"
      repo_dir="$(find_repo_for_worktree_dir "$wt_dir" || true)"
      [[ -n "$repo_dir" && -d "$repo_dir/.git" ]] \
        || die "cannot resolve configured canonical repository for worktrees/$(basename "$wt_dir")"
      if [[ "$gitdir_line" == /* ]]; then
        wt_real="$(cd "$(dirname "$wt_dir")" && pwd -P)/$(basename "$wt_dir")"
        git -C "$repo_dir" worktree repair --relative-paths "$wt_real"
        printf 'repaired relative path for worktrees/%s\n' "$(basename "$wt_dir")"
        repaired=$((repaired + 1))
      fi
    done < <(find "$ROOT/worktrees" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)
  fi

  if [[ "$repaired" -eq 0 ]]; then
    printf 'all registered worktrees are healthy\n'
  fi
}

cmd_cleanup() {
  local include_inactive=0
  local dry_run=0
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --inactive) include_inactive=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *) usage; exit 2 ;;
    esac
  done

  validate_projects
  pool_lock="$(acquire_pool_lock)"
  trap 'release_pool_lock "${pool_lock:-}"' EXIT
  export RUNTIME_POOL_LOCK_OWNER="$$"

  local actions=0
  local repo_path

  while IFS= read -r repo_path; do
    [[ -n "$repo_path" && -d "$ROOT/$repo_path/.git" ]] || continue
    local prune_out
    if [[ "$dry_run" -eq 1 ]]; then
      prune_out="$(git -C "$ROOT/$repo_path" worktree prune --dry-run -v 2>&1 || true)"
      if [[ -n "$prune_out" ]]; then
        actions=$((actions + 1))
        printf '[dry-run] %s: %s\n' "$repo_path" "$prune_out"
      fi
    else
      prune_out="$(git -C "$ROOT/$repo_path" worktree prune -v 2>&1 || true)"
      if [[ -n "$prune_out" ]]; then
        actions=$((actions + 1))
        printf 'pruned stale worktree metadata in %s\n' "$repo_path"
      fi
    fi
  done < <(jq -r '.projects[].repository.path' "$PROJECTS_MANIFEST" 2>/dev/null || true)

  local wt_rel
  while IFS= read -r wt_rel; do
    [[ -n "$wt_rel" ]] || continue
    local meta=""
    meta="$(find_meta_for_worktree "$wt_rel" || true)"
    local abs_path=""
    abs_path="$(resolve_safe_worktree_abspath "$wt_rel" || true)"
    if [[ -z "$abs_path" ]]; then
      printf 'warning: ignoring unsafe worktree path %s\n' "$wt_rel" >&2
      if [[ -n "$meta" && "$(jq -r '.runtime.worktree // empty' "$meta")" == "$wt_rel" ]]; then
        local dir ws wi cid slot next_status="stopped"
        dir="$(dirname "$meta")"
        ws="$(jq -r '.workspace' "$meta")"
        wi="$(jq -r '.workItem' "$meta")"
        cid="$(jq -r '.runtime.containerId // empty' "$meta")"
        slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
        [[ -n "$cid" && "$(inspect_container_status "$cid")" == running ]] && next_status="running"
        actions=$((actions + 1))
        if [[ "$dry_run" -eq 1 ]]; then
          printf '[dry-run] would clear invalid worktree reference %s on %s/%s\n' "$wt_rel" "$ws" "$wi"
        else
          update_runtime_state "$meta" "$next_status" "" "$cid" "$slot" worktree-cleanup
          record_history "$dir" "cleared invalid worktree reference $wt_rel"
          printf 'cleared invalid worktree reference %s on %s/%s\n' "$wt_rel" "$ws" "$wi"
        fi
      fi
      continue
    fi

    local state git_state
    state="$(classify_worktree "$wt_rel" "$meta")"
    git_state="$(worktree_git_state "$abs_path")"

    if [[ "$state" == missing && -n "$meta" ]]; then
      local ws wi dir cid slot
      dir="$(dirname "$meta")"
      ws="$(jq -r '.workspace' "$meta")"
      wi="$(jq -r '.workItem' "$meta")"
      cid="$(jq -r '.runtime.containerId // empty' "$meta")"
      slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
      actions=$((actions + 1))
      if [[ "$dry_run" -eq 1 ]]; then
        printf '[dry-run] would clear missing worktree reference %s on %s/%s\n' "$wt_rel" "$ws" "$wi"
      else
        update_runtime_state "$meta" stopped "" "$cid" "$slot" worktree-cleanup
        record_history "$dir" "cleared missing worktree reference $wt_rel"
        printf 'cleared missing worktree reference %s on %s/%s\n' "$wt_rel" "$ws" "$wi"
      fi
      continue
    fi

    if [[ "$state" == orphaned ]]; then
      if [[ -e "$abs_path" ]]; then
        if [[ "$git_state" == dirty ]]; then
          printf 'warning: skipping dirty orphaned worktree %s\n' "$wt_rel" >&2
          continue
        fi
        if [[ "$git_state" == error ]] || [[ "$git_state" == invalid && -e "$abs_path/.git" && ! -f "$abs_path/.git" ]]; then
          printf 'warning: skipping orphaned worktree with %s git state %s\n' "$git_state" "$wt_rel" >&2
          continue
        fi
        actions=$((actions + 1))
        if [[ "$dry_run" -eq 1 ]]; then
          printf '[dry-run] would remove orphaned worktree %s\n' "$wt_rel"
        else
          local repo_dir
          repo_dir="$(find_repo_for_worktree_dir "$abs_path" || true)"
          if [[ -n "$repo_dir" && -d "$repo_dir/.git" ]]; then
            git -C "$repo_dir" worktree remove "$abs_path"
          elif [[ -f "$abs_path/.git" ]]; then
            die "cannot resolve canonical repository for registered worktree: $wt_rel"
          else
            rm -rf "$abs_path"
          fi
          printf 'removed orphaned worktree %s\n' "$wt_rel"
        fi
      fi
      if [[ -n "$meta" && -n "$(jq -r '.runtime.worktree // empty' "$meta")" ]]; then
        local dir ws wi cid slot
        dir="$(dirname "$meta")"
        ws="$(jq -r '.workspace' "$meta")"
        wi="$(jq -r '.workItem' "$meta")"
        cid="$(jq -r '.runtime.containerId // empty' "$meta")"
        slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
        actions=$((actions + 1))
        if [[ "$dry_run" -eq 1 ]]; then
          printf '[dry-run] would clear stale worktree pointer on closed work item %s/%s\n' "$ws" "$wi"
        else
          update_runtime_state "$meta" stopped "" "$cid" "$slot" worktree-cleanup
          record_history "$dir" "cleared stale worktree pointer $wt_rel"
          printf 'cleared stale worktree pointer on closed work item %s/%s\n' "$ws" "$wi"
        fi
      fi
      continue
    fi

    if [[ "$state" == inactive && "$include_inactive" -eq 1 && -e "$abs_path" ]]; then
      if [[ "$git_state" != clean ]]; then
        printf 'warning: skipping %s inactive worktree %s\n' "$git_state" "$wt_rel" >&2
        continue
      fi
      local ws wi
      ws="$(jq -r '.workspace' "$meta")"
      wi="$(jq -r '.workItem' "$meta")"
      actions=$((actions + 1))
      if [[ "$dry_run" -eq 1 ]]; then
        printf '[dry-run] would reclaim inactive worktree %s from %s/%s\n' "$wt_rel" "$ws" "$wi"
      else
        "$ROOT/platform/runtime/scripts/slots.sh" release "$ws" "$wi" --remove-worktree >/dev/null
        printf 'reclaimed inactive worktree %s from %s/%s\n' "$wt_rel" "$ws" "$wi"
      fi
    fi
  done < <(collect_worktree_relpaths)

  release_pool_lock "${pool_lock:-}"
  pool_lock=""

  if [[ "$actions" -eq 0 ]]; then
    printf 'no worktree cleanup needed\n'
  fi
}

subcommand="${1:-list}"
case "$subcommand" in
  --active|--inactive|--orphaned|--dirty)
    cmd_list "$@"
    ;;
  list|status)
    [[ "$#" -eq 0 ]] || shift
    cmd_list "$@"
    ;;
  inspect)
    shift
    cmd_inspect "$@"
    ;;
  repair)
    shift
    cmd_repair "$@"
    ;;
  cleanup|prune)
    shift
    cmd_cleanup "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
