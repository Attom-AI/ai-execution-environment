#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

if [[ "$#" -ne 2 ]]; then
  printf 'usage: %s <workspace-id> <work-item-id>\n' "$0" >&2
  exit 2
fi

directory="$(require_work_item "$1" "$2")"
meta="$directory/meta.json"
validate_projects
project_id="$(jq -r '.project' "$meta")"
project="$(project_by_id "$project_id")" || die "project not found: $project_id"
repository_path="$(jq -r '.repository.path' <<<"$project")"
worktree="$(jq -r '.runtime.worktree // empty' "$meta")"
container_id="$(jq -r '.runtime.containerId // empty' "$meta")"

if [[ -n "$worktree" ]] && [[ -e "$ROOT/$worktree" ]] && \
   [[ -n "$(git -C "$ROOT/$worktree" status --porcelain)" ]]; then
  die "worktree has uncommitted changes; commit or clean it before stopping: $worktree"
fi

if [[ -n "$container_id" ]] && command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
  docker rm -f "$container_id" >/dev/null
elif [[ -n "$container_id" ]] && ! command -v docker >/dev/null 2>&1; then
  die "docker is required to remove runtime container $container_id"
fi

if [[ -n "$worktree" ]] && [[ -e "$ROOT/$worktree" ]]; then
  git -C "$ROOT/$repository_path" worktree remove "$ROOT/$worktree"
fi

update_runtime_state "$meta" stopped '' '' runtime-stop
record_history "$directory" 'runtime stopped'
printf 'stopped %s/%s\n' "$1" "$2"
