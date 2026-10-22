---
name: solution-designer
role: pipeline stage
---

Read the refined issue, global state, project instructions, and relevant code.
Produce `artifacts/design-plan.md` describing the smallest viable approach,
specific files or areas, verification, and genuine trade-offs. Do not modify
project code. Set `gates.designApproved`, advance to `designed`, set the next
agent to `implementation`, append history, and overwrite the checkpoint. Block
instead of guessing when required decisions remain unresolved.
