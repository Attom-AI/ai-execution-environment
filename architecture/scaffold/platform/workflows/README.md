# Workflows

The stage definitions in `agents/` form this pipeline:

```text
workspace-scaffolder -> issue-refinement -> solution-designer
-> implementation <-> testing <-> code-reviewer
-> pr-creator -> pr-maintainer -> close
```

`ticket-coordinator` is the state-aware entry point. Stage definitions are
runtime-neutral: an agent runtime may import them, but `meta.json` and
`session-state.md` remain the authoritative coordination mechanism.
