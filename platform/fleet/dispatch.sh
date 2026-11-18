#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
usage:
  dispatch.sh <workspace-id> <work-item-id> <goal> [options]

options:
  -e, --engine <engine>   Engine to use: claude, agy, gemini, codex
  -m, --model <model>     Specific model name/version
  -t, --tier <tier>       Semantic tier: fast, balanced, deep (default: balanced)
  -p, --priority <int>    Queue priority (default: 10)
  -f, --foreground        Run in foreground instead of background
  -h, --help              Show this help message
EOF
}

[[ "$#" -ge 3 ]] || { usage >&2; exit 2; }
workspace="$1"
work_item="$2"
goal="$3"
shift 3

engine=""
model=""
tier="balanced"
priority=10
foreground=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -e|--engine) engine="${2:-}"; shift 2 ;;
    -m|--model) model="${2:-}"; shift 2 ;;
    -t|--tier) tier="${2:-}"; shift 2 ;;
    -p|--priority) priority="${2:-10}"; shift 2 ;;
    -f|--foreground) foreground=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

item_dir="$ROOT/workspaces/$workspace/$work_item"
[[ -d "$item_dir" ]] || { printf 'error: work item directory not found: %s\n' "$item_dir" >&2; exit 1; }

meta="$item_dir/meta.json"
pool_slot="$(jq -r '.runtime.poolSlot // empty' "$meta" 2>/dev/null || true)"

# If work item does not yet have an allocated slot, check capacity
if [[ -z "$pool_slot" || "$pool_slot" == "null" ]]; then
  free_slots="$("$ROOT/platform/runtime/scripts/slots.sh" status 2>/dev/null | awk '/^Pool capacity:/ {for(i=1;i<=NF;i++) if($i=="free)") print $(i-1)}' || true)"
  if [[ "${free_slots:-0}" -le 0 ]]; then
    printf '[aee fleet] all slots in pool are occupied (0 free). Enqueueing task...\n'
    "$ROOT/platform/fleet/queue.sh" push "$workspace" "$work_item" "$goal" \
      ${engine:+--engine "$engine"} \
      --tier "$tier" \
      --priority "$priority"
    exit 0
  fi

  printf '[aee fleet] allocating slot for %s/%s...\n' "$workspace" "$work_item"
  "$ROOT/platform/runtime/scripts/slots.sh" allocate "$workspace" "$work_item"
fi

# Prepare fleet execution record
fleet_record="$item_dir/.fleet.json"
ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf '{"workspace":"%s","workItem":"%s","goal":"%s","engine":"%s","tier":"%s","status":"running","startedAt":"%s"}\n' \
  "$workspace" "$work_item" "$goal" "${engine:-auto}" "$tier" "$ts" > "$fleet_record"

exec_args=("$workspace" "$work_item" "$goal" -r -t "$tier")
[[ -z "$engine" ]] || exec_args+=(-e "$engine")
[[ -z "$model" ]] || exec_args+=(-m "$model")

log_file="$item_dir/fleet.log"
printf '[%s] fleet dispatch: %s (tier:%s, engine:%s)\n' "$ts" "$goal" "$tier" "${engine:-auto}" >> "$item_dir/history.log"

if [[ "$foreground" -eq 1 ]]; then
  printf '[aee fleet] running %s/%s in foreground...\n' "$workspace" "$work_item"
  "$ROOT/platform/agents/exec.sh" "${exec_args[@]}" 2>&1 | tee -a "$log_file"
  printf '{"workspace":"%s","workItem":"%s","status":"completed","finishedAt":"%s"}\n' \
    "$workspace" "$work_item" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$fleet_record"
else
  printf '[aee fleet] dispatched %s/%s in background slot (tier: %s, engine: %s)\n' \
    "$workspace" "$work_item" "$tier" "${engine:-auto}"
  printf 'Logs: %s\n' "$log_file"

  nohup "$ROOT/platform/agents/exec.sh" "${exec_args[@]}" >> "$log_file" 2>&1 &
  bg_pid=$!

  tmp_rec="$(mktemp /tmp/aee-fleet-rec-XXXXXX.json)"
  jq --argjson pid "$bg_pid" '.pid = $pid' "$fleet_record" > "$tmp_rec" && mv "$tmp_rec" "$fleet_record"
fi
