@AGENTS.md

## Claude Code

- Use the `work-item-execution` skill to inspect or drive a work item, and the
  `repository-onboarding` skill to register a repository. Both live under
  `.claude/skills/` and must stay identical to `.agents/skills/`.
- `.claude/settings.json` enforces the boundaries above: credentials and
  canonical checkouts are protected, and outbound Git and pull-request commands
  require approval through `platform/interfaces/claude/hooks/`.
- Operator-wide Claude Code rules belong in `~/.claude/CLAUDE.md` inside the VM.
