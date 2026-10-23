#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/workspaces/fixture/FEAT-1"
cp -R "$SOURCE_ROOT/platform" "$TEST_ROOT/platform"

jq \
  '.workspace = "fixture"
   | .workItem = "FEAT-1"
   | .project = "fixture"
   | .design.branch = "feat/1-context-test"' \
  "$SOURCE_ROOT/platform/state/templates/meta.json" \
  >"$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json"
: >"$TEST_ROOT/workspaces/fixture/FEAT-1/history.log"

export CONTEXT_L0_MAX_TURNS=3
export CONTEXT_L0_MAX_TOKENS=500
export CONTEXT_MEMTABLE_MAX_ENTRIES=3
export CONTEXT_SSTABLE_COMPACT_THRESHOLD=2

SCRIPTS="$TEST_ROOT/platform/context/scripts"
CTX="$TEST_ROOT/workspaces/fixture/FEAT-1/context"

# 1. Initialize default ("main") partition
"$SCRIPTS/init.sh" fixture FEAT-1
[[ -f "$CTX/manifest.json" ]]
[[ -f "$CTX/l3-archive.json" ]]
[[ -f "$CTX/partitions/main/wal.jsonl" ]]
[[ -f "$CTX/partitions/main/l0-window.json" ]]
[[ -f "$CTX/partitions/main/l1-memtable.json" ]]
[[ -f "$CTX/partitions/main/l2-sstables/manifest.json" ]]

# 2. Append 4 turns (L0 maxTurns=3 -> 1st turn evicts to L1 MemTable; all 4 in WAL)
"$SCRIPTS/append.sh" fixture FEAT-1 --kind turn --key t1 --value "Turn 1: initial exploration" --tokens 20 >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind turn --key t2 --value "Turn 2: inspect schema" --tokens 20 >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind turn --key t3 --value "Turn 3: draft query" --tokens 20 >/dev/null
[[ "$(jq -r '.turnCount' "$CTX/partitions/main/l0-window.json")" == 3 ]]
[[ "$(jq -r '.entryCount' "$CTX/partitions/main/l1-memtable.json")" == 0 ]]

"$SCRIPTS/append.sh" fixture FEAT-1 --kind turn --key t4 --value "Turn 4: refine index" --tokens 20 >/dev/null
[[ "$(wc -l <"$CTX/partitions/main/wal.jsonl" | tr -d ' ')" == 4 ]]
[[ "$(jq -r '.turnCount' "$CTX/partitions/main/l0-window.json")" == 3 ]]
[[ "$(jq -r '.turns[0].key' "$CTX/partitions/main/l0-window.json")" == "turn:t2" ]]
[[ "$(jq -r '.entryCount' "$CTX/partitions/main/l1-memtable.json")" == 1 ]]
[[ "$(jq -r '.entries[0].key' "$CTX/partitions/main/l1-memtable.json")" == "turn:t1" ]]

# 3. Trigger automatic minor compaction (memtableMaxEntries=3)
"$SCRIPTS/append.sh" fixture FEAT-1 --kind decision --key storage --value "Use LSM-tree v1" >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind fact --key temp-note --value "Temporary scratch fact" >/dev/null
# L1 MemTable had 3 entries (turn:t1, decision:storage, fact:temp-note) -> flushed to L1 SSTable run
[[ "$(jq -r '.entryCount' "$CTX/partitions/main/l1-memtable.json")" == 0 ]]
[[ "$(jq -r '.runs | length' "$CTX/partitions/main/l2-sstables/manifest.json")" == 1 ]]
[[ "$(jq -r '.runs[0].level' "$CTX/partitions/main/l2-sstables/manifest.json")" == 1 ]]

# Capture a snapshot after first minor compaction
snap_before_override="$("$SCRIPTS/snapshot.sh" fixture FEAT-1 create --reason before-override)"
[[ -n "$snap_before_override" ]]

# 4. Override key (decision:storage), tombstone key (fact:temp-note), and add file key -> triggers 2nd L1 run + automatic major compaction (sstableCompactThreshold=2)
"$SCRIPTS/append.sh" fixture FEAT-1 --kind decision --key storage --value "Use LSM-tree v2 with snapshots" >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind tombstone --key "fact:temp-note" >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind file --key "platform/context/scripts/compact.sh" --value "Compaction script" >/dev/null

