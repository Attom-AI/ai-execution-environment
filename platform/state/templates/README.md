# ${WORK_ITEM}

**${TITLE}**

- Source: ${SOURCE} — ${URL}
- Worktree: `${WORKTREE}` while the runtime is active

## Files

- `ticket.json`: normalized intake plus the source payload under `raw`
- `meta.json`: lifecycle gates, loop counters, resume pointer, and runtime state
- `session-state.md`: overwritten narrative checkpoint
- `history.log`: append-only transition history
- `artifacts/`: stage handoff artifacts
