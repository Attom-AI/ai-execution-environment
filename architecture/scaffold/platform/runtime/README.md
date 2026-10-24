# Runtime

One shared devcontainer definition builds every runtime, but containers are not
shared between worktrees. The pool admits five exclusive worktree/container
assignments by default; set `RUNTIME_POOL_SIZE` to change the capacity.

`start.sh` creates or reuses a flat worktree, claims a pool slot, and creates or
resumes that worktree's container. `stop.sh` stops the container while retaining
the container, worktree, and slot. `close.sh` removes those resources and frees
the slot after refusing to discard uncommitted changes. `list.sh` reports pool
slots alongside durable state and live container status.

`worktrees.sh` inspects, repairs, and cleans up active, inactive, and orphaned
worktrees across `worktrees/`, `workspaces/`, and canonical repositories (`list`,
`inspect`, `repair`, `cleanup [--inactive] [--dry-run]`). `slots.sh` manages
container-pool capacity and slot assignments (`status`, `resize`, `add`,
`allocate`, `release`, `recreate`, `cleanup [--dry-run]`), including reclaiming a
slot from an inactive work item without closing the work item.

Containers reuse the common image layers. Credentials are not copied between
containers or baked into the image: each container mounts only its work item's
isolated identity profile from `.local/state/identities/<id>/`; see
`platform/identity/`.
