#!/usr/bin/env bash

set -euo pipefail

CONTEXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/runtime/scripts/lib.sh
source "$CONTEXT_ROOT/platform/runtime/scripts/lib.sh"

validate_partition_id() {
  local partition="$1"
  [[ "$partition" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid partition id: $partition"
}

context_dir() {
  local directory
  directory="$(require_work_item "$1" "$2")"
  printf '%s/context\n' "$directory"
}

partition_dir() {
  local ctx_dir="$1"
  local partition="$2"
  validate_partition_id "$partition"
  printf '%s/partitions/%s\n' "$ctx_dir" "$partition"
}

context_setting() {
  local name="$1"
  local default_val="$2"
  local value="${!name:-}"
  if [[ -z "$value" && -f "$CONTEXT_ROOT/.env" ]]; then
    value="$(sed -nE "s/^${name}=([0-9]+)$/\1/p" "$CONTEXT_ROOT/.env" | tail -n 1)"
  fi
  value="${value:-$default_val}"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name must be a positive integer"
  printf '%s\n' "$value"
}

write_json_atomic() {
  local target="$1"
  local content="$2"
  local temporary="${target}.tmp.$$"
  printf '%s\n' "$content" >"$temporary"
  mv "$temporary" "$target"
}

active_partition_of() {
  local ctx_dir="$1"
  jq -r '.activePartition // "main"' "$ctx_dir/manifest.json"
}

next_context_seq() {
  local ctx_dir="$1"
  local manifest="$ctx_dir/manifest.json"
  local seq
  local updated
  seq="$(jq -r '(.lastSeq // 0) + 1' "$manifest")"
  updated="$(jq --argjson seq "$seq" --arg ts "$(utc_now)" '.lastSeq = $seq | .updatedAt = $ts' "$manifest")"
  write_json_atomic "$manifest" "$updated"
  printf '%s\n' "$seq"
}

upsert_memtable_entry() {
  local memtable_file="$1"
  local entry_json="$2"
  local updated
  updated="$(jq \
    --argjson entry "$entry_json" \
    --arg ts "$(utc_now)" \
    '.entries = (
       ((.entries // []) | map(select(.key != $entry.key))) + [$entry]
       | sort_by(.key)
     )
     | .entryCount = (.entries | length)
     | .updatedAt = $ts' \
    "$memtable_file")"
  write_json_atomic "$memtable_file" "$updated"
}

merge_entries_lsm() {
  local purge_tombstones="$1"
  shift
  if [[ "$#" -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi
  jq -s \
    --argjson purge "$purge_tombstones" \
    '[ .[] | (.entries // [])[] ]
     | group_by(.key)
     | map(max_by(.seq))
     | if $purge then map(select((.tombstone // false) | not)) else . end
     | sort_by(.key)' \
    "$@"
}
