# AI execution environment

## Purpose

This repository is a reusable control plane for an isolated development
environment. It inventories independent repositories, provides a shared
devcontainer, and documents the VM and workspace operating model. It is not an
application monorepo.

## Boundaries

- Treat every checkout under `repos/` as an independent Git repository.
- Never add files from `repos/`, `worktrees/`, `state/`, or `scratch/` to this
  repository.
- Keep code, credentials, and data outside this workspace when they belong to a
  different trust domain than the one selected by the workspace operator.
- Do not clone, fetch, push, publish, deploy, or authenticate unless the user
  requests it or the command is the explicit subject of the task.
- Do not store credentials in tracked files. Use VM-local credential storage or
  the relevant authenticated CLI.

## Working conventions

- `config/repos.json` is the source of truth for managed repository locations.
- Managed repository paths must be relative, remain below `repos/`, and contain
  no `.` or `..` path segments.
- Prefer the commands exposed by `make`; run `make validate` after platform
  changes.
- Keep the root devcontainer generic. Language and application dependencies
  belong in the individual project repositories.
- Record architectural decisions that materially change the operating model in
  `docs/decisions/`.

## Verification

- Shell scripts must pass `bash -n` and ShellCheck.
- JSON files must parse successfully.
- Repository-management commands must not rewrite branches or working trees.
- Bulk operations must report the repository they are acting on and fail
  visibly rather than hiding errors.

Project-specific instructions belong in each project's own `AGENTS.md`.
Operator-wide rules belong in `~/.codex/AGENTS.md` inside the VM because nested
repositories have their own repository roots.

