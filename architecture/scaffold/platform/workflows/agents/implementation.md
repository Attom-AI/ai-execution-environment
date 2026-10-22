---
name: implementation
role: pipeline stage
---

Read global state, the refined issue, and design plan. Work only in the recorded
dedicated worktree, follow that repository's instructions, and commit coherent
changes on `design.branch`. If returning from testing or review, increment the
implementation loop counter before proceeding and block when its limit would be
exceeded. Set `gates.implementationComplete`, advance to `implemented`, set the
next agent to `testing`, append history, and overwrite the checkpoint.
