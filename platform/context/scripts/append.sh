#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=platform/context/scripts/lib.sh
source "$ROOT/platform/context/scripts/lib.sh"

usage() {
  printf 'usage: %s <workspace-id> <work-item-id> [--partition <topic>] --kind <turn|decision|fact|file|tombstone> --key <key> [--value <text>] [--tokens <n>]\n' "$0" >&2
}

[[ "$#" -ge 2 ]] || { usage; exit 2; }
workspace="$1"
work_item="$2"
shift 2
partition=''
kind=''
key=''
value=''
tokens=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --partition) partition="${2:-}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    --key) key="${2:-}"; shift 2 ;;
    --value) value="${2:-}"; shift 2 ;;
    --tokens) tokens="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

case "$kind" in
  turn|decision|fact|file|tombstone) ;;
  *) die "invalid kind: ${kind:-<empty>} (expected turn, decision, fact, file, or tombstone)" ;;
esac
[[ -n "$key" ]] || die "--key is required"
[[ "$tokens" =~ ^[0-9]+$ ]] || die "--tokens must be a non-negative integer"
if [[ "$kind" != tombstone && -z "$value" ]]; then
  die "--value is required when --kind is $kind"
fi

"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item"
ctx_dir="$(context_dir "$workspace" "$work_item")"
if [[ -z "$partition" ]]; then
  partition="$(active_partition_of "$ctx_dir")"
fi
"$ROOT/platform/context/scripts/init.sh" "$workspace" "$work_item" --partition "$partition"
part_dir="$(partition_dir "$ctx_dir" "$partition")"

if [[ "$tokens" -eq 0 && -n "$value" ]]; then
  char_len="${#value}"
  tokens=$(((char_len + 3) / 4))
  [[ "$tokens" -ge 1 ]] || tokens=1
fi

seq="$(next_context_seq "$ctx_dir")"
timestamp="$(utc_now)"
is_tombstone=false
if [[ "$kind" == tombstone ]]; then
  is_tombstone=true
fi

if [[ "$key" == *:* ]]; then
  normalized_key="$key"
else
  normalized_key="${kind}:${key}"
fi

wal_record="$(jq -cn \
  --argjson seq "$seq" \
  --arg ts "$timestamp" \
  --arg partition "$partition" \
  --arg kind "$kind" \
  --arg key "$normalized_key" \
  --arg value "$value" \
  --argjson tokens "$tokens" \
  --argjson tombstone "$is_tombstone" \
  '{
    seq: $seq,
    timestamp: $ts,
    partition: $partition,
    kind: $kind,
    key: $key,
    value: (if $tombstone then null else $value end),
    tokens: $tokens,
    tombstone: $tombstone
  }')"

# 1. Write-Ahead Log (WAL) append before any window or MemTable mutation
printf '%s\n' "$wal_record" >>"$part_dir/wal.jsonl"

manifest_updated="$(jq \
  --arg partition "$partition" \
  --arg ts "$timestamp" \
  --argjson seq "$seq" \
  '.partitions[$partition].lastWalSeq = $seq
   | .partitions[$partition].updatedAt = $ts
   | .updatedAt = $ts' \
  "$ctx_dir/manifest.json")"
write_json_atomic "$ctx_dir/manifest.json" "$manifest_updated"

l0_file="$part_dir/l0-window.json"
l1_file="$part_dir/l1-memtable.json"

max_turns="$(jq -r '.config.l0MaxTurns // 8' "$ctx_dir/manifest.json")"
max_tokens="$(jq -r '.config.l0MaxTokens // 4000' "$ctx_dir/manifest.json")"
memtable_max="$(jq -r '.config.memtableMaxEntries // 16' "$ctx_dir/manifest.json")"

if [[ "$kind" == turn ]]; then
  l0_appended="$(jq \
    --argjson record "$wal_record" \
    --arg ts "$timestamp" \
    '.turns = ((.turns // []) + [$record])
     | .turnCount = (.turns | length)
     | .totalTokens = ([.turns[].tokens] | add // 0)
     | .updatedAt = $ts' \
    "$l0_file")"
  write_json_atomic "$l0_file" "$l0_appended"

  # 2. Sliding-window eviction: evict oldest L0 turns into L1 MemTable when bounds are exceeded
  while true; do
    turn_count="$(jq -r '.turnCount' "$l0_file")"
    total_tokens="$(jq -r '.totalTokens' "$l0_file")"
    if [[ "$turn_count" -le "$max_turns" ]] && { [[ "$turn_count" -le 1 ]] || [[ "$total_tokens" -le "$max_tokens" ]]; }; then
      break
    fi
    evicted="$(jq -c '.turns[0]' "$l0_file")"
    l0_trimmed="$(jq \
      --arg ts "$timestamp" \
      '.turns = (.turns[1:])
       | .turnCount = (.turns | length)
       | .totalTokens = ([.turns[].tokens] | add // 0)
       | .updatedAt = $ts' \
      "$l0_file")"
    write_json_atomic "$l0_file" "$l0_trimmed"
    upsert_memtable_entry "$l1_file" "$evicted"
  done
else
  upsert_memtable_entry "$l1_file" "$wal_record"
fi

# 3. Automatic minor LSM compaction when L1 MemTable reaches threshold
current_memtable_count="$(jq -r '.entryCount // 0' "$l1_file")"
if [[ "$current_memtable_count" -ge "$memtable_max" ]]; then
  "$ROOT/platform/context/scripts/compact.sh" "$workspace" "$work_item" --partition "$partition" --level minor >/dev/null
fi

printf '%s\n' "$wal_record"
