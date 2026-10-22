#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

require_command git
validate_projects

count=0
while IFS=$'\t' read -r name _workspace provider _url relative_path; do
  target="$ROOT/$relative_path"
  count=$((count + 1))

  if [[ ! -d "$target/.git" ]]; then
    printf 'skipping %s; checkout is missing (%s)\n' "$name" "$relative_path"
    continue
  fi

  printf 'fetching %s\n' "$name"
  "$(provider_script "$provider")" sync "$target" >/dev/null
done < <(project_rows)

if [[ "$count" -eq 0 ]]; then
  printf 'no projects configured in %s\n' "$PROJECTS_MANIFEST"
fi
