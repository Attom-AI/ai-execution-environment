# Context memory model

While `platform/state/` coordinates coarse-grained pipeline stage handoffs
(`meta.json`, `session-state.md`, `history.log`, and `artifacts/`),
`platform/context/` manages active conversation context windows and fast
context switching across topic-partitioned sessions under
`workspaces/<workspace>/<work-item>/context/`.

## Two complementary responsibilities

1. **Sliding-window context management with LSM-tree compaction**: keeps the
   active prompt window bounded during long interactive or stage-execution
   sessions without losing durable facts, decisions, or raw audit trails.
2. **Topic-partitioned session context switching**: isolates each work item's
   primary session (`main`) and optional sub-topic partitions
   (`partitions/<topic>/`), using consistent snapshots of the MemTable,
   SSTables, and L0 window to switch contexts in $O(1)$ without cross-topic
   contamination or full WAL replay.

## Memory tiers (`L0` -> `L1/L2` -> `L3`) and `WAL`

Each topic partition under
`workspaces/<workspace>/<work-item>/context/partitions/<topic>/` maintains:

- **WAL (`wal.jsonl`)**: append-only JSON Lines log recording every incoming
  turn, fact, decision, file touch, or tombstone with a monotonically
  increasing sequence number (`seq`) before any window eviction or MemTable
  mutation occurs. Never scanned during normal prompt hydration.
- **L0 (`l0-window.json`)**: bounded sliding window (`l0MaxTurns`, default `8`;
  `l0MaxTokens`, default `4000`) holding the uncompacted active conversation
  turns currently in the prompt window. When the window overflows, the oldest
  turns are evicted into the L1 MemTable.
- **L1 (`l1-memtable.json`)**: sorted, mutable in-session key-value map absorbing
  evicted L0 turns (`turn:<seq>`) and structured session updates
  (`decision:<key>`, `fact:<key>`, `file:<key>`, or tombstones). Entries are
  sorted by `key`, with the newest `seq` winning on update.
- **L2 (`l2-sstables/`)**: immutable, sorted SSTable runs produced by LSM-tree
  compaction:
  - **Minor compaction (`L1-<minSeq>-<maxSeq>.json`)**: triggered automatically
    when `l1-memtable.json` reaches `memtableMaxEntries` (default `16`) or on
    explicit flush. Writes the sorted MemTable to an immutable L1 SSTable run
    and resets `l1-memtable.json`.
  - **Major compaction (`L2-<minSeq>-<maxSeq>.json`)**: triggered automatically
    when minor SSTable runs reach `sstableCompactThreshold` (default `4`) or on
    explicit request. Performs a deterministic merge across L1 and L2 runs,
    retaining only the highest-`seq` record per key and purging keys whose
    winning record is a tombstone (`tombstone: true`).
- **L3 (`context/l3-archive.json` and `documentation/projects/<project>/`)**:
  cold, cross-partition compacted archive updated on work-item closure or `l3`
  compaction, distilling durable decisions, facts, and file references that
  survive after individual topic partitions are closed.

## Snapshots and topic-partitioned context switching

Switching between tickets or between sub-topics within a ticket uses point-in-time
snapshots (`partitions/<topic>/snapshots/snap-<seq>-<timestamp>.json`). Each
snapshot freezes:

- `walSeq`: the partition's watermark in `wal.jsonl`;
- `l0Window`: the exact sliding-window state;
- `l1Memtable`: the active mutable MemTable;
- `sstableManifest` and snapshotted SSTable entries.

When `snapshot.sh switch <target-partition>` runs, the current partition is
snapshotted (`reason=switch-out`), `manifest.json` updates `activePartition`,
and the target partition's state is hydrated immediately via `hydrate.sh`.
Runtime `stop.sh` and `close.sh` hooks automatically capture snapshots and run
L3 compaction so session memory remains recoverable across container stops and
disposal.
