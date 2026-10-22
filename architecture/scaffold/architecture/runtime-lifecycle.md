# Runtime lifecycle

One shared devcontainer definition is reused for every work item. `start`,
`stop`, `close`, and `list` are distinct operations.

`start` is idempotent. It safely synchronizes the canonical repository using a
provider adapter, resolves the remote's current default branch, and creates a
new branch explicitly from `origin/<default>` with no tracking relationship.
It never branches implicitly from the canonical checkout's `HEAD`. An existing
branch or registered worktree is reused. The shared devcontainer is then
started with the worktree mounted as its workspace, and the resulting container
id is persisted.

Repository synchronization is fetch-only: it may update remote-tracking refs
and `origin/HEAD`, but never checks out, merges, resets, or modifies the
canonical index or working tree.

`stop` removes the container and worktree but preserves the branch, commits,
workspace state, and artifacts. It refuses to force-remove a dirty worktree.
`close` first performs a safe stop, then records `merged` or `abandoned` as the
terminal state. `list` correlates persistent work items with live containers.
