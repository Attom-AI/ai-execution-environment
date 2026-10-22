# Architecture

## Context

This platform separates personal development from employer and client work. It
also makes the personal environment reproducible without turning independent
projects into a monorepo.

## Layers

### Host

The host owns the VM runtime, SSH client, and encrypted backup destination. It
should not mount work repositories or credentials into the personal VM.

### Personal VM

The VM owns personal source code, personal GitHub authentication, the Docker
engine, and persistent development state. Repository data should live on the
VM's disk rather than a host-shared directory.

### Platform repository

This repository inventories projects and supplies safe administration commands.
It does not own the history, dependencies, or release process of repositories
under `repos/`.

### Devcontainers

The root devcontainer contains cross-project administrative tools. A project
may provide its own devcontainer when it needs a language runtime, database, or
service topology. Open that project directly to use its environment.

### Workspaces

`config/workspaces.json` defines named, tool-neutral sets of managed
repositories. Workspace membership refers to repository names from
`config/repos.json`, keeping identity separate from editor configuration.

Files under `workspaces/` are optional tool-specific integrations, such as VS
Code multi-root workspace files. They may provide focused navigation, but they
are not the workspace source of truth and do not provide security isolation.

## Recovery target

A fresh VM should be recoverable through this sequence:

1. Install SSH access and a Docker engine.
2. Clone this repository.
3. Open it in the root devcontainer.
4. Authenticate the personal GitHub account inside the VM.
5. Run `make repos-clone`.
6. Open a repository or use an optional tool integration for a named workspace.

Secrets, caches, and generated state are intentionally outside this repository
and require a separate backup or re-authentication strategy.

