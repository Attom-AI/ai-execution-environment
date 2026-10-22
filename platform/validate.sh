#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

validate_projects

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_materialized="$(git -C "$ROOT" ls-files \
    'repos/**' 'workspaces/**' 'worktrees/**' '.local/**' '.env')"
  [[ -z "$tracked_materialized" ]] || die "materialized paths are tracked:\n$tracked_materialized"
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT" \
  -path "$ROOT/repos" -prune -o \
  -path "$ROOT/workspaces" -prune -o \
  -path "$ROOT/worktrees" -prune -o \
  -path "$ROOT/.local" -prune -o \
  -name '*.sh' -type f -print | sort)

if command -v shellcheck >/dev/null 2>&1; then
  shell_scripts=()
  while IFS= read -r script; do
    shell_scripts+=("$script")
  done < <(find "$ROOT" \
    -path "$ROOT/repos" -prune -o \
    -path "$ROOT/workspaces" -prune -o \
    -path "$ROOT/worktrees" -prune -o \
    -path "$ROOT/.local" -prune -o \
    -name '*.sh' -type f -print | sort)
  if [[ "${#shell_scripts[@]}" -gt 0 ]]; then
    shellcheck "${shell_scripts[@]}"
  fi
else
  printf 'warning: shellcheck not installed; static shell analysis skipped\n' >&2
fi

while IFS= read -r json_file; do
  jq -e . "$json_file" >/dev/null
done < <(find "$ROOT" \
  -path "$ROOT/repos" -prune -o \
  -path "$ROOT/workspaces" -prune -o \
  -path "$ROOT/worktrees" -prune -o \
  -path "$ROOT/.local" -prune -o \
  -name '*.json' -type f -print)

printf 'execution environment is valid\n'
