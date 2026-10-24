# Interfaces

Adapters that bind a specific agent interface to the tool-neutral platform.
Adapters enforce or expose existing policy; they never redefine workflow stages
or state.

- `claude/hooks/guard-outbound.sh`: Claude Code `PreToolUse` hook, registered in
  `.claude/settings.json`, that requires operator approval before cloning,
  pushing, or creating or merging a pull request.
