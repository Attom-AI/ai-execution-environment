# Runtime lifecycle

`start.sh` creates a dedicated branch and flat worktree from a canonical
checkout. `stop.sh` removes only that worktree and clears its runtime pointer.
`close.sh` also marks the persistent work item closed. Canonical checkouts are
never used as task working directories.
