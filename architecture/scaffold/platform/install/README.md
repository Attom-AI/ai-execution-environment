# Installation

`setup.sh plan` previews an agent-guided setup profile without changing the
environment. Profiles select `devcontainer`, `host`, or read-only `guidance`
execution and record the preferred Git provider and agent interface.

`setup.sh apply` delegates instance initialization to `install.sh`, then saves
the confirmed preferences under ignored `.local/state/setup/`. `install.sh`
creates ignored instance directories, seeds `.env` from
`templates/.env.example` without overwriting it, reports dependency and auth
status, and validates tracked infrastructure.

Neither command authenticates, installs global tools, clones repositories,
changes remotes, or starts work-item runtimes.

## Global CLI & Directory Awareness

The workspace root is anchored by `aee-workspace.yaml`. The CLI binary (`bin/aee`)
searches upward from the current working directory to locate this file, resolving
the root and active worktree context, and fails fast outside an `aee` workspace.

To make `aee` globally available, create a symlink in your user binary directory:

```sh
mkdir -p ~/.local/bin
ln -sf "$(pwd)/bin/aee" ~/.local/bin/aee
```

Do not use a shell alias (`alias aee=...`), as aliases do not adapt dynamically
to the working directory or support multiple workspaces.
