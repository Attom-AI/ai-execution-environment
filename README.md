# AI execution environment

An issue-driven execution platform for independent projects. Canonical clones
live under `repos/`; persistent work-item state lives under project-specific
workspace containers; disposable Git worktrees remain flat under `worktrees/`.

```text
repos/blog/                                     canonical clone
workspaces/eiakoji-me-blog/FEAT-12/            persistent work item
worktrees/eiakoji-me-blog-feat-12/              disposable checkout
```

Start agent-guided setup with a read-only plan:

```bash
./platform/install/setup.sh plan --mode devcontainer --provider github --interface codex
```

After reviewing the trust and credential implications, materialize the selected
profile with `setup.sh apply`. This creates ignored local state but never
authenticates, clones repositories, or changes Git remotes.

Register projects in `config/projects.json`, then create or resume work through
`platform/workspace-scaffolder/` and `platform/runtime/scripts/`. Executable
infrastructure is under `platform/`; the synchronized portable blueprint is
under `architecture/`.
