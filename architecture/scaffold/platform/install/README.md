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
