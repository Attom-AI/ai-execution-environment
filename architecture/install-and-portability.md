# Installation and portability

The tracked tree is portable. `platform/install/install.sh` creates ignored instance paths,
seeds a non-secret `.env`, checks required tools, and validates the control
plane. Repositories, work items, worktrees, credentials, and local state are
never part of the portable layer.
