# Directory layout

The root separates reusable control-plane material from local execution data.

| Path | Responsibility | Persistence |
| --- | --- | --- |
| `architecture/` | Shareable design contract and synchronized scaffold | tracked |
| `backlog/` | Deferred platform work and open design decisions | tracked |
| `config/` | Project, workspace, repository, and provider inventory | tracked |
| `documentation/` | Infrastructure references and compact project knowledge | tracked |
| `platform/` | Installer, intake, state, runtime, and workflow engine | tracked |
| `repos/` | Canonical independent Git repositories | local, ignored |
| `workspaces/` | Durable project-specific work-item records | local, ignored |
| `worktrees/` | Flat disposable Git worktrees | local, ignored |
| `.local/` | Host-local credentials and runtime support state | local, ignored |
| `.env` | Operator-selected local configuration | local, ignored |

`repos/`, `workspaces/`, and `worktrees/` are intentionally separate. A
canonical checkout can be used independently by a human. A work item retains
state after its worktree and container are destroyed. No project source or
work-item data is tracked by this control-plane repository.
