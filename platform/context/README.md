# Context memory subsystem

`platform/context/` manages session context windows (`L0`, `L1/L2`, `L3` + `WAL`
+ `LSM-tree` compaction) and snapshot-based context switching across
topic-partitioned sessions under `workspaces/<workspace>/<work-item>/context/`.

## Commands

```bash
# Initialize work-item context store and default ("main") or named partition
./platform/context/scripts/init.sh <workspace-id> <work-item-id> [--partition <topic>]

# Append a turn, decision, fact, file touch, or tombstone (WAL-first, auto-evicts L0->L1 and compacts L1->L2)
./platform/context/scripts/append.sh <workspace-id> <work-item-id> [--partition <topic>] \
  --kind <turn|decision|fact|file|tombstone> --key <key> [--value <text>] [--tokens <n>]

# Trigger minor (L1 MemTable -> L1 SSTable), major (k-way merge L1/L2 -> L2 SSTable), or l3 compaction
./platform/context/scripts/compact.sh <workspace-id> <work-item-id> [--partition <topic>] [--level minor|major|l3]

# Create, restore, list snapshots, or switch active topic partition with automatic snapshotting
./platform/context/scripts/snapshot.sh <workspace-id> <work-item-id> create [--partition <topic>] [--reason <label>]
./platform/context/scripts/snapshot.sh <workspace-id> <work-item-id> switch <target-partition>
./platform/context/scripts/snapshot.sh <workspace-id> <work-item-id> restore <snapshot-id> [--partition <topic>]
./platform/context/scripts/snapshot.sh <workspace-id> <work-item-id> list [--partition <topic>]

# Hydrate active context (L0 sliding window + merged L1/L2 key-value state + L3 archive summary)
./platform/context/scripts/hydrate.sh <workspace-id> <work-item-id> [--partition <topic>] [--prefix <key-prefix>]
```
