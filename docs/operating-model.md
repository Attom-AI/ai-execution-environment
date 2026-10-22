# Operating model

## Trust boundary

Choose one trust domain for each materialized environment. Only repositories,
credentials, content, and artifacts in that domain belong in the workspace. Do
not attach out-of-scope folders to the VM or root devcontainer.

## Repository lifecycle

1. Run `make bootstrap` when materializing a fresh workspace.
2. Add an entry to `config/repos.json`.
3. Run `make validate`.
4. Run `make repos-clone`.
5. Add a focused workspace definition only when multiple repositories need to
   be opened together.
6. Keep project tooling and instructions in the project repository.

Removing an inventory entry does not delete its checkout. Repository deletion
is intentionally a separate, manual operation.

## Materialized state

The `main` branch is the portable platform definition. It does not track
`repos/`, `worktrees/`, `state/`, or `scratch/`, including placeholder files.
`make bootstrap` creates those directories when a working environment is
materialized. Their contents remain local and ignored.

The devcontainer CLI may generate `.devcontainer/devcontainer-lock.json` while
building the environment. Treat that lock as local generated output; rebuild
the container to regenerate it.

## Credentials

- Authenticate GitHub inside the VM using the intended, narrowly scoped
  identity.
- Do not commit tokens, SSH keys, credential files, or exported environment
  variables.
- Avoid host SSH-agent forwarding unless its risks and scope are understood.
- Prefer re-authentication over copying host credential stores into the VM.

## Bulk operations

Platform commands may clone, inspect, and fetch repositories. They must not
merge, rebase, reset, clean, switch branches, push, or delete files across
repositories.

## Backups

Back up the encrypted VM disk or the irreplaceable VM-local data separately.
Treat cloned repositories and tool installations as reproducible. Periodically
test the recovery sequence documented in `docs/architecture.md`.

