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

# Verify the account before commands that publish under it.
outbound=0
case "$1 ${2:-} ${3:-}" in
  'gh pr create'*|'gh pr merge'*|'glab mr create'*|'glab mr merge'*) outbound=1 ;;
esac
if [[ "$1" == git ]]; then
  for argument in "${@:2}"; do
    [[ "$argument" != push ]] || { outbound=1; break; }
  done
fi
if [[ "$outbound" -eq 1 ]]; then
  identity_check "$identity" >&2 || die "identity $identity failed verification; refusing to run: $*"
fi

identity_exec "$identity" "$@"
