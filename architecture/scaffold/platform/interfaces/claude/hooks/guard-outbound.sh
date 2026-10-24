#!/usr/bin/env bash

# Claude Code PreToolUse hook: require operator approval before a Bash command
# clones, pushes, or creates or merges a pull request.

set -euo pipefail

ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"jq is unavailable; outbound command guard cannot inspect this command"}}\n'
  exit 0
fi

input="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)"
[[ "$tool_name" == Bash ]] || exit 0
command_text="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)"
[[ -n "$command_text" ]] || exit 0

# Matching is deliberately broad: a false positive only asks for approval.
if grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]([^;&|]*[[:space:]])?(push|clone)([[:space:]]|$)' <<<"$command_text"; then
  ask "AGENTS.md: cloning and pushing require explicit operator approval"
elif grep -Eq '(^|[^[:alnum:]_-])gh[[:space:]]([^;&|]*[[:space:]])?(repo[[:space:]]+clone|pr[[:space:]]+(create|merge))([[:space:]]|$)' <<<"$command_text"; then
  ask "AGENTS.md: cloning and pull-request publication require explicit operator approval"
fi
