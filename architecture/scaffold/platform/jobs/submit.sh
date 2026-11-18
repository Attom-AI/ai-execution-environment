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
  submit.sh [options]

options:
  --type <type>           Job type: study-synthesis, implementation, maintenance (default: implementation)
  --workspace <ws-id>     Workspace ID (optional for study-synthesis)
  --work-item <item-id>   Work item ID (optional for study-synthesis)
  --goal <goal>           Goal or instruction description
  --input <file>          Input file path (e.g. for study notes synthesis)
  --output <file>         Target output file path (e.g. for synthesized doc)
  --tier <tier>           Semantic tier: fast, balanced, deep (default: balanced)
  --engine <engine>       Engine to use: claude, agy, gemini, codex
  --max-turns <n>         Maximum allowed turns before budget capping (default: 5)
  --max-cost <dollars>    Maximum dollar budget cap (default: 2.00)
  --dry-run               Validate and print without registering
  -h, --help              Show this help message
EOF
}

job_type="implementation"
workspace=""
work_item=""
goal=""
input_file=""
output_file=""
tier="balanced"
engine=""
max_turns=5
max_cost="2.00"
dry_run=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --type) job_type="${2:-}"; shift 2 ;;
    --workspace|-w) workspace="${2:-}"; shift 2 ;;
    --work-item|-i) work_item="${2:-}"; shift 2 ;;
    --goal|-g) goal="${2:-}"; shift 2 ;;
    --input) input_file="${2:-}"; shift 2 ;;
    --output) output_file="${2:-}"; shift 2 ;;
    --tier|-t) tier="${2:-}"; shift 2 ;;
    --engine|-e) engine="${2:-}"; shift 2 ;;
    --max-turns) max_turns="${2:-5}"; shift 2 ;;
    --max-cost) max_cost="${2:-2.00}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$workspace" && "$job_type" != "study-synthesis" ]]; then
        workspace="$1"
        shift
      elif [[ -z "$work_item" && "$job_type" != "study-synthesis" ]]; then
        work_item="$1"
        shift
      elif [[ -z "$goal" ]]; then
        goal="$1"
        shift
      else
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ "$job_type" == "study-synthesis" ]]; then
  [[ -n "$input_file" ]] || { printf 'error: --input file is required for study-synthesis jobs\n' >&2; exit 2; }
  [[ -f "$ROOT/$input_file" || -f "$input_file" ]] || { printf 'error: input file not found: %s\n' "$input_file" >&2; exit 1; }
  if [[ -z "$goal" ]]; then
    goal="Synthesize learning notes from $(basename "$input_file")"
  fi
else
  [[ -n "$workspace" && -n "$work_item" ]] || { printf 'error: workspace and work-item are required for %s jobs\n' "$job_type" >&2; exit 2; }
fi

job_id="job-$(date +%Y%m%d%H%M%S)"
ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Dry-run: Job %s [%s] ready for submission (tier: %s, max_turns: %s, max_cost: $%s)\n' \
    "$job_id" "$job_type" "$tier" "$max_turns" "$max_cost"
  exit 0
fi

tmp="$(mktemp /tmp/aee-job-XXXXXX.json)"
jq --arg id "$job_id" \
   --arg jt "$job_type" \
   --arg ws "$workspace" \
   --arg wi "$work_item" \
   --arg goal "$goal" \
   --arg inp "$input_file" \
   --arg outp "$output_file" \
   --arg tr "$tier" \
   --arg eng "$engine" \
   --argjson turns "$max_turns" \
   --argjson cost "$max_cost" \
   --arg ts "$ts" '
  .jobs += [{
    id: $id,
    type: $jt,
    workspace: $ws,
    workItem: $wi,
    goal: $goal,
    inputFile: $inp,
    outputFile: $outp,
    tier: $tr,
    engine: $eng,
    maxTurns: $turns,
    maxCostUsd: $cost,
    status: "queued",
    createdAt: $ts
  }]
' "$JOBS_FILE" > "$tmp" && mv "$tmp" "$JOBS_FILE"

printf 'Job submitted successfully: %s [%s]\n' "$job_id" "$job_type"
printf '  Goal:   %s\n' "$goal"
printf '  Tier:   %s (engine: %s)\n' "$tier" "${engine:-auto}"
printf '  Budget: max %s turns, $%s limit\n' "$max_turns" "$max_cost"
printf 'Run "aee job run" to process queued jobs, or check "aee morning" for summaries.\n'
