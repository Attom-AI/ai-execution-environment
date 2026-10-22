# Runtime

One shared devcontainer definition serves all work items. `start.sh` creates or
reuses a flat worktree and starts its container. `stop.sh` removes runtime
resources while preserving branch commits and workspace state. `close.sh`
permanently closes a merged or abandoned item. `list.sh` reports both durable
state and live container status.
