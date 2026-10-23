#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/context/scripts/lib.sh
source "$ROOT/platform/context/scripts/lib.sh"

usage() {
  printf 'usage: %s <workspace-id> <work-item-id> [--partition <topic>] [--prefix <key-prefix>]\n' "$0" >&2
}

[[ "$#" -ge 2 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
shift 2
partition=''
prefix=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --partition) partition="${2:-}"; shift 2 ;;
    --prefix) prefix="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item"
ctx_dir="$(context_dir "$workspace" "$work_item")"
active_part="$(active_partition_of "$ctx_dir")"
if [[ -z "$partition" ]]; then
  partition="$active_part"
fi
"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item" --partition "$partition"
part_dir="$(partition_dir "$ctx_dir" "$partition")"

sources=("$part_dir/l1-memtable.json")
while IFS= read -r rel_file; do
  [[ -n "$rel_file" && -f "$part_dir/$rel_file" ]] && sources+=("$part_dir/$rel_file")
done < <(jq -r '.runs[]?.file' "$part_dir/l2-sstables/manifest.json")

merged_state="$(merge_entries_lsm true "${sources[@]}")"
if [[ -n "$prefix" ]]; then
  merged_state="$(jq --arg p "$prefix" '[ .[] | select(.key | startswith($p)) ]' <<<"$merged_state")"
fi

jq -n \
  --arg workspace "$workspace" \
  --arg work_item "$work_item" \
  --arg active_partition "$active_part" \
  --arg partition "$partition" \
  --slurpfile manifest "$ctx_dir/manifest.json" \
  --slurpfile l0 "$part_dir/l0-window.json" \
  --slurpfile l1 "$part_dir/l1-memtable.json" \
  --slurpfile sst "$part_dir/l2-sstables/manifest.json" \
  --slurpfile l3 "$ctx_dir/l3-archive.json" \
  --argjson state "$merged_state" \
  '{
    workspace: $workspace,
    workItem: $work_item,
    activePartition: $active_partition,
    partition: $partition,
    walSeq: ($manifest[0].partitions[$partition].lastWalSeq // 0),
    latestSnapshot: ($manifest[0].partitions[$partition].latestSnapshot // null),
    l0Window: {
      turnCount: $l0[0].turnCount,
      totalTokens: $l0[0].totalTokens,
      maxTurns: $l0[0].maxTurns,
      maxTokens: $l0[0].maxTokens,
      turns: $l0[0].turns
    },
    l1MemtableCount: ($l1[0].entryCount // 0),
    l2SstableRuns: ($sst[0].runs // []),
    activeState: $state,
    l3Archive: {
      entryCount: ($l3[0].entryCount // 0),
      entries: ($l3[0].entries // [])
    }
  }'
