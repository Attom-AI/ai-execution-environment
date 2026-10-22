#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

require_command git
validate_projects

count=0
while IFS=$'\t' read -r name _workspace _url relative_path; do
  target="$ROOT/$relative_path"
  count=$((count + 1))

  if [[ ! -d "$target/.git" ]]; then
    printf '%-24s missing  %s\n' "$name" "$relative_path"
    continue
  fi

  branch="$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$target" rev-parse --short HEAD)"
  if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
    tree_state='dirty'
  else
    tree_state='clean'
  fi

  upstream_state='no-upstream'
  if git -C "$target" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    read -r behind ahead < <(git -C "$target" rev-list --left-right --count '@{upstream}...HEAD')
    upstream_state="behind=$behind ahead=$ahead"
  fi

  printf '%-24s %-16s %-5s %s\n' "$name" "$branch" "$tree_state" "$upstream_state"
done < <(project_rows)

if [[ "$count" -eq 0 ]]; then
  printf 'no projects configured in %s\n' "$PROJECTS_MANIFEST"
fi

