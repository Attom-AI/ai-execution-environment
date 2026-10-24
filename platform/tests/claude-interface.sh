#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/platform/interfaces/claude/hooks/guard-outbound.sh"

decision() {
  jq -n --arg tool "$1" --arg command "$2" '{tool_name: $tool, tool_input: {command: $command}}' |
    "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

expect_ask() {
  [[ "$(decision Bash "$1")" == ask ]] || { printf 'error: expected approval prompt for: %s\n' "$1" >&2; exit 1; }
}

expect_pass() {
  [[ -z "$(decision "${2:-Bash}" "$1")" ]] || { printf 'error: unexpected approval prompt for: %s\n' "$1" >&2; exit 1; }
}

expect_ask 'git push origin main'
expect_ask 'git -C repos/blog push --force-with-lease'
expect_ask 'cd worktrees/x && git push -u origin HEAD'
expect_ask 'git clone https://github.com/example/repo repos/repo'
expect_ask 'gh pr create --fill'
expect_ask 'gh pr merge 12 --squash'
expect_ask 'gh repo clone example/repo'
expect_ask 'gh -R example/repo pr create --fill'

expect_pass 'git status --short'
expect_pass 'git -C repos/blog fetch --dry-run'
expect_pass 'gh pr view 12'
expect_pass 'gh pr list'
expect_pass 'printf push'
expect_pass 'git push origin main' Read

jq -e '
  (.permissions.deny | index("Read(./.env)") != null) and
  (.permissions.deny | index("Read(./.local/state/**)") != null) and
  (.permissions.deny | index("Edit(./repos/**)") != null) and
  ([.hooks.PreToolUse[].hooks[].command] | any(test("guard-outbound\\.sh")))
' "$ROOT/.claude/settings.json" >/dev/null || { printf 'error: .claude/settings.json is missing required policy\n' >&2; exit 1; }

for skill in "$ROOT"/.agents/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$skill")")"
  cmp -s "$skill" "$ROOT/.claude/skills/$name/SKILL.md" \
    || { printf 'error: .claude skill differs from .agents: %s\n' "$name" >&2; exit 1; }
done

printf 'claude interface tests passed\n'
