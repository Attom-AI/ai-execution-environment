# 0003: Use an agent-first setup contract with selectable profiles

## Status

Accepted

## Context

The environment may be operated through different coding agents, agent CLIs,
or chat interfaces. Some operators need devcontainer isolation for tools and
credentials, while others already have suitable Git and provider CLIs on a
trusted host. Maintaining one long-lived branch for each tool or setup mode
would duplicate the workspace contract and allow the variants to drift.

## Decision

Keep one agent-independent setup contract in the portable platform. Agents
must discover or ask for an execution profile, explain the implications,
verify prerequisites, and guide the operator step by step.

The initial profiles are:

- `devcontainer` for an isolated workspace tool and credential context;
- `host` for existing globally configured tools and credentials; and
- `guidance` when the agent can advise but cannot execute commands.

Tool-specific integrations and preference-based recommendations are optional
extensions to these profiles. They must not be required by the common setup
path. Local selections and credentials are materialized as ignored state.

Develop setup capabilities on short-lived feature branches and merge them into
`main` after validation. Do not maintain permanent branches per agent, tool, or
execution profile. Operators may keep their own working branches for tracked
personalizations.

## Consequences

- The same clone can be used with different agent products and interfaces.
- Devcontainer isolation remains available without becoming mandatory.
- Host-native setup is supported without copying global credentials into the
  repository.
- Agents can tailor recommendations without silently installing tools or
  authenticating accounts.
- Profile-specific features must preserve a shared setup contract and pass the
  same validation checks.
