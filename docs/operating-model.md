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
5. Add or update a named workspace in `config/workspaces.json` when a recurring
   activity needs a stable repository set.
6. Keep project tooling and instructions in the project repository.
7. Add a tool-specific integration under `workspaces/` only when useful.

Removing an inventory entry does not delete its checkout. Repository deletion
is intentionally a separate, manual operation.

## Workspace lifecycle

Workspace names and repository membership are unique. Every member is a
repository name registered in `config/repos.json`; a workspace may contain a
single repository. Run `make validate` after changing either manifest.

The manifest describes logical membership independently of an editor or agent.
Optional files under `workspaces/` may adapt that membership for a particular
tool, but they do not replace or override `config/workspaces.json`.

## Materialized state

The `main` branch is the portable platform definition. It does not track
`repos/`, `worktrees/`, `state/`, or `scratch/`, including placeholder files.
`make bootstrap` creates those directories when a working environment is
materialized. Their contents remain local and ignored.

The devcontainer CLI may generate `.devcontainer/devcontainer-lock.json` while
building the environment. Portable `main` treats that lock as local generated
output. A personalized working branch may track it when that branch carries
additional Features that need reproducible resolution, as `dev` does for Hugo
and SDKMAN.

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

