# 0004: Use tool-neutral workspace manifests

- Status: accepted
- Date: 2026-10-21

## Decision

Define logical workspaces in the versioned `config/workspaces.json` manifest.
Each workspace has a unique name and a non-empty list of repository names from
`config/repos.json`. Repository membership is unique across workspaces.

Treat files under `workspaces/` as optional integrations for specific editors
or tools. These files may adapt a logical workspace for a tool, but they are not
the source of truth for its membership.

## Consequences

- Workspace identity and membership can be consumed without understanding an
  editor-specific file format.
- A repository belongs to at most one logical workspace, preventing competing
  ownership definitions.
- A one-repository workspace is valid and can provide a stable, precise name
  even when no tool-specific integration is needed.
- Changes to either manifest must pass cross-manifest validation before use.
