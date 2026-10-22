# 0002: Keep materialized workspace state out of main

## Status

Accepted

## Context

The platform repository must be portable, while an active personal workspace
contains repository checkouts, credentials, temporary worktrees, scratch data,
and tool-generated metadata. Placeholder files made those runtime directories
part of the repository tree even though their contents were intentionally
local.

## Decision

The `main` branch contains only declarative configuration, automation,
documentation, templates, and static workspace definitions.

The following paths are materialized by `make bootstrap` and ignored in full:

- `repos/`
- `worktrees/`
- `state/`
- `scratch/`

The devcontainer lock file is also treated as generated local output. The root
devcontainer runs `make bootstrap` after creation so a clean clone becomes a
usable workspace without tracked placeholders.

## Consequences

- A clean clone does not contain runtime directories until it is bootstrapped.
- Repository checkouts and local state cannot accidentally become part of the
  platform repository.
- Recreating the environment requires bootstrap, GitHub authentication, and
  repository materialization.
- The devcontainer lock may differ between materializations as feature
  releases change.
