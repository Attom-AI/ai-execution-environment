#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/context/scripts/lib.sh
source "$ROOT/platform/context/scripts/lib.sh"

usage() {
  printf 'usage: %s <workspace-id> <work-item-id> [--partition <topic>] [--level minor|major|l3]\n' "$0" >&2
}

[[ "$#" -ge 2 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
shift 2
partition=''
level='minor'
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --partition) partition="${2:-}"; shift 2 ;;
    --level) level="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

case "$level" in
  minor|major|l3) ;;
  *) die "invalid compaction level: $level (expected minor, major, or l3)" ;;
esac

"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item"
ctx_dir="$(context_dir "$workspace" "$work_item")"
if [[ -z "$partition" ]]; then
  partition="$(active_partition_of "$ctx_dir")"
fi
"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item" --partition "$partition"
part_dir="$(partition_dir "$ctx_dir" "$partition")"
timestamp="$(utc_now)"
sstable_threshold="$(jq -r '.config.sstableCompactThreshold // 4' "$ctx_dir/manifest.json")"

compact_minor() {
  local p_dir="$1"
  local p_name="$2"
  local l1_file="$p_dir/l1-memtable.json"
  local sst_manifest="$p_dir/l2-sstables/manifest.json"
  local count
  count="$(jq -r '.entryCount // 0' "$l1_file")"
  [[ "$count" -gt 0 ]] || return 0

  local min_seq
  local max_seq
  local min_key
  local max_key
  min_seq="$(jq -r '[.entries[].seq] | min' "$l1_file")"
  max_seq="$(jq -r '[.entries[].seq] | max' "$l1_file")"
  min_key="$(jq -r '.entries[0].key' "$l1_file")"
  max_key="$(jq -r '.entries[-1].key' "$l1_file")"

  local run_id="L1-${min_seq}-${max_seq}"
  local run_file="l2-sstables/${run_id}.json"
  local run_path="$p_dir/$run_file"

  local sst_content
  sst_content="$(jq \
    --arg id "$run_id" \
    --arg partition "$p_name" \
    --arg ts "$timestamp" \
    --arg min_key "$min_key" \
    --arg max_key "$max_key" \
    --argjson min_seq "$min_seq" \
    --argjson max_seq "$max_seq" \
    '{
      runId: $id,
      level: 1,
      partition: $partition,
      createdAt: $ts,
      minSeq: $min_seq,
      maxSeq: $max_seq,
      minKey: $min_key,
      maxKey: $max_key,
      entryCount: (.entries | length),
      entries: (.entries | sort_by(.key))
    }' \
    "$l1_file")"
  write_json_atomic "$run_path" "$sst_content"

  local updated_manifest
  updated_manifest="$(jq \
    --arg id "$run_id" \
    --arg file "$run_file" \
    --arg ts "$timestamp" \
    --arg min_key "$min_key" \
    --arg max_key "$max_key" \
    --argjson min_seq "$min_seq" \
    --argjson max_seq "$max_seq" \
    --argjson count "$count" \
    '.runs = ((.runs // []) + [{
       runId: $id,
       level: 1,
       file: $file,
       createdAt: $ts,
       minSeq: $min_seq,
       maxSeq: $max_seq,
       minKey: $min_key,
       maxKey: $max_key,
       entryCount: $count
     }])
     | .updatedAt = $ts' \
    "$sst_manifest")"
  write_json_atomic "$sst_manifest" "$updated_manifest"

  local empty_l1
  empty_l1="$(jq \
    --arg ts "$timestamp" \
    '.entries = [] | .entryCount = 0 | .updatedAt = $ts' \
    "$l1_file")"
  write_json_atomic "$l1_file" "$empty_l1"
}

