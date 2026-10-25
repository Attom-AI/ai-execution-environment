#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECTS_MANIFEST="${PROJECTS_MANIFEST:-$WORKSPACE_ROOT/config/projects.json}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_projects() {
  require_command jq
  [[ -f "$PROJECTS_MANIFEST" ]] || die "manifest not found: $PROJECTS_MANIFEST"

  jq -e '
    .version == 1 and
    (.projects | type == "array") and
    ([.projects[].id] | length == (unique | length)) and
    ([.projects[].workspace] | length == (unique | length)) and
    ([.projects[].repository.path] | length == (unique | length)) and
    all(.projects[];
      (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
      (.workspace | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
      (.repository.provider | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
      (.repository.owner | type == "string" and length > 0) and
      (.repository.name | type == "string" and length > 0) and
      (.repository.url | type == "string" and length > 0) and
      (.repository.path | type == "string" and test("^repos/[^/]+(?:/[^/]+)*$")) and
      (.repository.path | split("/") | all(. != "." and . != "..")) and
      (.issues.provider | type == "string" and length > 0) and
      (.issues.owner | type == "string" and length > 0) and
      (.issues.repository | type == "string" and length > 0) and
      (.repository.identity == null or (.repository.identity | type == "string" and test("^[a-z0-9][a-z0-9-]*$"))) and
      (.issues.identity == null or (.issues.identity | type == "string" and test("^[a-z0-9][a-z0-9-]*$")))
    )
  ' "$PROJECTS_MANIFEST" >/dev/null || die "invalid project manifest: $PROJECTS_MANIFEST"
}

project_rows() {
  jq -r '.projects[] | [.id, .workspace, .repository.provider, .repository.url, .repository.path] | @tsv' "$PROJECTS_MANIFEST"
}

project_by_workspace() {
  jq -e --arg workspace "$1" '.projects[] | select(.workspace == $workspace)' "$PROJECTS_MANIFEST"
}

project_by_id() {
  jq -e --arg id "$1" '.projects[] | select(.id == $id)' "$PROJECTS_MANIFEST"
}

provider_script() {
  local provider="$1"
  local script="$WORKSPACE_ROOT/platform/repositories/providers/$provider.sh"
  [[ -x "$script" ]] || die "unsupported repository provider: $provider"
  printf '%s\n' "$script"
}
