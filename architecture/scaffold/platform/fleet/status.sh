#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
usage:
  status.sh [options]

options:
  -h, --help    Show this help message
EOF
}

[[ "${1:-}" != "--help" && "${1:-}" != "-h" ]] || { usage; exit 0; }

printf '=== AEE Fleet & Capacity Status ===\n\n'

# 1. Container Slots
"$ROOT/platform/runtime/scripts/slots.sh" status
printf '\n'

# 2. Active Background Workers
printf '=== Active Fleet Background Workers ===\n'
found_workers=0
printf '%-28s %-14s %-8s %-8s %-10s %s\n' WORKSPACE WORK-ITEM PID TIER ENGINE STATUS
while IFS= read -r rec_file; do
  if [[ -f "$rec_file" ]]; then
    ws="$(jq -r '.workspace // "-"' "$rec_file")"
    wi="$(jq -r '.workItem // "-"' "$rec_file")"
    pid="$(jq -r '.pid // "-"' "$rec_file")"
    tr="$(jq -r '.tier // "-"' "$rec_file")"
    eng="$(jq -r '.engine // "-"' "$rec_file")"
    st="$(jq -r '.status // "-"' "$rec_file")"

    # Check if PID is still alive
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      if kill -0 "$pid" 2>/dev/null; then
        st="running"
      else
        st="finished"
      fi
    fi

    printf '%-28s %-14s %-8s %-8s %-10s %s\n' "$ws" "$wi" "$pid" "$tr" "$eng" "$st"
    found_workers=1
  fi
done < <(find "$ROOT/workspaces" -mindepth 3 -maxdepth 3 -name ".fleet.json" -type f 2>/dev/null | sort)

if [[ "$found_workers" -eq 0 ]]; then
  printf 'No background fleet workers currently running.\n'
fi
printf '\n'

# 3. Queued Tasks
printf '=== Queued Fleet Tasks ===\n'
"$ROOT/platform/fleet/queue.sh" list
