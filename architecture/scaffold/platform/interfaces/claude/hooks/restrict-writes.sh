#!/usr/bin/env bash

# Claude Code PreToolUse hook for file-editing tools: deny writes outside the
# workspace-relative roots passed as arguments, e.g. `restrict-writes.sh workspaces`.

set -euo pipefail

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(jq -Rn --arg reason "$1" '$reason')"
  exit 0
}

command -v jq >/dev/null 2>&1 || {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq is unavailable; write restriction cannot inspect this edit"}}\n'
  exit 0
}
[[ "$#" -gt 0 ]] || deny "restrict-writes.sh was registered without allowed roots"

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
root="$(cd "$root" && pwd -P)"

input="$(cat)"
target="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null || true)"
[[ -n "$target" ]] || exit 0
[[ "$target" == /* ]] || target="$root/$target"
[[ "/$target/" != */../* ]] || deny "path traversal is not allowed: $target"
[[ ! -L "$target" ]] || deny "symlinked files are not editable by pipeline stages: $target"

# Resolve symlinks through the nearest existing ancestor so links cannot escape a root.
existing="$target"
remainder=''
while [[ ! -d "$existing" ]]; do
  remainder="/$(basename "$existing")$remainder"
  existing="$(dirname "$existing")"
done
resolved="$(cd "$existing" && pwd -P)$remainder"

for allowed in "$@"; do
  [[ "$resolved" == "$root/${allowed%/}/"* ]] && exit 0
done
deny "this stage may only edit files under: $*"
