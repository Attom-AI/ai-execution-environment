# Pipeline and agents

```text
workspace-scaffolder -> issue-refinement -> solution-designer
-> implementation <-> testing <-> code-reviewer
-> pr-creator -> pr-maintainer -> close
```

The tool-neutral definitions are under `platform/workflows/agents/`, and
assistant skills are provided under `.codex/skills/` (for Codex) and
`.agents/skills/` (for Antigravity / `agy`). The coordinator is not a stage: it
reads persistent state, reports the current position, and advances only when
explicitly asked to run headlessly.

Each stage has one bounded responsibility and one durable output. Refinement
produces scope and acceptance criteria; design produces an executable plan;
implementation commits project changes; testing records verification; review
records a verdict; PR stages publish and maintain the change. Failed testing or
review returns to implementation through bounded loop counters. Reaching a
limit blocks the item for human intervention rather than looping indefinitely.

Every handoff updates global state and the narrative checkpoint. Conversation
history is never treated as workflow memory.
