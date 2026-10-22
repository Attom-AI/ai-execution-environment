# 0001: Use an isolated VM with a root devcontainer

- Status: accepted
- Date: 2026-10-21

## Decision

Use a dedicated Linux VM as the boundary between the workspace's selected trust
domain and other development contexts. Store managed repositories on the VM
disk. Run a generic root devcontainer inside the VM for workspace
administration, while allowing each project to define its own development
container.

## Consequences

- In-scope repositories and credentials remain outside the host's other
  development environments.
- The VM requires an explicit backup and recovery strategy.
- The root container can see repositories under `repos/`; it is a convenience
  and reproducibility layer, not a per-project security boundary.
- Projects remain independently versioned and deployable.

## Deferred choice

The VM provider and provisioning mechanism remain undecided. Provider-specific
automation will be added under `infra/vm/` after that choice is made.
