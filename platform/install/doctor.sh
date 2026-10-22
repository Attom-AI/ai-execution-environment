#!/usr/bin/env bash

set -euo pipefail

missing=0

for command_name in bash git gh hugo jq rg shellcheck; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$command_name"
  else
    printf 'missing %s\n' "$command_name" >&2
    missing=1
  fi
done

sdkman_dir="${SDKMAN_DIR:-/usr/local/sdkman}"
if [[ -s "$sdkman_dir/bin/sdkman-init.sh" ]]; then
  if SDKMAN_DIR="$sdkman_dir" bash -c '
    # shellcheck source=/dev/null
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    command -v sdk >/dev/null 2>&1
  '; then
    printf 'ok      sdkman\n'
  else
    printf 'missing sdkman\n' >&2
    missing=1
  fi
else
  printf 'missing sdkman\n' >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  printf '\nOpen this repository in its devcontainer to install the workspace tools.\n' >&2
  exit 1
fi

