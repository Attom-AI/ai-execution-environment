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
record_history "$directory" "closed (reason=$3)"

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
