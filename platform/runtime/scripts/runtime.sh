#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS="$ROOT/platform/runtime/scripts"

usage() {
  cat <<'EOF'
usage:
  runtime.sh start <workspace-id> <work-item-id> [--start-point <ref>] [--slot <slot>] [--no-container] [--recreate-container]
  runtime.sh stop <workspace-id> <work-item-id>
  runtime.sh close <workspace-id> <work-item-id> <merged|abandoned>
  runtime.sh list
  runtime.sh slots [status|resize|add|allocate|release|recreate|cleanup] [args...]
  runtime.sh worktrees [list|inspect|repair|cleanup] [args...]
EOF
}

action="${1:-}"
[[ "$#" -eq 0 ]] || shift

case "$action" in
  start)
    exec "$SCRIPTS/start.sh" "$@"
    ;;
  stop)
    exec "$SCRIPTS/stop.sh" "$@"
    ;;
  close)
    exec "$SCRIPTS/close.sh" "$@"
    ;;
  list|status)
    exec "$SCRIPTS/list.sh" "$@"
    ;;
  slots)
    exec "$SCRIPTS/slots.sh" "$@"
    ;;
  worktrees)
    exec "$SCRIPTS/worktrees.sh" "$@"
    ;;
  help|--help|-h)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  *)
    printf 'error: unknown runtime action: %s\n' "$action" >&2
    usage >&2
    exit 2
    ;;
esac
