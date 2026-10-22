# 0004: Treat workspaces as materialized work-item folders

## Status

Accepted

## Context

The initial scaffold treated a workspace as a tracked VS Code
`.code-workspace` definition. That editor-specific meaning does not match the
platform model, where a workspace is simply a folder used to organize a
specific work item.

## Decision

Materialize and ignore `workspaces/` alongside the other local runtime
directories. Create `workspaces/<work-item>/` folders on demand and leave their
internal structure unconstrained.

Do not track `.code-workspace` files as platform definitions. Editors and other
tools may generate local configuration inside a work-item folder when useful.

## Consequences

- The portable repository is independent of VS Code and other editors.
- Work items can use only the organization they need.
- Workspace contents remain local unless deliberately persisted in their
  authoritative repository or content system.
- Repeated patterns may later become optional templates without changing the
  core definition of a workspace.
