#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/identity/lib.sh
source "$ROOT/platform/identity/lib.sh"

require_command git
validate_projects

count=0
while IFS=$'\t' read -r name _workspace provider url relative_path; do
  target="$ROOT/$relative_path"
  count=$((count + 1))

  if [[ -d "$target/.git" ]]; then
    printf 'present %s (%s)\n' "$name" "$relative_path"
    continue
  fi

  if [[ -e "$target" ]]; then
    die "target exists but is not a Git repository: $relative_path"
  fi

  identity="$(project_identity "$(project_by_id "$name")" repository)"
  printf 'cloning %s into %s (identity=%s)\n' "$name" "$relative_path" "$identity"
  mkdir -p "$(dirname "$target")"
  identity_exec "$identity" "$(provider_script "$provider")" clone "$url" "$target"
done < <(project_rows)

if [[ "$count" -eq 0 ]]; then
  printf 'no projects configured in %s\n' "$PROJECTS_MANIFEST"
fi
