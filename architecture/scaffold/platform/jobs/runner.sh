#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT/.local/state"
JOBS_FILE="$STATE_DIR/jobs.json"

mkdir -p "$STATE_DIR"
if [[ ! -f "$JOBS_FILE" ]]; then
  printf '{"jobs":[]}\n' > "$JOBS_FILE"
fi

usage() {
  cat <<'EOF'
usage:
  runner.sh [options] [job-id]

options:
  --all         Process all queued jobs sequentially
  -h, --help    Show this help message
EOF
}

process_all=0
target_id=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --all) process_all=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) target_id="$1"; shift ;;
  esac
done

update_job_status() {
  local id="$1"
  local new_status="$2"
  local notes="${3:-}"
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local tmp
  tmp="$(mktemp /tmp/aee-job-upd-XXXXXX.json)"

  jq --arg id "$id" --arg st "$new_status" --arg ts "$ts" --arg notes "$notes" '
    .jobs = [.jobs[] | if .id == $id then . + {status: $st, finishedAt: $ts, notes: $notes} else . end]
  ' "$JOBS_FILE" > "$tmp" && mv "$tmp" "$JOBS_FILE"
}

execute_job() {
  local job_json="$1"
  local j_id j_type ws wi goal inp outp tier eng max_turns max_cost
  j_id="$(jq -r '.id' <<<"$job_json")"
  j_type="$(jq -r '.type' <<<"$job_json")"
  ws="$(jq -r '.workspace // empty' <<<"$job_json")"
  wi="$(jq -r '.workItem // empty' <<<"$job_json")"
  goal="$(jq -r '.goal // empty' <<<"$job_json")"
  inp="$(jq -r '.inputFile // empty' <<<"$job_json")"
  outp="$(jq -r '.outputFile // empty' <<<"$job_json")"
  tier="$(jq -r '.tier // "balanced"' <<<"$job_json")"
  eng="$(jq -r '.engine // empty' <<<"$job_json")"
  max_turns="$(jq -r '.maxTurns // 5' <<<"$job_json")"
  max_cost="$(jq -r '.maxCostUsd // 2.00' <<<"$job_json")"

  printf '=== Running Job %s [%s] (tier: %s, max_turns: %s, max_cost: $%s) ===\n' \
    "$j_id" "$j_type" "$tier" "$max_turns" "$max_cost"
  update_job_status "$j_id" "running" "Execution started"

  local start_time
  start_time="$(date +%s)"
  local exit_code=0

  case "$j_type" in
    study-synthesis)
      local synth_args=(--input "$inp" --tier "$tier")
      [[ -z "$outp" ]] || synth_args+=(--output "$outp")
      [[ -z "$eng" ]] || synth_args+=(--engine "$eng")

      if "$ROOT/platform/routines/synthesize-notes.sh" "${synth_args[@]}"; then
        update_job_status "$j_id" "completed" "Synthesized notes successfully into ${outp:-stdout}"
      else
        exit_code=$?
        update_job_status "$j_id" "failed" "Synthesis failed with exit code $exit_code"
      fi
      ;;
    implementation|*)
      if [[ -z "$ws" || -z "$wi" ]]; then
        update_job_status "$j_id" "failed" "Missing workspace or workItem for implementation job"
        return 1
      fi

      local dispatch_args=("$ws" "$wi" "$goal" --tier "$tier" --foreground)
      [[ -z "$eng" ]] || dispatch_args+=(--engine "$eng")

      if "$ROOT/platform/fleet/dispatch.sh" "${dispatch_args[@]}"; then
        update_job_status "$j_id" "completed" "Implementation turn executed successfully"
      else
        exit_code=$?
        update_job_status "$j_id" "failed" "Implementation turn failed with exit code $exit_code"
      fi
      ;;
  esac

  local elapsed=$(( $(date +%s) - start_time ))
  printf 'Job %s completed in %ss.\n\n' "$j_id" "$elapsed"
}

if [[ -n "$target_id" ]]; then
  target_job="$(jq -c --arg id "$target_id" '.jobs[] | select(.id == $id)' "$JOBS_FILE")"
  [[ -n "$target_job" ]] || { printf 'error: job not found: %s\n' "$target_id" >&2; exit 1; }
  execute_job "$target_job"
elif [[ "$process_all" -eq 1 ]]; then
  while true; do
    next_job="$(jq -c '.jobs[] | select(.status == "queued")' "$JOBS_FILE" | head -n 1)"
    if [[ -z "$next_job" ]]; then
      printf 'All queued jobs processed.\n'
      break
    fi
    execute_job "$next_job"
  done
else
  next_job="$(jq -c '.jobs[] | select(.status == "queued")' "$JOBS_FILE" | head -n 1)"
  if [[ -z "$next_job" ]]; then
    printf 'No jobs currently queued.\n'
  else
    execute_job "$next_job"
  fi
fi
