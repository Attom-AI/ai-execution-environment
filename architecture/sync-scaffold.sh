#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s <empty-destination>\n' "$0" >&2
  exit 2
fi

destination="$1"
mkdir -p "$destination"
[[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
  printf 'error: destination must be empty: %s\n' "$destination" >&2
  exit 1
}

git -C "$ROOT" archive HEAD -- . ':(exclude)config/projects.json' | tar -x -C "$destination"
mkdir -p "$destination/config"
cp "$ROOT/architecture/scaffold/config/projects.json" "$destination/config/projects.json"
printf 'copied portable scaffold to %s\n' "$destination"
