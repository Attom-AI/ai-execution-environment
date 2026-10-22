# AI execution environment

## Purpose

This repository is an agentic execution platform for issue-driven work across
independent personal projects. It is a workspace control plane, not an
application monorepo.

## Boundaries

- Treat every checkout under `repos/` as an independent Git repository.
- Never add files from `repos/`, `workspaces/`, `worktrees/`, `.local/`, or
  `.env` to this repository.
- Keep code, credentials, and data outside this workspace when they belong to a
  different trust domain than the one selected by the workspace operator.
- Do not clone, fetch, push, publish, deploy, or authenticate unless the user
  requests it or the command is the explicit subject of the task.
- Do not store credentials in tracked files. Use VM-local credential storage or
  the relevant authenticated CLI.

## Working conventions

- `config/projects.json` maps each project to one canonical checkout, one
  project-specific workspace, and one issue source.
- Canonical repository paths must remain below `repos/`.
- Work items live directly under `workspaces/<workspace-id>/<work-item-id>/`.
- Worktrees are flat, disposable, and direct children of `worktrees/`.
- Persistent work-item state must survive worktree and runtime disposal.
- Executable infrastructure belongs under `platform/`.
- `architecture/` is the portable blueprint and must stay synchronized with the
  generic tracked implementation.
- Run `./platform/validate.sh` after platform changes.

## Verification

- Shell scripts must pass `bash -n` and ShellCheck.
- JSON files must parse successfully.
- Repository-management commands must not rewrite canonical checkouts.
- Bulk operations must report the repository they are acting on and fail
  visibly rather than hiding errors.

Project-specific instructions belong in each project's own `AGENTS.md`.
Operator-wide rules belong in `~/.codex/AGENTS.md` inside the VM because nested
repositories have their own repository roots.

