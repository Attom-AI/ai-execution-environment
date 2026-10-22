# AI execution environment

This repository is a reusable control plane for an isolated development
environment. It keeps independent Git repositories inside a dedicated VM,
provides a generic devcontainer for workspace administration, and offers safe
commands for cloning and inspecting those repositories.

## Agent-first setup

The repository is designed to be handed to a coding agent, agent CLI, or chat
assistant after cloning. The agent should inspect `AGENTS.md`, explain the
available execution modes, verify prerequisites, and guide the operator one
step at a time. Authentication, cloning, and other network actions still
require explicit approval.

A portable starting prompt is:

> Read `AGENTS.md` and `README.md`. Help me set up this workspace. Ask whether I
> want devcontainer isolation or host-native tools, verify the selected mode,
> and guide me step by step. Do not authenticate or clone repositories until I
> approve those actions.

The workflow is agent-independent. Codex, Claude, Gemini, Cursor, an
orchestration layer, or a chat interface can follow the same repository
contract when it can read the workspace and run—or clearly propose—commands.

On `feature/agent-guided-setup`, start with a read-only assessment:

```sh
make setup-plan MODE=devcontainer INTERFACE=cli+herdr PROVIDER=github
```

After reviewing the plan, materialize the selected profile without installing
tools, authenticating, or cloning repositories:

```sh
make setup MODE=devcontainer INTERFACE=cli+herdr PROVIDER=github
```

See `SETUP.md` for the agent and operator walkthrough.

## Execution modes

| Mode | Best fit | Tradeoff |
| --- | --- | --- |
| Devcontainer | Separate toolchains, credentials, or work contexts, including multiple Git identities | Requires Docker and a devcontainer-capable client |
| Host-native | A trusted host with suitable global Git and provider CLI configuration | Shares host tools and credential context |
| Guidance-only | A chat or agent without local command execution | The operator runs each proposed command |

Tool-specific enhancements should be optional profiles layered on this common
contract. For example, a CLI-plus-orchestrator preference can add recommended
commands without making that tool mandatory for every user.

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

## Branch strategy

`main` is the portable, shareable artifact. Setup modes belong on `main` once
they are documented, optional, and verified; permanent branches per tool or
mode would cause the common setup contract to drift. Short-lived feature
branches are used to develop capabilities before merging them.

Personalized manifests and experiments may live on an operator-owned working
branch, while credentials, cloned repositories, generated preferences, and
other materialized state remain ignored. Agent-guided setup is being developed
on `feature/agent-guided-setup` before it is proposed for `main`.

See `docs/operating-model.md` before adding credentials or host mounts.

