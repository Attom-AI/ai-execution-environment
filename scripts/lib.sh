#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_MANIFEST="${REPOS_MANIFEST:-$WORKSPACE_ROOT/config/repos.json}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_manifest() {
  require_command jq
  [[ -f "$REPOS_MANIFEST" ]] || die "manifest not found: $REPOS_MANIFEST"

  jq -e '
    .version == 1 and
    (.repos | type == "array") and
    ([.repos[].name] | length == (unique | length)) and
    ([.repos[].path] | length == (unique | length)) and
    all(.repos[];
      (.name | type == "string" and length > 0 and (test("[\\t\\r\\n]") | not)) and
      (.url | type == "string" and length > 0 and (test("[\\t\\r\\n]") | not)) and
      (.path | type == "string" and test("^repos/[^/]+(?:/[^/]+)*$")) and
      (.path | split("/") | all(. != "." and . != "..")) and
      ((.groups // []) | type == "array")
    )
  ' "$REPOS_MANIFEST" >/dev/null || die "invalid repository manifest: $REPOS_MANIFEST"
}

repo_rows() {
  jq -r '.repos[] | [.name, .url, .path] | @tsv' "$REPOS_MANIFEST"
}

