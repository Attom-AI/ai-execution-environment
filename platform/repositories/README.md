# Repositories

`config/projects.json` is the inventory. Provider adapters implement clone,
fetch-only synchronization, and remote-default-branch resolution. `ensure.sh`
may clone a missing project and otherwise changes only remote-tracking refs;
it never checks out, merges, or modifies the canonical working tree.
