#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT/.local/state"
QUEUE_FILE="$STATE_DIR/fleet-queue.json"

mkdir -p "$STATE_DIR"
if [[ ! -f "$QUEUE_FILE" ]]; then
  printf '{"queue":[]}\n' > "$QUEUE_FILE"
fi

usage() {
  cat <<'EOF'
usage:
  queue.sh list
  queue.sh push <workspace-id> <work-item-id> <goal> [--engine <engine>] [--tier <tier>] [--priority <int>]
  queue.sh pop [--auto]
  queue.sh cancel <workspace-id> <work-item-id>
  queue.sh clear
  queue.sh count
EOF
}

count_free_slots() {
  local count
  count="$("$ROOT/platform/runtime/scripts/slots.sh" status 2>/dev/null | awk '/^Pool capacity:/ {for(i=1;i<=NF;i++) if($i=="free)") print $(i-1)}' || true)"
  printf '%s' "${count:-0}"
}

cmd_list() {
  local q_len
  q_len="$(jq '.queue | length' "$QUEUE_FILE")"
  if [[ "$q_len" -eq 0 ]]; then
    printf 'Fleet queue is empty (0 queued tasks).\n'
    return 0
  fi

  printf 'Fleet Task Queue (%s pending):\n' "$q_len"
  printf '%-4s %-28s %-14s %-8s %-10s %-8s %s\n' PRIO WORKSPACE WORK-ITEM TIER ENGINE ENQUEUED GOAL
  jq -r '
    .queue | sort_by(-.priority, .enqueuedAt)[] |
    [
      (.priority // 0 | tostring),
      .workspace,
      .workItem,
      (.tier // "balanced"),
      (.engine // "auto"),
      (.enqueuedAt[11:19] // "-"),
      .goal
    ] | @tsv
  ' "$QUEUE_FILE" | while IFS=$'\t' read -r prio ws wi tr eng ts goal; do
    printf '%-4s %-28s %-14s %-8s %-10s %-8s %s\n' "$prio" "$ws" "$wi" "$tr" "$eng" "$ts" "$goal"
  done
}

cmd_push() {
  [[ "$#" -ge 3 ]] || { usage >&2; exit 2; }
  local ws="$1"
  local wi="$2"
  local goal="$3"
  shift 3

  local engine=""
  local tier="balanced"
  local priority=10

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --engine|-e) engine="${2:-}"; shift 2 ;;
      --tier|-t) tier="${2:-}"; shift 2 ;;
      --priority|-p) priority="${2:-10}"; shift 2 ;;
      *) usage >&2; exit 2 ;;
    esac
  done

  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local tmp
  tmp="$(mktemp /tmp/aee-queue-XXXXXX.json)"

  # Remove any existing queued entry for this work item before inserting
  jq --arg ws "$ws" --arg wi "$wi" --arg goal "$goal" --arg eng "$engine" \
     --arg tr "$tier" --argjson prio "$priority" --arg ts "$ts" '
    .queue = ([.queue[] | select(.workspace != $ws or .workItem != $wi)] + [{
      workspace: $ws,
      workItem: $wi,
      goal: $goal,
      engine: $eng,
      tier: $tr,
      priority: $prio,
      enqueuedAt: $ts
    }])
  ' "$QUEUE_FILE" > "$tmp" && mv "$tmp" "$QUEUE_FILE"

  local pos
  pos="$(jq '.queue | length' "$QUEUE_FILE")"
  printf 'enqueued %s/%s in fleet queue (position %s, priority %s)\n' "$ws" "$wi" "$pos" "$priority"
}

cmd_pop() {
  local auto_mode=0
  if [[ "${1:-}" == "--auto" ]]; then
    auto_mode=1
  fi

  local q_len
  q_len="$(jq '.queue | length' "$QUEUE_FILE")"
  if [[ "$q_len" -eq 0 ]]; then
    if [[ "$auto_mode" -eq 0 ]]; then
      printf 'Fleet queue is empty.\n'
    fi
    return 0
  fi

  local free_slots
  free_slots="$(count_free_slots)"
  if [[ "$free_slots" -le 0 ]]; then
    if [[ "$auto_mode" -eq 0 ]]; then
      printf 'cannot pop from fleet queue: all container pool slots are occupied (0 free slots).\n'
    fi
    return 0
  fi

  # Pick highest priority, oldest enqueued task
  local next_item
  next_item="$(jq -c '.queue | sort_by(-.priority, .enqueuedAt) | .[0]' "$QUEUE_FILE")"
  local ws wi goal eng tr prio
  ws="$(jq -r '.workspace' <<<"$next_item")"
  wi="$(jq -r '.workItem' <<<"$next_item")"
  goal="$(jq -r '.goal' <<<"$next_item")"
  eng="$(jq -r '.engine // empty' <<<"$next_item")"
  tr="$(jq -r '.tier // "balanced"' <<<"$next_item")"
  prio="$(jq -r '.priority // 10' <<<"$next_item")"

  # Remove from queue
  local tmp
  tmp="$(mktemp /tmp/aee-queue-XXXXXX.json)"
  jq --arg ws "$ws" --arg wi "$wi" '
    .queue = [.queue[] | select(.workspace != $ws or .workItem != $wi)]
  ' "$QUEUE_FILE" > "$tmp" && mv "$tmp" "$QUEUE_FILE"

  printf 'popped %s/%s from fleet queue (priority %s)\n' "$ws" "$wi" "$prio"

  # Dispatch task
  local dispatch_args=("$ws" "$wi" "$goal" --tier "$tr")
  [[ -z "$eng" ]] || dispatch_args+=(--engine "$eng")

  if [[ -x "$ROOT/platform/fleet/dispatch.sh" ]]; then
    "$ROOT/platform/fleet/dispatch.sh" "${dispatch_args[@]}"
  fi
}

cmd_cancel() {
  [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
  local ws="$1"
  local wi="$2"

  local tmp
  tmp="$(mktemp /tmp/aee-queue-XXXXXX.json)"
  jq --arg ws "$ws" --arg wi "$wi" '
    .queue = [.queue[] | select(.workspace != $ws or .workItem != $wi)]
  ' "$QUEUE_FILE" > "$tmp" && mv "$tmp" "$QUEUE_FILE"

  printf 'cancelled and removed %s/%s from fleet queue\n' "$ws" "$wi"
}

cmd_clear() {
  printf '{"queue":[]}\n' > "$QUEUE_FILE"
  printf 'fleet queue cleared\n'
}

cmd_count() {
  jq '.queue | length' "$QUEUE_FILE"
}

action="${1:-}"
[[ "$#" -eq 0 ]] || shift

case "$action" in
  list|status) cmd_list "$@" ;;
  push) cmd_push "$@" ;;
  pop) cmd_pop "$@" ;;
  cancel) cmd_cancel "$@" ;;
  clear) cmd_clear ;;
  count) cmd_count ;;
  help|--help|-h) usage; exit 0 ;;
  "") cmd_list ;;
  *)
    printf 'error: unknown queue action: %s\n' "$action" >&2
    usage >&2
    exit 2
    ;;
esac
