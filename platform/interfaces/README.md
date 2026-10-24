# Interfaces

Adapters that bind a specific agent interface to the tool-neutral platform.
Adapters enforce or expose existing policy; they never redefine workflow stages
or state.

- `claude/hooks/guard-outbound.sh`: Claude Code `PreToolUse` hook, registered in
  `.claude/settings.json`, that requires operator approval before cloning,
  pushing, or creating or merging a pull request.
- `claude/generate-agents.sh`: generates the `.claude/agents/` subagent wrappers
  from `platform/workflows/agents/`. Each wrapper points to its stage definition
  rather than copying it. The script holds the per-stage policy (description,
  tool allowlist, writable roots); a new stage definition fails generation until
  it has a policy entry. Run it after changing a stage definition;
  `validate.sh` fails when the wrappers are stale.
- `claude/hooks/restrict-writes.sh <root>...`: subagent-scoped `PreToolUse`
  hook that denies file edits outside the given workspace-relative roots,
  rejecting path traversal and symlink escapes. Refinement, design, and review
  stages may edit only `workspaces/`. Implementation, testing, and PR
  maintenance may also edit `worktrees/`. Documentation may edit only
  `documentation/projects/`.

Run `claude --agent ticket-coordinator` to start a session as the coordinator.
It can delegate only to the pipeline-stage subagents and never edits files
itself.
