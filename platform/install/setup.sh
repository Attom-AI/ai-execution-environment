#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${SETUP_STATE_DIR:-$ROOT/.local/state/setup}"
PREFERENCES_FILE="$STATE_DIR/preferences.json"

action="${1:-plan}"
[[ "$#" -eq 0 ]] || shift
mode="${SETUP_MODE:-auto}"
interface="${AGENT_INTERFACE:-unspecified}"
provider="${GIT_PROVIDER:-auto}"

usage() {
  printf 'usage: %s <plan|apply|status> [--mode auto|devcontainer|host|guidance] [--interface name] [--provider auto|github|gitlab|bitbucket|git|none]\n' "$0" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --interface) interface="${2:-}"; shift 2 ;;
    --provider) provider="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
done

case "$action" in plan|apply|status) ;; *) usage; die "unknown action: $action" ;; esac
case "$mode" in auto|devcontainer|host|guidance) ;; *) die "unsupported mode: $mode" ;; esac
case "$provider" in auto|github|gitlab|bitbucket|git|none) ;; *) die "unsupported provider: $provider" ;; esac
[[ -n "$interface" && "$interface" != *$'\n'* && "$interface" != *$'\r'* ]] \
  || die "interface must be a non-empty single-line label"

resolved_mode="$mode"
if [[ "$resolved_mode" == auto ]]; then
  resolved_mode=devcontainer
fi

resolved_provider="$provider"
if [[ "$resolved_provider" == auto ]]; then
  if command -v gh >/dev/null 2>&1; then
    resolved_provider=github
  elif command -v glab >/dev/null 2>&1; then
    resolved_provider=gitlab
  else
    resolved_provider=git
  fi
fi

command_state() {
  if command -v "$1" >/dev/null 2>&1; then
    printf available
  else
    printf 'not installed'
  fi
}

print_plan() {
  printf 'Agent-guided setup plan\n'
  printf '  requested mode: %s\n' "$mode"
  printf '  resolved mode:  %s\n' "$resolved_mode"
  printf '  interface:      %s\n' "$interface"
  printf '  provider:       %s\n' "$resolved_provider"
  printf '\nDetected commands:\n'
  for command_name in git jq rg gh glab docker devcontainer shellcheck; do
    printf '  %-12s %s\n' "$command_name" "$(command_state "$command_name")"
  done
  printf '\nProfile behavior:\n'
  case "$resolved_mode" in
    devcontainer)
      printf '  Project work runs in the shared, work-item-specific devcontainer.\n'
      printf '  Host-local credentials are mounted only into that runtime.\n'
      ;;
    host)
      printf '  Project work uses the dedicated worktree directly on this host.\n'
      printf '  Host tools and credential context are shared intentionally.\n'
      ;;
    guidance)
      printf '  Commands are presented for the operator; apply remains disabled.\n'
      ;;
  esac
  printf '\nNo authentication, cloning, installation, or remote changes were performed.\n'
}

if [[ "$action" == status ]]; then
  if [[ ! -f "$PREFERENCES_FILE" ]]; then
    printf 'No saved setup preferences.\n'
    exit 0
  fi
  command -v jq >/dev/null 2>&1 || die "jq is required to read saved preferences"
  jq . "$PREFERENCES_FILE"
  exit 0
fi

print_plan
[[ "$action" == plan ]] && exit 0
[[ "$resolved_mode" != guidance ]] || die "guidance mode is read-only"

"$ROOT/platform/install/install.sh"
mkdir -p "$STATE_DIR"
temporary="${PREFERENCES_FILE}.tmp"
jq -n \
  --arg mode "$resolved_mode" \
  --arg interface "$interface" \
  --arg provider "$resolved_provider" \
  '{version: 1, mode: $mode, interface: $interface, provider: $provider}' \
  >"$temporary"
mv "$temporary" "$PREFERENCES_FILE"

printf '\nSaved local preferences to %s\n' "$PREFERENCES_FILE"
printf 'Authentication and repository onboarding remain separate explicit steps.\n'
