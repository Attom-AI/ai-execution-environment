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
if [[ "$(jq -r '.runtime.worktree // empty' "$directory/meta.json")" != "" ]]; then
  "$ROOT/platform/runtime/scripts/stop.sh" "$1" "$2"
fi
update_runtime_state "$directory/meta.json" closed '' ''
printf 'closed %s/%s\n' "$1" "$2"
