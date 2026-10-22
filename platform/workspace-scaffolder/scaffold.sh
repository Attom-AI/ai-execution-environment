#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  printf 'usage: %s <workspace-id> <issue-number> [work-item-prefix]\n' "$0" >&2
  exit 2
fi

workspace="$1"
issue_number="$2"
prefix="${3:-ISSUE}"

[[ "$issue_number" =~ ^[0-9]+$ ]] || die "issue number must be numeric"
[[ "$prefix" =~ ^[A-Z][A-Z0-9-]*$ ]] || die "work-item prefix must be uppercase"

validate_projects
project="$(project_by_workspace "$workspace")" || die "unknown workspace: $workspace"
project_id="$(jq -r '.id' <<<"$project")"
owner="$(jq -r '.issues.owner' <<<"$project")"
repository="$(jq -r '.issues.repository' <<<"$project")"
provider="$(jq -r '.issues.provider' <<<"$project")"
[[ "$provider" == "github" ]] || die "unsupported issue provider: $provider"

work_item="${prefix}-${issue_number}"
target="$ROOT/workspaces/$workspace/$work_item"
[[ ! -e "$target" ]] || die "work item already exists: $target"

issue_snapshot="$(mktemp)"
trap 'rm -f "$issue_snapshot"' EXIT
"$ROOT/platform/workspace-scaffolder/sources/github.sh" \
  "$owner" "$repository" "$issue_number" >"$issue_snapshot"
jq -e . "$issue_snapshot" >/dev/null || die "issue provider returned invalid JSON"

mkdir -p "$target/artifacts"
mv "$issue_snapshot" "$target/issue.json"

jq \
  --arg workspace "$workspace" \
  --arg work_item "$work_item" \
  --arg project "$project_id" \
  --arg provider "$provider" \
  --arg owner "$owner" \
  --arg repository "$repository" \
  --argjson number "$issue_number" \
  '.workspace = $workspace
   | .workItem = $work_item
   | .project = $project
   | .source = {
       provider: $provider,
       owner: $owner,
       repository: $repository,
       number: $number
     }' \
  "$ROOT/platform/state/templates/meta.json" >"$target/meta.json"
cp "$ROOT/platform/state/templates/session-state.md" "$target/session-state.md"
: >"$target/history.log"

printf 'created %s\n' "$target"
