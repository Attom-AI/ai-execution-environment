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
worktree="$(jq -r '.runtime.worktree // empty' "$meta")"
container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"

if [[ -n "$container_id" ]] && command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
  docker stop "$container_id" >/dev/null
elif [[ -n "$container_id" ]] && ! command -v docker >/dev/null 2>&1; then
  die "docker is required to stop runtime container $container_id"
fi

update_runtime_state "$meta" stopped "$worktree" "$container_id" "$pool_slot" runtime-stop
"$ROOT/platform/context/scripts/snapshot.sh" "$1" "$2" create --reason runtime-stop >/dev/null
record_history "$directory" "runtime stopped (pool-slot=${pool_slot:-none}; resources retained)"
printf 'stopped %s/%s\n' "$1" "$2"
