@AGENTS.md

## Claude Code

- Use the `work-item-execution` skill to inspect or drive a work item, and the
  `repository-onboarding` skill to register a repository. Both live under
  `.claude/skills/` and must stay identical to `.agents/skills/`.
- `.claude/settings.json` enforces the boundaries above: credentials and
  canonical checkouts are protected, and outbound Git and pull-request commands
  require approval through `platform/interfaces/claude/hooks/`.
- Pipeline stages are available as subagents in `.claude/agents/`, generated
  from `platform/workflows/agents/` by
  `platform/interfaces/claude/generate-agents.sh`. Never edit them by hand.
  Start a coordinator session with `claude --agent ticket-coordinator`.
- Operator-wide Claude Code rules belong in `~/.claude/CLAUDE.md` inside the VM.
