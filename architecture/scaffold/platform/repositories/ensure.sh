#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

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

if [[ ! -e "$target" ]]; then
  printf 'cloning %s into %s\n' "$1" "$relative_path" >&2
  mkdir -p "$(dirname "$target")"
  "$adapter" clone "$url" "$target"
elif [[ ! -d "$target/.git" ]]; then
  die "target exists but is not a canonical Git repository: $relative_path"
fi

printf 'synchronizing %s without changing its working tree\n' "$1" >&2
"$adapter" sync "$target"
