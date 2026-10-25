#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/identity/lib.sh
source "$ROOT/platform/identity/lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 <workspace-id> <work-item-id> [--issues] -- <command> [args...]
  $0 --project <project-id> [--issues] -- <command> [args...]
  $0 --identity <identity-id> -- <command> [args...]
EOF
}

kind=repository
identity=''
case "${1:-}" in
  --project)
    [[ "$#" -ge 2 ]] || { usage; exit 2; }
    validate_projects
    project="$(project_by_id "$2")" || die "unknown project: $2"
    shift 2
    if [[ "${1:-}" == --issues ]]; then kind=issues; shift; fi
    identity="$(project_identity "$project" "$kind")"
    ;;
  --identity)
    [[ "$#" -ge 2 ]] || { usage; exit 2; }
    identity="$2"
    shift 2
    ;;
  ''|--*)
    usage
    exit 2
    ;;
  *)
    [[ "$#" -ge 2 ]] || { usage; exit 2; }
    workspace="$1"
    work_item="$2"
    shift 2
    if [[ "${1:-}" == --issues ]]; then kind=issues; shift; fi
    identity="$(work_item_identity "$workspace" "$work_item" "$kind")"
    ;;
esac
[[ "${1:-}" == -- ]] || { usage; exit 2; }
shift
[[ "$#" -gt 0 ]] || { usage; exit 2; }

# Verify the account before commands that publish under it. Subcommands are
# matched anywhere after the program so global flags (`gh -R <repo> pr create`)
# cannot skip verification. This catches mistakes, not deliberate bypasses such
# as raw API calls; profile isolation is what bounds those.
outbound=0
arguments=("$@")
case "$(basename "$1")" in
  git)
    for argument in "${arguments[@]:1}"; do
      [[ "$argument" != push ]] || { outbound=1; break; }
    done
    ;;
  gh|glab)
    group='pr'
    [[ "$(basename "$1")" == gh ]] || group='mr'
    for ((index = 1; index + 1 < ${#arguments[@]}; index++)); do
      if [[ "${arguments[index]}" == "$group" ]]; then
        case "${arguments[index + 1]}" in create|merge) outbound=1; break ;; esac
      fi
    done
    ;;
esac
if [[ "$outbound" -eq 1 ]]; then
  identity_check "$identity" >&2 || die "identity $identity failed verification; refusing to run: $*"
fi

identity_exec "$identity" "$@"
