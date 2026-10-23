#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/context/scripts/lib.sh
source "$ROOT/platform/context/scripts/lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 <workspace-id> <work-item-id> create [--partition <topic>] [--reason <label>]
  $0 <workspace-id> <work-item-id> switch <target-partition>
  $0 <workspace-id> <work-item-id> restore <snapshot-id> [--partition <topic>]
  $0 <workspace-id> <work-item-id> list [--partition <topic>]
EOF
}

[[ "$#" -ge 3 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
action="$3"
shift 3

"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item"
ctx_dir="$(context_dir "$workspace" "$work_item")"
timestamp="$(utc_now)"

create_snapshot() {
  local partition="$1"
  local reason="$2"
  "$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item" --partition "$partition"
  local part_dir
  part_dir="$(partition_dir "$ctx_dir" "$partition")"

  local wal_seq
  wal_seq="$(jq -r --arg p "$partition" '.partitions[$p].lastWalSeq // 0' "$ctx_dir/manifest.json")"
  local ts_slug
  ts_slug="$(printf '%s' "$timestamp" | tr -cd '0-9TZ')"
  local snap_id="snap-${wal_seq}-${ts_slug}"
  local snap_path="$part_dir/snapshots/${snap_id}.json"
  while [[ -e "$snap_path" ]]; do
    snap_id="${snap_id}-1"
    snap_path="$part_dir/snapshots/${snap_id}.json"
  done

  local run_objects='[]'
  while IFS= read -r rel_file; do
    [[ -n "$rel_file" && -f "$part_dir/$rel_file" ]] || continue
    run_objects="$(jq \
      --arg file "$rel_file" \
      --slurpfile data "$part_dir/$rel_file" \
      '. + [{file: $file, content: $data[0]}]' \
      <<<"$run_objects")"
  done < <(jq -r '.runs[]?.file' "$part_dir/l2-sstables/manifest.json")

  local snap_content
  snap_content="$(jq -n \
    --arg id "$snap_id" \
    --arg partition "$partition" \
    --arg reason "$reason" \
    --arg ts "$timestamp" \
    --argjson wal_seq "$wal_seq" \
    --slurpfile l0 "$part_dir/l0-window.json" \
    --slurpfile l1 "$part_dir/l1-memtable.json" \
    --slurpfile sst_manifest "$part_dir/l2-sstables/manifest.json" \
    --argjson sst_runs "$run_objects" \
    '{
      snapshotId: $id,
      partition: $partition,
      reason: $reason,
      createdAt: $ts,
      walSeq: $wal_seq,
      l0Window: $l0[0],
      l1Memtable: $l1[0],
      sstableManifest: $sst_manifest[0],
      sstableData: $sst_runs
    }')"
  write_json_atomic "$snap_path" "$snap_content"

  local manifest_updated
  manifest_updated="$(jq \
    --arg p "$partition" \
    --arg id "$snap_id" \
    --arg ts "$timestamp" \
    '.partitions[$p].latestSnapshot = $id
     | .partitions[$p].updatedAt = $ts
     | .updatedAt = $ts' \
    "$ctx_dir/manifest.json")"
  write_json_atomic "$ctx_dir/manifest.json" "$manifest_updated"

  printf '%s\n' "$snap_id"
}

case "$action" in
  create)
    partition=''
    reason='manual'
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --partition) partition="${2:-}"; shift 2 ;;
        --reason) reason="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    if [[ -z "$partition" ]]; then
      partition="$(active_partition_of "$ctx_dir")"
    fi
    create_snapshot "$partition" "$reason"
    ;;
  switch)
    [[ "$#" -eq 1 ]] || { usage; exit 2; }
    target_partition="$1"
    validate_partition_id "$target_partition"
    current_partition="$(active_partition_of "$ctx_dir")"
    if [[ "$current_partition" != "$target_partition" ]]; then
      create_snapshot "$current_partition" "switch-out" >/dev/null
      "$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item" --partition "$target_partition"
      manifest_updated="$(jq \
        --arg target "$target_partition" \
        --arg ts "$timestamp" \
        '.activePartition = $target | .updatedAt = $ts' \
        "$ctx_dir/manifest.json")"
      write_json_atomic "$ctx_dir/manifest.json" "$manifest_updated"
    fi
    "$ROOT/platform/context/scripts/hydrate.sh" "$workspace" "$work_item" --partition "$target_partition"
    ;;
  restore)
    [[ "$#" -ge 1 ]] || { usage; exit 2; }
    snap_id="$1"
    shift
    partition=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --partition) partition="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    if [[ -z "$partition" ]]; then
      partition="$(active_partition_of "$ctx_dir")"
    fi
    part_dir="$(partition_dir "$ctx_dir" "$partition")"
    snap_file="$part_dir/snapshots/${snap_id}.json"
    [[ -f "$snap_file" ]] || die "snapshot not found: $partition/$snap_id"

    write_json_atomic "$part_dir/l0-window.json" "$(jq '.l0Window' "$snap_file")"
    write_json_atomic "$part_dir/l1-memtable.json" "$(jq '.l1Memtable' "$snap_file")"

    find "$part_dir/l2-sstables" -maxdepth 1 -name 'L*.json' -type f -delete
    count="$(jq -r '.sstableData | length' "$snap_file")"
    for ((i = 0; i < count; i++)); do
      rel_file="$(jq -r ".sstableData[$i].file" "$snap_file")"
      content="$(jq ".sstableData[$i].content" "$snap_file")"
      write_json_atomic "$part_dir/$rel_file" "$content"
    done
    write_json_atomic "$part_dir/l2-sstables/manifest.json" "$(jq '.sstableManifest' "$snap_file")"

    wal_seq="$(jq -r '.walSeq' "$snap_file")"
    manifest_updated="$(jq \
      --arg p "$partition" \
      --arg id "$snap_id" \
      --arg ts "$timestamp" \
      --argjson seq "$wal_seq" \
      '.partitions[$p].lastWalSeq = $seq
       | .partitions[$p].latestSnapshot = $id
       | .partitions[$p].updatedAt = $ts
       | .updatedAt = $ts' \
      "$ctx_dir/manifest.json")"
    write_json_atomic "$ctx_dir/manifest.json" "$manifest_updated"
    printf 'restored %s/%s partition=%s snapshot=%s\n' "$workspace" "$work_item" "$partition" "$snap_id"
    ;;
  list)
    partition=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --partition) partition="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    if [[ -z "$partition" ]]; then
      partition="$(active_partition_of "$ctx_dir")"
    fi
    part_dir="$(partition_dir "$ctx_dir" "$partition")"
    snap_files=()
    while IFS= read -r f; do
      snap_files+=("$f")
    done < <(find "$part_dir/snapshots" -maxdepth 1 -name 'snap-*.json' -type f -print 2>/dev/null | sort)
    if [[ "${#snap_files[@]}" -eq 0 ]]; then
      printf '[]\n'
    else
      jq -s 'map({snapshotId, partition, reason, createdAt, walSeq}) | sort_by(.walSeq, .createdAt)' "${snap_files[@]}"
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
