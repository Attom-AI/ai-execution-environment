# Runtime lifecycle

One shared devcontainer definition is reused to build the runtimes, but each
worktree receives its own exclusive container. A bounded pool controls capacity
and defaults to five assignments. Pool entries are created lazily because a
container's workspace mount is established for a specific worktree.

`start` is idempotent. It safely synchronizes the canonical repository using a
provider adapter, resolves the remote's current default branch, and creates a
new branch explicitly from `origin/<default>` with no tracking relationship.
It never branches implicitly from the canonical checkout's `HEAD`. An existing
branch or registered worktree is reused. The work item claims an available pool
slot, then its container is started with that worktree mounted as the workspace.
The container id and slot are persisted in the work-item state. A sixth start
fails visibly while all five default slots are assigned.

Worktrees use relative Git administrative paths; `start` also repairs an older
registered worktree into this form. The Dev Container CLI mounts the canonical
repository's common Git directory into the runtime. This keeps Git fully
functional while exposing the selected worktree—not every project checkout—as
the container workspace.

Repository synchronization is fetch-only: it may update remote-tracking refs
and `origin/HEAD`, but never checks out, merges, resets, or modifies the
canonical index or working tree.

`stop` pauses the container while preserving its container-local state,
worktree, slot, branch, commits, workspace state, and artifacts. `close` refuses
to discard a dirty worktree, removes the container and worktree, frees the pool
slot, and records `merged` or `abandoned` as the terminal state. `list`
correlates persistent work items, pool slots, and live containers.

`slots` (`platform/runtime/scripts/slots.sh`) provides direct pool-slot
inspection and lifecycle management: viewing all slots (`1..RUNTIME_POOL_SIZE`)
and orphaned containers, growing or resizing pool capacity, allocating a specific
slot, recreating a slot's container, or releasing a slot from an inactive work
item without closing the ticket. `worktrees`
(`platform/runtime/scripts/worktrees.sh`) lists active, inactive, dirty, and
orphaned worktrees, inspects link health, repairs relative Git paths, and prunes
orphaned or clean inactive worktrees (`--dry-run` supported).

The runtime CLI (`platform/runtime/runtime.sh` or `bin/aee runtime`) provides a
unified command surface dispatching to `start`, `stop`, `close`, `list`, `slots`,
and `worktrees`. Top-level aliases like `bin/aee slots` and `bin/aee worktrees`
are also available.

The containers reuse the same built image rather than being copied from one
another. Credentials are never baked into an image or shared between
containers: each container mounts only its work item's isolated identity
profile at `/home/vscode/.identity`, with the matching environment, and keeps
that identity for its lifetime. Host-mode identities give the container no
credentials. See `identity-model.md`.
