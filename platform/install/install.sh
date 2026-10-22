#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mkdir -p \
  "$ROOT/repos" \
  "$ROOT/workspaces" \
  "$ROOT/worktrees" \
  "$ROOT/.local/state"

if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  printf 'created %s\n' "$ROOT/.env"
fi

"$ROOT/platform/install/doctor.sh"
"$ROOT/platform/validate.sh"

printf '\nEnvironment ready. Projects are registered in config/projects.json.\n'
