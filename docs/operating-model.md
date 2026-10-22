# Operating model

## Personal boundary

Only personal repositories, credentials, content, and artifacts belong in this
environment. Do not attach employer or client folders to the VM or the root
devcontainer.

## Repository lifecycle

1. Add an entry to `config/repos.json`.
2. Run `make validate`.
3. Run `make repos-clone`.
4. Add a focused workspace definition only when multiple repositories need to
   be opened together.
5. Keep project tooling and instructions in the project repository.

Removing an inventory entry does not delete its checkout. Repository deletion
is intentionally a separate, manual operation.

## Credentials

- Authenticate GitHub inside the VM using a personal, narrowly scoped identity.
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

