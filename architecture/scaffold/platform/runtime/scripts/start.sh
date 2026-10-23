#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

usage() {
  printf 'usage: %s <workspace-id> <work-item-id> [--start-point <ref>] [--no-container]\n' "$0" >&2
}

[[ "$#" -ge 2 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
shift 2
start_point=''
start_container=1
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --start-point) start_point="${2:-}"; shift 2 ;;
    --no-container) start_container=0; shift ;;
    *) usage; exit 2 ;;
  esac
done

directory="$(require_work_item "$workspace" "$work_item")"
meta="$directory/meta.json"
[[ "$(jq -r '.lifecycleStage' "$meta")" != closed ]] || die "work item is closed: $workspace/$work_item"
validate_projects
project_id="$(jq -r '.project' "$meta")"
project="$(project_by_id "$project_id")" || die "project not found: $project_id"
repository_path="$(jq -r '.repository.path' <<<"$project")"
provider="$(jq -r '.repository.provider' <<<"$project")"
repository="$ROOT/$repository_path"
provider_script "$provider" >/dev/null

if [[ -z "$start_point" ]]; then
  default_branch="$("$ROOT/platform/repositories/ensure.sh" "$project_id")"
  start_point="origin/$default_branch"
else
  [[ -d "$repository/.git" ]] || die "canonical repository is missing: $repository_path"
fi

branch="$(jq -r '.design.branch // empty' "$meta")"
[[ -n "$branch" ]] || die "work item has no design branch: $workspace/$work_item"
worktree_id="$(printf '%s-%s' "$workspace" "$work_item" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
worktree="worktrees/${worktree_id%-}"
target="$ROOT/$worktree"
target_real="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"

if git -C "$repository" worktree list --porcelain | grep -Fxq "worktree $target_real"; then
  printf 'reusing worktree %s\n' "$worktree" >&2
  if [[ "$(sed -n 's/^gitdir: //p' "$target/.git")" == /* ]]; then
    git -C "$repository" worktree repair --relative-paths "$target_real"
  fi
elif [[ -e "$target" ]]; then
  die "worktree path exists but is not registered: $worktree"
elif git -C "$repository" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$repository" worktree add --relative-paths "$target" "$branch"
else
  git -C "$repository" worktree add --relative-paths --no-track -b "$branch" "$target" "$start_point"
fi

container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"
update_runtime_state "$meta" worktree-ready "$worktree" "$container_id" "$pool_slot" runtime-start

if [[ "$start_container" -eq 1 ]]; then
  require_command docker
  require_command devcontainer
  pool_lock="$(acquire_pool_lock)"
  trap 'rmdir "$pool_lock" 2>/dev/null || true' EXIT
  pool_slot="$(claim_pool_slot "$meta")"
  if [[ -n "$container_id" ]] && docker inspect "$container_id" >/dev/null 2>&1; then
    container_status="$(docker inspect -f '{{.State.Status}}' "$container_id")"
    if [[ "$container_status" != running ]]; then
      docker start "$container_id" >/dev/null
    fi
  else
    export EXECUTION_ROOT="$ROOT"
    up_result="$(devcontainer up \
      --workspace-folder "$target" \
      --mount-git-worktree-common-dir \
      --config "$ROOT/platform/runtime/.devcontainer/devcontainer.json" \
      --id-label "ai.execution-environment.runtime=slot-$pool_slot-$worktree_id")"
    container_id="$(jq -r '.containerId // empty' <<<"$up_result")"
    [[ -n "$container_id" ]] || die "devcontainer did not return a container id"
  fi
  runtime_status=running
else
  runtime_status='worktree-ready'
fi

update_runtime_state "$meta" "$runtime_status" "$worktree" "$container_id" "$pool_slot" runtime-start
record_history "$directory" "runtime started (worktree=$worktree container=${container_id:-none} pool-slot=${pool_slot:-none})"
printf 'started %s/%s at %s\n' "$workspace" "$work_item" "$target"