compact_major() {
  local p_dir="$1"
  local p_name="$2"
  local sst_manifest="$p_dir/l2-sstables/manifest.json"
  local run_files=()
  while IFS= read -r rel_file; do
    [[ -n "$rel_file" ]] || continue
    [[ -f "$p_dir/$rel_file" ]] && run_files+=("$p_dir/$rel_file")
  done < <(jq -r '.runs[]?.file' "$sst_manifest")

  [[ "${#run_files[@]}" -gt 0 ]] || return 0

  # Major compaction purges tombstones and merges all runs into a single sorted L2 SSTable
  local merged_entries
  merged_entries="$(merge_entries_lsm true "${run_files[@]}")"
  local min_seq
  local max_seq
  min_seq="$(jq -r '[.runs[].minSeq] | min' "$sst_manifest")"
  max_seq="$(jq -r '[.runs[].maxSeq] | max' "$sst_manifest")"

  local entry_count
  entry_count="$(jq -r 'length' <<<"$merged_entries")"

  local old_file
  for old_file in "${run_files[@]}"; do
    rm -f "$old_file"
  done

  if [[ "$entry_count" -eq 0 ]]; then
    local cleared_manifest
    cleared_manifest="$(jq --arg ts "$timestamp" '.runs = [] | .updatedAt = $ts' "$sst_manifest")"
    write_json_atomic "$sst_manifest" "$cleared_manifest"
    return 0
  fi

  local min_key
  local max_key
  min_key="$(jq -r '.[0].key' <<<"$merged_entries")"
  max_key="$(jq -r '.[-1].key' <<<"$merged_entries")"
  local run_id="L2-${min_seq}-${max_seq}"
  local run_file="l2-sstables/${run_id}.json"
  local run_path="$p_dir/$run_file"

  local sst_content
  sst_content="$(jq -n \
    --arg id "$run_id" \
    --arg partition "$p_name" \
    --arg ts "$timestamp" \
    --arg min_key "$min_key" \
    --arg max_key "$max_key" \
    --argjson min_seq "$min_seq" \
    --argjson max_seq "$max_seq" \
    --argjson entries "$merged_entries" \
    '{
      runId: $id,
      level: 2,
      partition: $partition,
      createdAt: $ts,
      minSeq: $min_seq,
      maxSeq: $max_seq,
      minKey: $min_key,
      maxKey: $max_key,
      entryCount: ($entries | length),
      entries: $entries
    }')"
  write_json_atomic "$run_path" "$sst_content"

  local updated_manifest
  updated_manifest="$(jq -n \
    --arg partition "$p_name" \
    --arg id "$run_id" \
    --arg file "$run_file" \
    --arg ts "$timestamp" \
    --arg min_key "$min_key" \
    --arg max_key "$max_key" \
    --argjson min_seq "$min_seq" \
    --argjson max_seq "$max_seq" \
    --argjson count "$entry_count" \
    '{
      partition: $partition,
      updatedAt: $ts,
      runs: [{
        runId: $id,
        level: 2,
        file: $file,
        createdAt: $ts,
        minSeq: $min_seq,
        maxSeq: $max_seq,
        minKey: $min_key,
        maxKey: $max_key,
        entryCount: $count
      }]
    }')"
  write_json_atomic "$sst_manifest" "$updated_manifest"
}

if [[ "$level" == minor ]]; then
  compact_minor "$part_dir" "$partition"
  l1_run_count="$(jq -r '[.runs[]? | select(.level == 1)] | length' "$part_dir/l2-sstables/manifest.json")"
  if [[ "$l1_run_count" -ge "$sstable_threshold" ]]; then
    compact_major "$part_dir" "$partition"
  fi
elif [[ "$level" == major ]]; then
  compact_minor "$part_dir" "$partition"
  compact_major "$part_dir" "$partition"
elif [[ "$level" == l3 ]]; then
  all_sources=("$ctx_dir/l3-archive.json")
  while IFS= read -r p_name; do
    [[ -n "$p_name" ]] || continue
    p_dir="$(partition_dir "$ctx_dir" "$p_name")"
    [[ -d "$p_dir" ]] || continue
    compact_minor "$p_dir" "$p_name"
    compact_major "$p_dir" "$p_name"
    while IFS= read -r rel_file; do
      [[ -n "$rel_file" && -f "$p_dir/$rel_file" ]] && all_sources+=("$p_dir/$rel_file")
    done < <(jq -r '.runs[]?.file' "$p_dir/l2-sstables/manifest.json")
  done < <(jq -r '.partitions | keys[]' "$ctx_dir/manifest.json")

  l3_merged="$(merge_entries_lsm true "${all_sources[@]}")"
  l3_durable="$(jq '[ .[] | select(.kind != "turn") ]' <<<"$l3_merged")"
  l3_updated="$(jq \
    --arg ts "$timestamp" \
    --argjson entries "$l3_durable" \
    '.updatedAt = $ts
     | .entries = $entries
     | .entryCount = ($entries | length)' \
    "$ctx_dir/l3-archive.json")"
  write_json_atomic "$ctx_dir/l3-archive.json" "$l3_updated"
fi

printf 'compacted %s/%s (partition=%s level=%s)\n' "$workspace" "$work_item" "$partition" "$level"
