---
name: work-item-execution
description: Resume, inspect, or drive a spec-driven work item in this execution environment using its persistent state and pipeline-stage contracts. Use for project work-item execution; do not use for unrelated repository tasks.
---

# Work item execution

Treat the work item's files as authoritative memory rather than relying on the
conversation.

1. Read the root `AGENTS.md`, the work item's `meta.json` and
   `session-state.md`, and the selected project's own instructions. Hydrate the
   active session context partition when needed with
   `platform/context/scripts/hydrate.sh`.
2. Report `lifecycleStage`, unmet gates, blocking state, loop counters, runtime
   state, and `resume.nextAgent` when the user asks for status or guidance.
3. If the user asks to execute or continue the work, read the complete matching
   definition under `platform/workflows/agents/` and follow it. Do not load
   unrelated stage definitions.
4. Start or resume the dedicated runtime with
   `platform/runtime/scripts/start.sh` when project changes require a worktree.
   Never implement in the canonical checkout under `repos/`.
5. Run every Git, `gh`, `glab`, or other provider command for the work item
   through `platform/identity/run.sh <workspace> <work-item> -- <command>`
   (add `--issues` for issue-source commands) so the identity recorded in
   `meta.json` is used. Never switch accounts, log in, or fall back to host
   credentials; report an identity failure instead.
6. Use `platform/context/scripts/append.sh`, `compact.sh`, and
   `snapshot.sh switch` to maintain the active L0/L1/L2/L3 session context
   window and switch cleanly between topic partitions.
7. Before handing off, update `meta.json`, overwrite `session-state.md`, and
   append `history.log` as required by `platform/state/README.md`.

Default to one human-approved stage at a time. Drive stages headlessly only when
the user explicitly requests end-to-end execution. Never bypass a blocked state
or a loop limit. Cloning, fetching, pushing, opening or updating pull requests,
and starting containers remain subject to the authority in the root
`AGENTS.md` and the user's request.
