# Identity model

An operator may hold several accounts with one provider and use several
providers (GitHub, GitLab, Bitbucket, SVN) on one machine. Every Git and provider
operation therefore runs under an explicit, named identity profile instead of
whatever the host happens to provide: `~/.ssh`, the SSH agent, the keychain, or
the active global CLI login.

## Binding

`config/projects.json` names a profile and holds no secrets:
`repository.identity` for repository operations, and optionally
`issues.identity` when the issue source uses a different account. When
`issues.identity` is absent, the repository identity is used. A project without
an identity fails visibly; nothing falls back to host credentials.

The scaffolder records both identities in the work item's `meta.json`
(`identity.repository`, `identity.issues`). Every stage reads the identity from
durable state. If the project later changes identity, commands for that work
item fail as drift until the operator resolves it.

## Profiles and modes

Profiles live in ignored host-local state: `.local/state/identities.json`
declares each profile, and `.local/state/identities/<id>/` (mode `0700`) holds
an isolated profile's material: `gh/`, `glab/`, `git/config`,
`git/credentials`, `ssh/`, `svn/`.

- `isolated`: only the profile directory is used. Git system and global
  configuration, the keychain credential helper, inherited provider tokens
  (`GH_TOKEN`, `GITLAB_TOKEN`, and similar), the SSH agent, and `~/.ssh` are
  excluded. Git credentials come from `gh` or `glab` for their hosts and from the
  profile's credential store elsewhere. SSH uses only the profile's `id_*` keys
  and verifies host keys strictly against the profile's `known_hosts`. Commit
  name and email come from the profile.
- `host`: host credentials are used deliberately, for example for hardware keys
  or a password-manager SSH agent. The mode is declared per profile and its
  consequence is shown during setup. Runtime containers receive no credentials
  for host-mode identities.

Containers cannot reach the system keyring, so isolated profiles keep tokens in
files (for example `gh auth login --insecure-storage`). Profiles that cannot
accept tokens at rest use host mode and stay on the host.

Git settings are applied with `GIT_CONFIG_COUNT` environment entries rather
than a written configuration file, so the same profile produces correct paths
both on the host and at its container mount point.

## Enforcement

- On the host, `platform/identity/run.sh` resolves the identity for a work item,
  project, or profile and runs the command under it. Repository adapters,
  intake, and pull-request stages use it; agent skills direct agents to it, and
  the Claude Code outbound guard asks with a specific reason when an outbound
  command bypasses it.
- In a runtime container, `start.sh` mounts only the work item's profile at
  `/home/vscode/.identity` and sets the matching environment. There is no other
  identity to choose. A container keeps the identity it was created with;
  starting it under a different identity fails until it is recreated.
- Before `git push`, `gh pr create|merge`, or `glab mr create|merge` (including
  forms with global flags such as `gh -R <repo> pr create`), `run.sh` verifies
  that the profile authenticates as its declared `account`. This catches
  mistakes, not deliberate bypasses such as raw API calls; profile isolation is
  what bounds those.
- Verification also fails when a project's remote URL disagrees with the
  identity's declared transport (an HTTPS remote under an `ssh` identity, or the
  reverse), rather than probing the wrong host.

Verification never logs in or switches accounts. A mismatch fails and names
both accounts.

## Limits

- SVN credentials can be held in a profile (`IDENTITY_SVN_CONFIG_DIR` for
  `svn --config-dir`), but worktrees, branches, pull requests, and runtimes are
  Git-only. SVN projects need their own provider adapter and runtime model.
- Credential helpers are preset for `github.com` and `gitlab.com`. Self-hosted
  hosts use the profile's credential store.
- On the host, routing commands through `run.sh` depends on agents following
  their instructions, with interface hooks as a backstop. Containers enforce it
  structurally.
