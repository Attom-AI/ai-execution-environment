# Eiakoji personal workspace

This repository is the control plane for a personal development environment.
It keeps personal GitHub repositories inside an isolated VM, provides a generic
devcontainer for workspace administration, and offers safe commands for cloning
and inspecting those repositories.

## Architecture

```text
host
└── personal Linux VM
    └── this repository
        └── root devcontainer
            └── repos/* (independent Git repositories)
```

The VM is the identity and data-isolation boundary. The root devcontainer is a
reproducible toolbox, not a replacement for project-specific devcontainers.
It includes Hugo for blog development and SDKMAN for managing JVM tooling.

## Quick start

1. Clone this repository inside the personal VM.
2. Connect to the VM with VS Code Remote SSH.
3. Open this directory and choose **Reopen in Container**.
4. Add personal repositories to `config/repos.json` and recurring repository
   groupings to `config/workspaces.json`.
5. Run `make validate`, then `make repos-clone` and `make repos-status` when
   network operations are intended.

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
- `repos/`: ignored independent repository checkouts
- `scripts/`: safe workspace administration commands
- `state/`: ignored generated local state
- `scratch/`: ignored disposable experiments
- `templates/`: starting points copied into individual repositories
- `workspaces/`: optional tool-specific integrations derived from the workspace
  manifest
- `worktrees/`: ignored temporary Git worktrees

`config/workspaces.json` is the tool-neutral source of truth for named groups of
managed repositories. A workspace can contain one or more repositories; editor
files under `workspaces/` are optional conveniences and are not authoritative.

See `docs/operating-model.md` before adding credentials or host mounts.

