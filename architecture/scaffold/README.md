# AI execution environment

An issue-driven execution platform for independent projects. Canonical clones
live under `repos/`; persistent work-item state lives under project-specific
workspace containers; each active Git worktree gets an exclusive container
from a bounded runtime pool; disposable worktrees remain flat under
`worktrees/`.

```text
repos/blog/                                     canonical clone
workspaces/eiakoji-me-blog/FEAT-12/            persistent work item
worktrees/eiakoji-me-blog-feat-12/              disposable checkout
```

Run `./platform/install/install.sh` to create ignored instance directories and
seed `.env`. Register projects in `config/projects.json`, then create or resume
work through `platform/workspace-scaffolder/` and `platform/runtime/scripts/`.
Executable infrastructure is under `platform/`; the synchronized portable
blueprint is under `architecture/`.
