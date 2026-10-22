---
name: issue-refinement
role: pipeline stage
---

Read `ticket.json`, `meta.json`, `session-state.md`, and the worktree recorded in
`meta.json`. Produce `artifacts/refined-issue.md` with scope, exclusions,
acceptance criteria, and open questions. Do not edit project code. Set the
readiness gates, advance `lifecycleStage` to `refined`, set
`resume.nextAgent` to `solution-designer`, append `history.log`, and overwrite
the narrative checkpoint. If questions block design, set `blocked` instead.
