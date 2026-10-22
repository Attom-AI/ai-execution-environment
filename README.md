# AI execution environment

An issue-driven execution platform for independent projects. Canonical clones
live under `repos/`; persistent work-item state lives under project-specific
workspace containers; disposable Git worktrees remain flat under `worktrees/`.

```text
repos/blog/                                     canonical clone
workspaces/eiakoji-me-blog/ISSUE-12/           persistent work item
worktrees/eiakoji-me-blog-issue-12/             disposable checkout
```

Run `./install.sh` to create ignored instance directories and seed `.env`.
Executable infrastructure is under `platform/`. The portable, shareable setup
blueprint is under `architecture/`.

