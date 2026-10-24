#!/usr/bin/env bash

set -euo pipefail

missing=0

for command_name in bash devcontainer docker envsubst git gh jq rg shellcheck; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$command_name"
  else
    printf 'missing %s\n' "$command_name" >&2
    missing=1
  fi
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_config="$root/platform/runtime/.devcontainer/devcontainer.json"
if command -v jq >/dev/null 2>&1 && jq -e '
  .features
  | has("ghcr.io/devcontainers/features/hugo:1") and
    has("ghcr.io/devcontainers/features/java:1")
' "$runtime_config" >/dev/null; then
  printf 'configured runtime:hugo\n'
  printf 'configured runtime:sdkman\n'
else
  printf 'missing runtime Hugo/SDKMAN feature configuration\n' >&2
  missing=1
fi

if command -v gh >/dev/null 2>&1; then
  # The host's global login is reported for comparison only; isolated
  # identities never use it.
  global_account="$(gh auth status --active 2>/dev/null | sed -nE 's/.*Logged in to [^ ]+ account ([^ ]+).*/\1/p' | head -n 1)"
  printf 'info    global github account: %s (used only by host-mode identities)\n' "${global_account:-none}"
fi

if command -v jq >/dev/null 2>&1; then
  # shellcheck source=platform/identity/lib.sh
  source "$root/platform/identity/lib.sh"
  if [[ ! -f "$IDENTITIES_FILE" ]]; then
    printf 'missing identity profiles (create with: platform/identity/identity.sh init)\n' >&2
  elif ! (validate_identities) 2>/dev/null; then
    printf 'invalid identity profiles: %s\n' "$IDENTITIES_FILE" >&2
    missing=1
  else
    while IFS=$'\t' read -r id mode account transport; do
      credentials='host'
      if [[ "$mode" == isolated ]]; then
        profile_dir="$(identity_dir "$id")"
        credentials=''
        [[ ! -s "$profile_dir/gh/hosts.yml" ]] || credentials+='gh '
        [[ ! -d "$profile_dir/glab" ]] || credentials+='glab '
        [[ ! -s "$profile_dir/git/credentials" ]] || credentials+='git-credentials '
        if find "$profile_dir/ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null | grep -q .; then
          credentials+='ssh-key '
          [[ -s "$profile_dir/ssh/known_hosts" ]] || printf 'missing known_hosts for identity %s (SSH host keys are verified strictly)\n' "$id" >&2
        fi
        credentials="${credentials% }"
        if [[ -z "$credentials" ]]; then
          credentials='none'
          printf 'missing credentials for identity %s (authenticate explicitly; see platform/identity/README.md)\n' "$id" >&2
        fi
      fi
      printf 'ok      identity %s mode=%s account=%s transport=%s credentials=%s\n' "$id" "$mode" "$account" "$transport" "$credentials"
    done < <(jq -r '.identities | to_entries[] | [.key, .value.mode, (.value.account // "-"), (.value.transport // "https")] | @tsv' "$IDENTITIES_FILE")
    printf 'info    run platform/identity/identity.sh check --all to verify accounts online\n'
  fi
  if [[ -f "$PROJECTS_MANIFEST" ]]; then
    while IFS= read -r project_id; do
      printf 'missing identity for project %s (set repository.identity in config/projects.json)\n' "$project_id" >&2
      missing=1
    done < <(jq -r '.projects[]? | select(.repository.identity == null) | .id' "$PROJECTS_MANIFEST")
  fi
fi
if [[ -f "$root/.env" ]] && grep -q '^GH_CONFIG_DIR=' "$root/.env"; then
  printf 'warning GH_CONFIG_DIR in .env is retired; credentials now come from identity profiles\n' >&2
fi

if [[ "$missing" -ne 0 ]]; then
  printf '\nInstall the missing tools before running work-item automation.\n' >&2
fi
