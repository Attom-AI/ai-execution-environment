# AI execution environment

This repository is a reusable control plane for an isolated development
environment. It keeps independent Git repositories inside a dedicated VM,
provides a generic devcontainer for workspace administration, and offers safe
commands for cloning and inspecting those repositories.

## Architecture

```text
host
└── isolated Linux VM
    └── this repository
        └── root devcontainer
            └── repos/* (independent Git repositories)
```

The VM is the identity and data-isolation boundary. The root devcontainer is a
reproducible toolbox, not a replacement for project-specific devcontainers.

## Quick start

1. Clone this repository inside the workspace VM.
2. Connect to the VM with VS Code Remote SSH.
3. Open this directory and choose **Reopen in Container**.
4. Let the devcontainer run `make bootstrap` to materialize local directories.
5. Add repositories for the selected trust domain to `config/repos.json`.
6. Run `make repos-clone` and then `make repos-status`.

Useful commands:

```sh
make help
make doctor
make validate
make repos-clone
make repos-status
make repos-fetch
```

`repos-fetch` only fetches remote refs. It never merges, rebases, resets, or
changes a checked-out branch.

## Directory ownership

- `.devcontainer/`: generic workspace administration environment
- `config/`: tracked declarative configuration
- `docs/`: architecture, operating model, and decisions
- `infra/vm/`: VM provisioning documentation and future automation
- `repos/`: materialized, ignored independent repository checkouts
- `scripts/`: safe workspace administration commands
- `state/`: materialized, ignored generated local state
- `scratch/`: materialized, ignored disposable experiments
- `templates/`: starting points copied into individual repositories
- `workspaces/`: focused VS Code multi-root workspace definitions
- `worktrees/`: materialized, ignored temporary Git worktrees

The materialized directories are intentionally absent from the `main` tree.
Run `make bootstrap` to create them. The devcontainer CLI may also generate
`.devcontainer/devcontainer-lock.json`; it is local output and is not committed.

See `docs/operating-model.md` before adding credentials or host mounts.

