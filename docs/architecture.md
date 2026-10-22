# Architecture

## Context

This platform isolates one development trust domain from others and makes its
environment reproducible without turning independent projects into a monorepo.

## Layers

### Host

The host owns the VM runtime, SSH client, and encrypted backup destination. It
should not mount repositories or credentials from other trust domains into the
workspace VM.

### Workspace VM

The VM owns the selected source repositories, their GitHub authentication, the
Docker engine, and persistent development state. Repository data should live
on the VM's disk rather than a host-shared directory.

### Platform repository

This repository inventories projects and supplies safe administration commands.
It does not own the history, dependencies, or release process of repositories
under `repos/`.

The `main` branch contains only the portable platform definition. Runtime
directories and tool-generated files are materialized locally and ignored.

### Devcontainers

The root devcontainer contains cross-project administrative tools. A project
may provide its own devcontainer when it needs a language runtime, database, or
service topology. Open that project directly to use its environment.

### Workspaces

Each ignored `workspaces/<work-item>/` directory organizes one activity. Its
internal structure is deliberately unconstrained and may include notes,
references, generated artifacts, or local editor configuration. Workspaces are
organizational boundaries, not security boundaries or source repositories.

Editor-specific files such as `.code-workspace` may be generated inside a work
item when useful, but they are not part of the portable platform definition.

## Recovery target

A fresh VM should be recoverable through this sequence:

1. Install SSH access and a Docker engine.
2. Clone this repository.
3. Open it in the root devcontainer.
4. Run `make bootstrap` (the devcontainer does this automatically on creation).
5. Authenticate the intended GitHub identity inside the VM.
6. Run `make repos-clone`.
7. Create a work-item folder under `workspaces/` when an activity needs one.
8. Open the relevant work-item folder or repository.

Secrets, caches, and generated state are intentionally outside this repository
and require a separate backup or re-authentication strategy.

