#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

printf '%-24s %-14s %-14s %-32s %s\n' WORKSPACE WORK-ITEM STAGE WORKTREE CONTAINER
found=0
while IFS= read -r meta; do
  found=1
  container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
  container_status='-'
  if [[ -n "$container_id" ]]; then
    if command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
      container_status="$(docker inspect -f '{{.State.Status}}' "$container_id")"
    else
      container_status='missing'
    fi
  fi
  jq -r --arg container "$container_status" \
    '[.workspace, .workItem, .lifecycleStage, (.runtime.worktree // "-"), $container] | @tsv' "$meta" |
    while IFS=$'\t' read -r workspace work_item stage worktree status; do
      printf '%-24s %-14s %-14s %-32s %s\n' "$workspace" "$work_item" "$stage" "$worktree" "$status"
    done
done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)

[[ "$found" -eq 1 ]] || printf '%s\n' 'no work items'
