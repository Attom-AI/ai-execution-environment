#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$ROOT/platform/runtime/scripts/lib.sh"

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  printf 'usage: %s <workspace-id> <work-item-id> [start-point]\n' "$0" >&2
  exit 2
fi

workspace="$1"
work_item="$2"
start_point="${3:-HEAD}"
directory="$(require_work_item "$workspace" "$work_item")"
meta="$directory/meta.json"
project_id="$(jq -r '.project' "$meta")"
repository_path="$(jq -er --arg id "$project_id" '.projects[] | select(.id == $id) | .repository.path' "$PROJECTS_MANIFEST")" \
  || die "project not found: $project_id"
repository="$ROOT/$repository_path"
[[ -d "$repository/.git" ]] || die "canonical repository is missing: $repository_path"

worktree_id="$(printf '%s-%s' "$workspace" "$work_item" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
worktree="worktrees/${worktree_id%-}"
target="$ROOT/$worktree"
branch="work/$workspace/$(printf '%s' "$work_item" | tr '[:upper:]' '[:lower:]')"
[[ ! -e "$target" ]] || die "worktree path already exists: $worktree"

if git -C "$repository" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$repository" worktree add "$target" "$branch"
else
  git -C "$repository" worktree add -b "$branch" "$target" "$start_point"
fi

update_runtime_state "$meta" active "$worktree" "$branch"
printf '%s\n' "$worktree" >>"$directory/history.log"
printf 'started %s at %s\n' "$workspace/$work_item" "$target"