# Verify major compaction merged into a single L2 SSTable run, kept v2 of decision:storage, and purged tombstoned fact:temp-note
[[ "$(jq -r '.runs | length' "$CTX/partitions/main/l2-sstables/manifest.json")" == 1 ]]
[[ "$(jq -r '.runs[0].level' "$CTX/partitions/main/l2-sstables/manifest.json")" == 2 ]]

hydrated_main="$("$SCRIPTS/hydrate.sh" fixture FEAT-1)"
jq -e '
  .activePartition == "main" and
  .l0Window.turnCount == 3 and
  ((.activeState | map(select(.key == "decision:storage")) | .[0].value) == "Use LSM-tree v2 with snapshots") and
  ((.activeState | map(select(.key == "fact:temp-note")) | length) == 0) and
  ((.activeState | map(select(.key == "file:platform/context/scripts/compact.sh")) | length) == 1)
' <<<"$hydrated_main" >/dev/null

# 5. Topic-partitioned context switching with zero context bleed
switched_subtopic="$("$SCRIPTS/snapshot.sh" fixture FEAT-1 switch auth-topic)"
jq -e '
  .activePartition == "auth-topic" and
  .partition == "auth-topic" and
  .l0Window.turnCount == 0 and
  (.activeState | length == 0)
' <<<"$switched_subtopic" >/dev/null

"$SCRIPTS/append.sh" fixture FEAT-1 --kind decision --key token-format --value "Ed25519 signed session token" >/dev/null
"$SCRIPTS/append.sh" fixture FEAT-1 --kind turn --key auth-t1 --value "Subtopic turn 1" --tokens 15 >/dev/null

hydrated_subtopic="$("$SCRIPTS/hydrate.sh" fixture FEAT-1)"
jq -e '
  .activePartition == "auth-topic" and
  .l0Window.turnCount == 1 and
  ((.activeState | map(select(.key == "decision:token-format")) | length) == 1) and
  ((.activeState | map(select(.key == "decision:storage")) | length) == 0)
' <<<"$hydrated_subtopic" >/dev/null

# Switch back to main and verify main's context is preserved without auth-topic bleed
switched_main="$("$SCRIPTS/snapshot.sh" fixture FEAT-1 switch main)"
jq -e '
  .activePartition == "main" and
  .partition == "main" and
  .l0Window.turnCount == 3 and
  ((.activeState | map(select(.key == "decision:storage")) | .[0].value) == "Use LSM-tree v2 with snapshots") and
  ((.activeState | map(select(.key == "decision:token-format")) | length) == 0)
' <<<"$switched_main" >/dev/null

# 6. Restore earlier snapshot on main and verify point-in-time recovery
"$SCRIPTS/snapshot.sh" fixture FEAT-1 restore "$snap_before_override" --partition main >/dev/null
restored_main="$("$SCRIPTS/hydrate.sh" fixture FEAT-1 --partition main)"
jq -e '
  ((.activeState | map(select(.key == "decision:storage")) | .[0].value) == "Use LSM-tree v1") and
  ((.activeState | map(select(.key == "fact:temp-note")) | .[0].value) == "Temporary scratch fact")
' <<<"$restored_main" >/dev/null

# 7. L3 compaction across all partitions promotes durable facts/decisions and excludes raw turns
"$SCRIPTS/compact.sh" fixture FEAT-1 --level l3 >/dev/null
hydrated_after_l3="$("$SCRIPTS/hydrate.sh" fixture FEAT-1)"
jq -e '
  (.l3Archive.entryCount >= 2) and
  ((.l3Archive.entries | map(select(.kind == "turn")) | length) == 0) and
  ((.l3Archive.entries | map(select(.key == "decision:token-format")) | length) == 1) and
  ((.l3Archive.entries | map(select(.key == "decision:storage")) | length) == 1)
' <<<"$hydrated_after_l3" >/dev/null

printf 'context memory test passed\n'
