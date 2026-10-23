#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/context/scripts/lib.sh
source "$ROOT/platform/context/scripts/lib.sh"

usage() {
  printf 'usage: %s <workspace-id> <work-item-id> [--partition <topic>]\n' "$0" >&2
}

[[ "$#" -ge 2 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
shift 2
partition='main'
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --partition) partition="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

validate_partition_id "$partition"
ctx_dir="$(context_dir "$workspace" "$work_item")"
mkdir -p "$ctx_dir/partitions"
timestamp="$(utc_now)"

l0_max_turns="$(context_setting CONTEXT_L0_MAX_TURNS 8)"
l0_max_tokens="$(context_setting CONTEXT_L0_MAX_TOKENS 4000)"
memtable_max="$(context_setting CONTEXT_MEMTABLE_MAX_ENTRIES 16)"
sstable_threshold="$(context_setting CONTEXT_SSTABLE_COMPACT_THRESHOLD 4)"

manifest_file="$ctx_dir/manifest.json"
if [[ ! -f "$manifest_file" ]]; then
  manifest_content="$(jq \
    --arg workspace "$workspace" \
    --arg work_item "$work_item" \
    --arg partition "$partition" \
    --arg ts "$timestamp" \
    --argjson l0_turns "$l0_max_turns" \
    --argjson l0_tokens "$l0_max_tokens" \
    --argjson memtable_max "$memtable_max" \
    --argjson sstable_threshold "$sstable_threshold" \
    '.workspace = $workspace
     | .workItem = $work_item
     | .activePartition = $partition
     | .config.l0MaxTurns = $l0_turns
     | .config.l0MaxTokens = $l0_tokens
     | .config.memtableMaxEntries = $memtable_max
     | .config.sstableCompactThreshold = $sstable_threshold
     | .updatedAt = $ts' \
    "$ROOT/platform/context/templates/manifest.json")"
  write_json_atomic "$manifest_file" "$manifest_content"
fi

l3_file="$ctx_dir/l3-archive.json"
if [[ ! -f "$l3_file" ]]; then
  l3_content="$(jq -n \
    --arg workspace "$workspace" \
    --arg work_item "$work_item" \
    --arg ts "$timestamp" \
    '{
      schemaVersion: 1,
      workspace: $workspace,
      workItem: $work_item,
      updatedAt: $ts,
      entryCount: 0,
      entries: []
    }')"
  write_json_atomic "$l3_file" "$l3_content"
fi

part_dir="$(partition_dir "$ctx_dir" "$partition")"
mkdir -p "$part_dir/l2-sstables" "$part_dir/snapshots"
touch "$part_dir/wal.jsonl"

if [[ ! -f "$part_dir/l0-window.json" ]]; then
  l0_content="$(jq -n \
    --arg partition "$partition" \
    --arg ts "$timestamp" \
    --argjson max_turns "$l0_max_turns" \
    --argjson max_tokens "$l0_max_tokens" \
    '{
      partition: $partition,
      updatedAt: $ts,
      maxTurns: $max_turns,
      maxTokens: $max_tokens,
      turnCount: 0,
      totalTokens: 0,
      turns: []
    }')"
  write_json_atomic "$part_dir/l0-window.json" "$l0_content"
fi

if [[ ! -f "$part_dir/l1-memtable.json" ]]; then
  l1_content="$(jq -n \
    --arg partition "$partition" \
    --arg ts "$timestamp" \
    '{
      partition: $partition,
      updatedAt: $ts,
      entryCount: 0,
      entries: []
    }')"
  write_json_atomic "$part_dir/l1-memtable.json" "$l1_content"
fi

if [[ ! -f "$part_dir/l2-sstables/manifest.json" ]]; then
  sstable_manifest="$(jq -n \
    --arg partition "$partition" \
    --arg ts "$timestamp" \
    '{
      partition: $partition,
      updatedAt: $ts,
      runs: []
    }')"
  write_json_atomic "$part_dir/l2-sstables/manifest.json" "$sstable_manifest"
fi

manifest_updated="$(jq \
  --arg partition "$partition" \
  --arg ts "$timestamp" \
  'if (.partitions[$partition] == null) then
     .partitions[$partition] = {
       createdAt: $ts,
       updatedAt: $ts,
       lastWalSeq: 0,
       latestSnapshot: null
     }
   else
     .
   end' \
  "$manifest_file")"
write_json_atomic "$manifest_file" "$manifest_updated"
