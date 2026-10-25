#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/identity/lib.sh
source "$ROOT/platform/identity/lib.sh"

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s <project-id>\n' "$0" >&2
  exit 2
fi

validate_projects
project="$(project_by_id "$1")" || die "unknown project: $1"
provider="$(jq -r '.repository.provider' <<<"$project")"
url="$(jq -r '.repository.url' <<<"$project")"
relative_path="$(jq -r '.repository.path' <<<"$project")"
target="$ROOT/$relative_path"
adapter="$(provider_script "$provider")"
identity="$(project_identity "$project" repository)"

if [[ ! -e "$target" ]]; then
  printf 'cloning %s into %s (identity=%s)\n' "$1" "$relative_path" "$identity" >&2
  mkdir -p "$(dirname "$target")"
  identity_exec "$identity" "$adapter" clone "$url" "$target"
elif [[ ! -d "$target/.git" ]]; then
  die "target exists but is not a canonical Git repository: $relative_path"
fi

printf 'synchronizing %s without changing its working tree (identity=%s)\n' "$1" "$identity" >&2
identity_exec "$identity" "$adapter" sync "$target"
