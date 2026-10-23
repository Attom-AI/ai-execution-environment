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

The containers reuse the same built image rather than being copied from one
another. GitHub CLI state remains outside the containers in `.local/state/gh`
and is bind-mounted into each runtime, so new pool members do not require
duplicated authentication and credentials are never committed into an image.
