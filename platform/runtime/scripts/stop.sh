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
project_id="$(jq -r '.project' "$meta")"
repository_path="$(jq -er --arg id "$project_id" '.projects[] | select(.id == $id) | .repository.path' "$PROJECTS_MANIFEST")" \
  || die "project not found: $project_id"
worktree="$(jq -r '.runtime.worktree // empty' "$meta")"

if [[ -n "$worktree" ]]; then
  git -C "$ROOT/$repository_path" worktree remove "$ROOT/$worktree"
fi

update_runtime_state "$meta" planned '' ''
printf 'stopped %s/%s\n' "$1" "$2"
