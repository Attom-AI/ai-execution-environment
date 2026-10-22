#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p \
  "$ROOT/repos" \
  "$ROOT/workspaces" \
  "$ROOT/worktrees" \
  "$ROOT/.local/state/gh"

if [[ ! -f "$ROOT/.env" ]]; then
  cp "$INSTALL_DIR/templates/.env.example" "$ROOT/.env"
  printf 'created %s\n' "$ROOT/.env"
fi

"$ROOT/platform/install/doctor.sh"
if command -v jq >/dev/null 2>&1; then
  "$ROOT/platform/validate.sh"
else
  printf 'validation skipped because jq is missing\n' >&2
fi

printf '\nEnvironment ready. Projects are registered in config/projects.json.\n'
