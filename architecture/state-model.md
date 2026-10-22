# State model

Each `workspaces/<workspace>/<work-item>/` contains:

- `issue.json`: immutable intake snapshot
- `meta.json`: lifecycle and runtime pointers
- `session-state.md`: resumable working memory
- `history.log`: append-only lifecycle notes
- `artifacts/`: outputs that belong to the work item rather than the project

Project deliverables are written to the dedicated worktree and committed to
the independent repository.
