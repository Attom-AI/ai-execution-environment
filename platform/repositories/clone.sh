#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

require_command git
validate_projects

count=0
while IFS=$'\t' read -r name _workspace url relative_path; do
  target="$ROOT/$relative_path"
  count=$((count + 1))

  if [[ -d "$target/.git" ]]; then
    printf 'present %s (%s)\n' "$name" "$relative_path"
    continue
  fi

  if [[ -e "$target" ]]; then
    die "target exists but is not a Git repository: $relative_path"
  fi

  printf 'cloning %s into %s\n' "$name" "$relative_path"
  mkdir -p "$(dirname "$target")"
  git clone -- "$url" "$target"
done < <(project_rows)

if [[ "$count" -eq 0 ]]; then
  printf 'no projects configured in %s\n' "$PROJECTS_MANIFEST"
fi

