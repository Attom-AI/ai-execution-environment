#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
usage:
  compose.sh [options]

options:
  -r, --role <role>           Role persona (e.g. implementation, solution-designer, testing)
  -w, --workspace <ws-id>     Workspace ID
  -i, --work-item <item-id>   Work item ID
  -t, --tier <tier>           Semantic tier: fast, balanced, deep (default: balanced)
      --instruction <text>    User or workflow instruction to append
  -o, --output <file>         File to write composed prompt to (default: stdout)
  -h, --help                  Show this help message
EOF
}

role=""
workspace=""
work_item=""
tier="balanced"
instruction=""
output_file=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -r|--role)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      role="$2"
      shift 2
      ;;
    -w|--workspace)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      workspace="$2"
      shift 2
      ;;
    -i|--work-item)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      work_item="$2"
      shift 2
      ;;
    -t|--tier)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      tier="$2"
      shift 2
      ;;
    --instruction)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      instruction="$2"
      shift 2
      ;;
    -o|--output)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      output_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

[[ -n "$workspace" && -n "$work_item" ]] || { usage >&2; exit 2; }

item_dir="$ROOT/workspaces/$workspace/$work_item"
[[ -d "$item_dir" ]] || { printf 'error: work item directory not found: %s\n' "$item_dir" >&2; exit 1; }

composed_output() {
  printf '# AI Execution Environment Composed Prompt\n\n'
  printf '## Execution Context & Metadata\n'
  printf -- '- **Workspace**: %s\n' "$workspace"
  printf -- '- **Work Item**: %s\n' "$work_item"
  printf -- '- **Semantic Tier**: %s\n' "$tier"
  if [[ -n "$role" ]]; then
    printf -- '- **Active Role**: %s\n' "$role"
  fi
  printf '\n'

  # 1. Base Invariants
  printf '## Platform Invariants & Rules\n'
  printf '1. Work exclusively inside the dedicated worktree assigned to this work item.\n'
  printf '2. Never access credentials or host keys directly; use platform/identity/run.sh.\n'
  printf '3. Never commit directly to canonical repos; all changes remain on task branches.\n'
  printf '4. Operate non-interactively; verify changes with local tests before reporting completion.\n\n'

  # 2. Role Persona if specified
  if [[ -n "$role" ]]; then
    role_file="$ROOT/platform/workflows/agents/${role}.md"
    if [[ -f "$role_file" ]]; then
      printf '## Role Directive: %s\n' "$role"
      cat "$role_file"
      printf '\n\n'
    fi
  fi

  # 3. Ticket Spec
  if [[ -f "$item_dir/ticket.json" ]]; then
    printf '## Work Item Specification\n'
    jq -r '
      "- **Title**: " + (.title // "-"),
      "- **Type**: " + (.type // "-"),
      "- **Key**: " + (.key // "-"),
      "- **URL**: " + (.url // "-"),
      "\n### Acceptance Criteria & Description:\n" + (.body // "No description provided.")
    ' "$item_dir/ticket.json"
    printf '\n\n'
  fi

  # 4. Pipeline State
  if [[ -f "$item_dir/meta.json" ]]; then
    printf '## Pipeline State\n'
    jq -r '
      "- **Lifecycle Stage**: " + (.lifecycleStage // "-"),
      "- **Resume Next Agent**: " + (.resume.nextAgent // "-"),
      "- **Assigned Slot**: " + ((.runtime.poolSlot // "-") | tostring),
      "- **Worktree**: " + (.runtime.worktree // "-"),
      "- **Blocked**: " + (if .blocked.isBlocked then ("yes (" + (.blocked.reason // "unknown") + ")") else "no" end)
    ' "$item_dir/meta.json"
    printf '\n'
  fi

  # 5. Hydrated Active Memory (filtered by tier)
  if [[ -x "$ROOT/platform/context/scripts/hydrate.sh" ]]; then
    hydrated_json="$("$ROOT/platform/context/scripts/hydrate.sh" "$workspace" "$work_item")"
    printf '## Active Memory State\n'
    active_count="$(jq -r '.activeState | length' <<<"$hydrated_json")"
    if [[ "$active_count" -gt 0 ]]; then
      jq -r '.activeState[] | "- **" + .key + "**: " + (.value | tostring)' <<<"$hydrated_json"
    else
      printf '*(No active memory entries in MemTable)*\n'
    fi
    printf '\n'
  fi

  # 6. Session Narrative (Trimming based on tier)
  if [[ -f "$item_dir/session-state.md" ]]; then
    printf '## Session State & Recent Hand-offs\n'
    case "$tier" in
      fast)
        # Fast tier: only last 25 lines
        tail -n 25 "$item_dir/session-state.md"
        ;;
      balanced)
        # Balanced tier: last 80 lines
        tail -n 80 "$item_dir/session-state.md"
        ;;
      deep|*)
        # Deep tier: full session narrative
        cat "$item_dir/session-state.md"
        ;;
    esac
    printf '\n\n'
  fi

  # 7. Explicit Instruction
  if [[ -n "$instruction" ]]; then
    printf '## Current Instruction\n'
    printf '%s\n' "$instruction"
  fi
}

if [[ -n "$output_file" ]]; then
  composed_output > "$output_file"
else
  composed_output
fi
