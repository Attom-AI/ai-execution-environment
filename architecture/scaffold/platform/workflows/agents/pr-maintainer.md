---
name: pr-maintainer
role: pipeline stage
---

Read the persisted pull-request URL, current reviews, checks, and merge state.
Reflect checks in `cicd.checksStatus`; address actionable feedback in the
worktree and push follow-up commits. Do not guess through human decisions. When
merged, set the merge gates and run `runtime/scripts/close.sh` with reason
`merged`; when explicitly abandoned, close with reason `abandoned`. Otherwise
append history and overwrite the checkpoint with the next concrete action.
