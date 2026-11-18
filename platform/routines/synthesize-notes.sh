#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
usage:
  synthesize-notes.sh --input <raw-notes.md> [--output <final-guide.md>] [--tier <tier>] [--engine <engine>]

options:
  -i, --input <file>      Input raw notes, draft, or memo file (required)
  -o, --output <file>     Target output markdown file (default: stdout)
  -t, --tier <tier>       Semantic tier: fast, balanced, deep (default: deep)
  -e, --engine <engine>   Engine to use: claude, agy, gemini, codex (default: auto)
  -h, --help              Show this help message
EOF
}

input_file=""
output_file=""
tier="deep"
engine=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -i|--input) input_file="${2:-}"; shift 2 ;;
    -o|--output) output_file="${2:-}"; shift 2 ;;
    -t|--tier) tier="${2:-deep}"; shift 2 ;;
    -e|--engine) engine="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ -n "$input_file" ]] || { usage >&2; exit 2; }
abs_input="$input_file"
if [[ ! -f "$abs_input" && -f "$ROOT/$input_file" ]]; then
  abs_input="$ROOT/$input_file"
fi
[[ -f "$abs_input" ]] || { printf 'error: input file not found: %s\n' "$input_file" >&2; exit 1; }

temp_prompt="$(mktemp /tmp/aee-synth-prompt-XXXXXX.md)"
cleanup() {
  rm -f "$temp_prompt"
}
trap cleanup EXIT

cat <<'EOF' > "$temp_prompt"
You are an expert Principal Systems Engineer and technical author adhering to first-principles thinking and the "technical-authorial-voice" discipline.

Synthesize the provided raw notes into a rigorous, staff-level technical guide and study drill pack.

Structure the guide as follows:
1. Executive Summary & Core Mechanism (First principles, fundamental trade-offs).
2. Architectural Invariants (What must always hold true, formal safety & liveness guarantees).
3. Failure Modes & Edge Cases (Split-brain, cascade failures, partition behavior, clock skew).
4. Concrete Implementation Trade-Offs (Comparative analysis of algorithms / production systems).
5. Staff-Level Interview Drills & Scenarios (3-5 rigorous questions testing trade-offs under duress).

Guidelines:
- Ground all explanations in mechanics rather than buzzwords.
- Use GitHub Flavored Markdown and Mermaid diagrams where applicable.
- Write with authorial restraint: concise, clear, and mechanism-oriented.
EOF

printf '\n\n---\n### Source Notes (%s):\n\n' "$(basename "$abs_input")" >> "$temp_prompt"
cat "$abs_input" >> "$temp_prompt"

exec_args=(--context "$temp_prompt" "Synthesize these notes into the structured first-principles guide." -t "$tier")
[[ -z "$engine" ]] || exec_args+=(-e "$engine")

if [[ -n "$output_file" ]]; then
  abs_output="$output_file"
  if [[ "$output_file" != /* ]]; then
    abs_output="$ROOT/$output_file"
  fi
  mkdir -p "$(dirname "$abs_output")"
  "$ROOT/platform/agents/exec.sh" "${exec_args[@]}" > "$abs_output"
  printf 'Successfully synthesized notes to: %s\n' "$output_file"
else
  "$ROOT/platform/agents/exec.sh" "${exec_args[@]}"
fi
