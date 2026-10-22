#!/usr/bin/env bash

set -euo pipefail

missing=0

for command_name in bash devcontainer docker envsubst git gh jq rg shellcheck; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$command_name"
  else
    printf 'missing %s\n' "$command_name" >&2
    missing=1
  fi
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_config="$root/platform/runtime/.devcontainer/devcontainer.json"
if command -v jq >/dev/null 2>&1 && jq -e '
  .features
  | has("ghcr.io/devcontainers/features/hugo:1") and
    has("ghcr.io/devcontainers/features/java:1")
' "$runtime_config" >/dev/null; then
  printf 'configured runtime:hugo\n'
  printf 'configured runtime:sdkman\n'
else
  printf 'missing runtime Hugo/SDKMAN feature configuration\n' >&2
  missing=1
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    printf 'ok      github-auth\n'
  else
    printf 'missing github-auth (run: gh auth login)\n' >&2
  fi
fi

if [[ "$missing" -ne 0 ]]; then
  printf '\nInstall the missing tools before running work-item automation.\n' >&2
fi
