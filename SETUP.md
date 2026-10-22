# Agent-guided setup

This document is the stable handoff point for a coding agent, agent CLI,
orchestration layer, or chat assistant. The setup flow is deliberately
vendor-neutral and separates local materialization from authentication and
repository cloning.

## 1. Establish the trust domain

The operator should name the work context this environment will contain. Do not
mix repositories, credentials, or artifacts from another trust domain merely
because they are available on the host.

## 2. Choose an execution mode

- `devcontainer`: use when toolchains or credentials need isolation, including
  when the operator switches among multiple accounts for the same Git provider.
- `host`: use when the host is trusted and its global Git configuration,
  credential helpers, and provider CLIs are intentionally shared.
- `guidance`: use when the agent cannot execute local commands. The agent
  explains each command and waits for the operator to run it.

An agent must ask before choosing between `devcontainer` and `host` unless the
operator has already stated a preference. `auto` is convenient for direct CLI
use, but it is not a substitute for discussing credential scope.

## 3. Record preferences and inspect the plan

`MODE`, `INTERFACE`, and `PROVIDER` select the setup profile. `INTERFACE` is a
free-form label such as `codex-cli`, `cursor`, or `cli+herdr`. Supported provider
recommendations are `github`, `gitlab`, `bitbucket`, `git`, and `none`.

```sh
make setup-plan MODE=devcontainer INTERFACE=cli+herdr PROVIDER=github
```

The plan is read-only. It reports the execution context, available commands,
and the next approval boundaries.

## 4. Materialize the profile

For devcontainer mode, first open the repository in a devcontainer-capable
client or run this on the host:

```sh
devcontainer up --workspace-folder .
```

Then run the apply step inside the devcontainer. For host mode, run it directly
on the host:

```sh
make setup MODE=devcontainer INTERFACE=cli+herdr PROVIDER=github
```

The apply step creates ignored runtime directories, validates the workspace,
and writes the selected preferences to `state/setup/preferences.json`. It does
not install tools, authenticate accounts, clone repositories, or modify Git
remotes.

Inspect the saved selection with:

```sh
make setup-status
```

## 5. Configure identity and authentication

Treat these as separate, explicit actions after setup:

1. Confirm the intended Git author name and email for this trust domain.
2. Choose HTTPS credential helpers or SSH keys.
3. Authenticate the selected provider with its CLI when desired.
4. Verify the active account before cloning or pushing.

For host mode, existing global configuration may be reused intentionally. For
devcontainer mode, configure identity and provider authentication inside the
container or its persistent local state so another work context is not reused
accidentally.

## 6. Register and clone repositories

Add approved repository entries to `config/repos.json`, run `make validate`,
and review the complete missing set before authorizing `make repos-clone`.
Cloning is not part of setup materialization.

## Preference-based enhancements

After the baseline works, an agent may recommend optional improvements based on
the saved mode and interface, for example:

- a CLI or orchestrator adapter that invokes the same `make` targets;
- a persistent devcontainer volume for selected caches;
- provider-specific account verification commands;
- a credential manager for host-native use;
- project-specific devcontainers for language or service dependencies; or
- backup and recovery automation for irreplaceable local state.

Recommendations must remain optional, explain their trust impact, and avoid
placing personalized state on the portable branch.
