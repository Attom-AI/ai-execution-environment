#!/usr/bin/env bash

# Generate Claude Code subagent wrappers in .claude/agents/ from the
# tool-neutral stage definitions in platform/workflows/agents/.
# With --check, fail instead of writing when the wrappers are stale.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STAGES="$ROOT/platform/workflows/agents"
OUTPUT="$ROOT/.claude/agents"
# The project directory is expanded by Claude Code when the hook runs.
# shellcheck disable=SC2016
HOOKS='"$CLAUDE_PROJECT_DIR"/platform/interfaces/claude/hooks'

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

check=0
case "${1:-}" in
  '') ;;
  --check) check=1 ;;
  *) printf 'usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac

# Per-stage Claude Code policy: description, tool allowlist, writable roots, and
# stage-specific guidance. Every stage definition must have an entry.
# Backticks are literal Markdown in the generated files.
# shellcheck disable=SC2016
stage_policy() {
  handoff=1
  case "$1" in
    ticket-coordinator)
      description='Report a work item'"'"'s pipeline position and recommend the next stage. Drives stages headlessly only when explicitly asked; run as `claude --agent ticket-coordinator` so it can delegate to stage subagents.'
      tools='Agent(issue-refinement, solution-designer, implementation, testing, code-reviewer, pr-creator, pr-maintainer), Read, Grep, Glob, Bash'
      roots='workspaces'
      guidance='Delegate each stage to the subagent named by `resume.nextAgent`, one stage at a time, and re-read `meta.json` after every transition. Never perform stage work yourself.'
      handoff=0
      ;;
    issue-refinement)
      description='Pipeline stage: refine a work item'"'"'s issue into scope, exclusions, and acceptance criteria. Use when `resume.nextAgent` is issue-refinement.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces'
      guidance='Never edit project code.'
      ;;
    solution-designer)
      description='Pipeline stage: produce the design plan for a refined work item. Use when `resume.nextAgent` is solution-designer.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces'
      guidance='Never edit project code.'
      ;;
    implementation)
      description='Pipeline stage: implement and commit a designed work item in its dedicated worktree. Use when `resume.nextAgent` is implementation.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces worktrees'
      guidance='Edit project files only in the worktree recorded in `meta.json` `.runtime.worktree`; never in `repos/`.'
      ;;
    testing)
      description='Pipeline stage: verify an implemented work item and record test results. Use when `resume.nextAgent` is testing.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces worktrees'
      guidance='Add tests only in the worktree recorded in `meta.json` `.runtime.worktree`; never in `repos/`.'
      ;;
    code-reviewer)
      description='Pipeline stage: review a tested work item and record a verdict. Use when `resume.nextAgent` is code-reviewer.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces'
      guidance='Never edit the implementation.'
      ;;
    pr-creator)
      description='Pipeline stage: push a reviewed work item'"'"'s branch and open its pull request. Use when `resume.nextAgent` is pr-creator.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces'
      guidance='Pushing and opening the pull request require operator approval through the outbound guard.'
      ;;
    pr-maintainer)
      description='Pipeline stage: track an open pull request, address feedback, and close the work item when merged or abandoned. Use when `resume.nextAgent` is pr-maintainer.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='workspaces worktrees'
      guidance='Edit project files only in the worktree recorded in `meta.json` `.runtime.worktree`; pushes require operator approval.'
      ;;
    documentation)
      description='On-demand knowledge curator for `documentation/projects/<project>/`. Use when durable project knowledge should be recorded; most invocations correctly make no change.'
      tools='Read, Grep, Glob, Bash, Edit, Write'
      roots='documentation/projects'
      guidance='Edit only the project knowledge base under `documentation/projects/`.'
      handoff=0
      ;;
    *)
      return 1
      ;;
  esac
}

frontmatter_value() {
  sed -n '/^---$/,/^---$/{s/^'"$1"': *//p;}' "$2" | head -n 1
}

render() {
  local stage_file="$1"
  local name role roots_display root
  name="$(frontmatter_value name "$stage_file")"
  role="$(frontmatter_value role "$stage_file")"
  [[ "$name" == "$(basename "$stage_file" .md)" ]] || die "stage name does not match file: $stage_file"
  [[ -n "$role" ]] || die "stage has no role: $stage_file"
  stage_policy "$name" || die "no Claude Code policy for stage: $name (add it to $0)"

  roots_display=''
  for root in $roots; do
    roots_display+="${roots_display:+, }\`$root/\`"
  done

  cat <<EOF
---
name: $name
description: $(jq -n --arg value "$description" '$value')
tools: $(jq -n --arg value "$tools" '$value')
hooks:
  PreToolUse:
    - matcher: "Edit|Write|NotebookEdit"
      hooks:
        - type: command
          command: '$HOOKS/restrict-writes.sh $roots'
---

<!-- Generated by platform/interfaces/claude/generate-agents.sh from
platform/workflows/agents/$name.md. Do not edit; regenerate instead. -->

You are the \`$name\` $role in this execution environment.

Read \`platform/workflows/agents/$name.md\` in full before acting and follow it
exactly. It is the authoritative definition; this file only adapts it to Claude
Code. Follow the root \`AGENTS.md\` and the selected project's own instructions.

EOF
  if [[ "$handoff" -eq 1 ]]; then
    cat <<'EOF'
Read the work item's `meta.json` and `session-state.md` under
`workspaces/<workspace>/<work-item>/` before acting. Before returning, complete
the durable handoff in `platform/state/README.md`: update `meta.json`, overwrite
`session-state.md`, and append `history.log`. Conversation history is never
workflow memory. Never bypass `blocked.isBlocked` or a loop limit.

EOF
  fi
  cat <<EOF
$guidance File edits are limited to $roots_display.

Return a short summary: what changed, the resulting \`lifecycleStage\`, gates,
\`resume.nextAgent\`, and any blocking reason.
EOF
}

generate() {
  local destination="$1"
  local stage_file
  mkdir -p "$destination"
  for stage_file in "$STAGES"/*.md; do
    render "$stage_file" >"$destination/$(basename "$stage_file")"
  done
}

if [[ "$check" -eq 1 ]]; then
  temporary="$(mktemp -d)"
  trap 'rm -rf "$temporary"' EXIT
  generate "$temporary/agents"
  diff -qr "$temporary/agents" "$OUTPUT" >/dev/null 2>&1 \
    || die "Claude Code agents are stale; run platform/interfaces/claude/generate-agents.sh"
  exit 0
fi

rm -rf "$OUTPUT"
generate "$OUTPUT"
printf 'generated %s Claude Code agents in .claude/agents\n' "$(find "$OUTPUT" -name '*.md' -type f | wc -l | tr -d ' ')"
