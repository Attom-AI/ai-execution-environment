# Install and portability

`platform/install/install.sh` is the single bootstrap entry point. It creates
ignored instance directories, seeds root `.env` from
`platform/install/templates/.env.example` without overwriting it, reports
dependencies and authentication status, and validates tracked infrastructure.
It does not clone repositories, fetch remotes, or start runtimes.

The tracked tree contains only reusable control-plane material and generic
configuration. Repositories, work items, worktrees, identity profiles and their
credentials, runtime state, and `.env` remain instance-local. Projects reference
identities by name only, so a manifest can be shared without exposing which
secrets back it. A fresh instance is created by copying the
portable scaffold and running the platform installer.
