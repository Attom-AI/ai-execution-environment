# Naming conventions

- Project id: stable inventory key such as `blog`.
- Workspace id: globally stable project container such as `eiakoji-me-blog`.
- Work-item id: normalized source type and number such as `FEAT-12`.
- Workspace path: `workspaces/<workspace-id>/<work-item-id>/`.
- Worktree id: lowercase `<workspace-id>-<work-item-id>`, making the flat path
  globally unique.
- Branch: `<type>/<number>-<title-slug>`, scoped by its independent repository.
- Canonical checkout: the configured relative path below `repos/`.

Names are derived once during intake and persisted in `ticket.json` and
`meta.json`; downstream stages consume them instead of reconstructing them.
