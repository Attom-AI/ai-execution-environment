#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

if [[ "$#" -ne 3 ]]; then
  printf 'usage: %s <workspace-id> <work-item-id> <merged|abandoned>\n' "$0" >&2
  exit 2
fi
case "$3" in merged|abandoned) ;; *) die "close reason must be merged or abandoned" ;; esac

directory="$(require_work_item "$1" "$2")"
meta="$directory/meta.json"
"$ROOT/platform/runtime/scripts/stop.sh" "$1" "$2"
validate_projects
project_id="$(jq -r '.project' "$meta")"
project="$(project_by_id "$project_id")" || die "project not found: $project_id"
repository_path="$(jq -r '.repository.path' <<<"$project")"
worktree="$(jq -r '.runtime.worktree // empty' "$meta")"
container_id="$(jq -r '.runtime.containerId // empty' "$meta")"
pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta")"

if [[ -n "$worktree" ]] && [[ -e "$ROOT/$worktree" ]] && \
   [[ -n "$(git -C "$ROOT/$worktree" status --porcelain)" ]]; then
  die "worktree has uncommitted changes; commit or clean it before closing: $worktree"
fi
if [[ -n "$container_id" ]] && command -v docker >/dev/null 2>&1 && docker inspect "$container_id" >/dev/null 2>&1; then
  docker rm -f "$container_id" >/dev/null
elif [[ -n "$container_id" ]] && ! command -v docker >/dev/null 2>&1; then
  die "docker is required to remove runtime container $container_id"
fi
if [[ -n "$worktree" ]] && [[ -e "$ROOT/$worktree" ]]; then
  git -C "$ROOT/$repository_path" worktree remove "$ROOT/$worktree"
fi
update_runtime_state "$meta" stopped '' '' '' runtime-close
timestamp="$(utc_now)"
temporary="${meta}.tmp"
jq \
  --arg reason "$3" \
  --arg timestamp "$timestamp" \
  '.lifecycleStage = "closed"
   | .closed.reason = $reason
   | .closed.at = $timestamp
   | .resume.nextAgent = null
   | .resume.lastUpdatedBy = "runtime-close"
   | .resume.lastUpdatedAt = $timestamp' \
  "$meta" >"$temporary"
mv "$temporary" "$meta"
record_history "$directory" "closed (reason=$3 pool-slot=${pool_slot:-none} released)"

cat >"$directory/session-state.md" <<EOF
# Session State — $2

**Last updated:** $timestamp by runtime-close

## Status
Work item closed ($3). Runtime resources have been released.

## Next step
None.

## Open questions
- None.

## Key decisions
- Closed as $3.

## Files in flight
- None.
EOF
printf 'closed %s/%s (%s)\n' "$1" "$2" "$3"
