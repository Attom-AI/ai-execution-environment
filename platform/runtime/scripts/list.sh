#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

found=0
while IFS= read -r meta; do
  found=1
  jq -r '[.workspace, .workItem, .status, (.runtime.worktree // "-")] | @tsv' "$meta"
done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name meta.json -type f -print 2>/dev/null | sort)

if [[ "$found" -eq 0 ]]; then
  printf 'no work items\n'
fi
