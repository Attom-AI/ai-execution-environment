#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT/.local/state"
JOBS_FILE="$STATE_DIR/jobs.json"

save_briefing=0
output_path=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --save)
      save_briefing=1
      shift
      ;;
    -o|--output)
      [[ "$#" -ge 2 ]] || exit 2
      output_path="$2"
      save_briefing=1
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
usage:
  briefing.sh [--save] [-o <file>]

options:
  --save      Save the briefing under documentation/briefings/
  -o, --output <file> Save briefing to a specific file path
  -h, --help  Show this help message
EOF
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

current_date="$(date -u +'%Y-%m-%d')"
current_time="$(date -u +'%H:%M:%SZ')"

generate_briefing() {
  printf '# ☀️ AEE Executive Morning Briefing: %s\n\n' "$current_date"
  printf "Generated at: \`%s\` UTC\n\n" "$current_time"

  if [[ ! -f "$JOBS_FILE" ]]; then
    printf "*(No jobs manifest found in \`.local/state/jobs.json\`)*\n\n"
    return 0
  fi

  local total_jobs completed_jobs queued_jobs running_jobs failed_jobs
  total_jobs="$(jq '.jobs | length' "$JOBS_FILE")"
  completed_jobs="$(jq '[.jobs[] | select(.status == "completed")] | length' "$JOBS_FILE")"
  running_jobs="$(jq '[.jobs[] | select(.status == "running")] | length' "$JOBS_FILE")"
  queued_jobs="$(jq '[.jobs[] | select(.status == "queued")] | length' "$JOBS_FILE")"
  failed_jobs="$(jq '[.jobs[] | select(.status == "failed" or .status == "budget_capped")] | length' "$JOBS_FILE")"

  printf '### Job Health Overview\n'
  printf -- '- **Total Tracked Jobs**: %s\n' "$total_jobs"
  printf -- '- **Completed Successfully**: %s\n' "$completed_jobs"
  printf -- '- **In Progress**: %s\n' "$running_jobs"
  printf -- '- **Pending in Queue**: %s\n' "$queued_jobs"
  printf -- '- **Failed / Budget Capped**: %s\n\n' "$failed_jobs"

  # Completed Jobs
  printf '### Completed Operations\n'
  if [[ "$completed_jobs" -gt 0 ]]; then
    jq -r '
      .jobs[] | select(.status == "completed") |
      "#### ✅ [" + .type + "] " + .id + "\n" +
      "- **Goal**: " + .goal + "\n" +
      "- **Tier**: `" + (.tier // "balanced") + "` (Engine: `" + (.engine // "auto") + "`)\n" +
      (if .outputFile then ("- **Generated Artifact**: [" + .outputFile + "](file://" + .outputFile + ")\n") else "" end) +
      (if .notes then ("- **Outcome**: " + .notes + "\n") else "" end) +
      "- **Finished At**: `" + (.finishedAt // "-") + "`\n"
    ' "$JOBS_FILE"
  else
    printf '*(No completed jobs recorded yet)*\n\n'
  fi

  # Running / In Progress Jobs
  if [[ "$running_jobs" -gt 0 ]]; then
    printf '### In-Flight Operations\n'
    jq -r '
      .jobs[] | select(.status == "running") |
      "- ⏳ **" + .id + "** (" + .type + "): " + .goal + " [Tier: `" + (.tier // "balanced") + "`]\n"
    ' "$JOBS_FILE"
    printf '\n'
  fi

  # Pending / Queued Jobs
  if [[ "$queued_jobs" -gt 0 ]]; then
    printf '### Pending Queue\n'
    jq -r '
      .jobs[] | select(.status == "queued") |
      "- 💤 **" + .id + "** (" + .type + "): " + .goal + " (max turns: " + (.maxTurns | tostring) + ", max cost: $" + (.maxCostUsd | tostring) + ")\n"
    ' "$JOBS_FILE"
    printf '\n'
  fi

  # Failed / Budget-capped Jobs
  if [[ "$failed_jobs" -gt 0 ]]; then
    printf '### Attention Required (Failed or Budget Capped)\n'
    jq -r '
      .jobs[] | select(.status == "failed" or .status == "budget_capped") |
      "- ⚠️ **" + .id + "** (" + .type + "): " + .goal + "\n  *Reason*: " + (.notes // "unknown error") + "\n"
    ' "$JOBS_FILE"
    printf '\n'
  fi

  # Active Slots Overview
  printf '### Active Runtime Slots\n'
  printf '```\n'
  "$ROOT/platform/runtime/scripts/slots.sh" status 2>/dev/null || printf 'Slots status unavailable\n'
  printf '```\n'
}

if [[ "$save_briefing" -eq 1 ]]; then
  if [[ -z "$output_path" ]]; then
    mkdir -p "$ROOT/documentation/briefings"
    output_path="$ROOT/documentation/briefings/${current_date}-morning-briefing.md"
  else
    mkdir -p "$(dirname "$output_path")"
  fi
  generate_briefing | tee "$output_path"
  printf '\nMorning briefing saved to: %s\n' "$output_path"
else
  generate_briefing
fi
