#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/identity/lib.sh
source "$ROOT/platform/identity/lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 list
  $0 init <id> --mode isolated --account <login> [--transport https|ssh] [--git-name <name>] [--git-email <email>]
  $0 init <id> --mode host [--account <login>]
  $0 check <id>|--all
  $0 env <id>
EOF
}

action="${1:-}"
[[ "$#" -eq 0 ]] || shift

case "$action" in
  list)
    [[ "$#" -eq 0 ]] || { usage; exit 2; }
    if [[ ! -f "$IDENTITIES_FILE" ]]; then
      printf 'no identity profiles configured (%s)\n' "$IDENTITIES_FILE"
      exit 0
    fi
    validate_identities
    validate_projects
    printf '%-24s %-9s %-24s %-9s %s\n' IDENTITY MODE ACCOUNT TRANSPORT PROJECTS
    while IFS=$'\t' read -r id mode account transport; do
      projects="$(jq -r --arg id "$id" '
        [.projects[] | select(.repository.identity == $id or (.issues.identity // .repository.identity) == $id) | .id]
        | if length == 0 then "-" else join(",") end' "$PROJECTS_MANIFEST")"
      printf '%-24s %-9s %-24s %-9s %s\n' "$id" "$mode" "$account" "$transport" "$projects"
    done < <(jq -r '.identities | to_entries[] | [.key, .value.mode, (.value.account // "-"), (.value.transport // "https")] | @tsv' "$IDENTITIES_FILE")
    ;;
  init)
    [[ "$#" -ge 1 ]] || { usage; exit 2; }
    id="$1"
    shift
    mode=''
    account=''
    transport=https
    git_name=''
    git_email=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --mode) mode="${2:-}"; shift 2 ;;
        --account) account="${2:-}"; shift 2 ;;
        --transport) transport="${2:-}"; shift 2 ;;
        --git-name) git_name="${2:-}"; shift 2 ;;
        --git-email) git_email="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    validate_identity_id "$id"
    case "$mode" in isolated|host) ;; *) die "--mode must be isolated or host" ;; esac
    case "$transport" in https|ssh) ;; *) die "--transport must be https or ssh" ;; esac
    [[ "$mode" == host || -n "$account" ]] || die "an isolated identity requires --account"

    mkdir -p "$(dirname "$IDENTITIES_FILE")"
    if [[ ! -f "$IDENTITIES_FILE" ]]; then
      (umask 077 && jq -n '{version: 1, identities: {}}' >"$IDENTITIES_FILE")
    fi
    validate_identities
    if jq -e --arg id "$id" '.identities | has($id)' "$IDENTITIES_FILE" >/dev/null; then
      die "identity profile already exists: $id"
    fi
    temporary="${IDENTITIES_FILE}.tmp"
    (umask 077 && jq \
      --arg id "$id" \
      --arg mode "$mode" \
      --arg account "$account" \
      --arg transport "$transport" \
      --arg git_name "$git_name" \
      --arg git_email "$git_email" \
      '.identities[$id] = ({mode: $mode, transport: $transport}
        + (if $account == "" then {} else {account: $account} end)
        + (if $git_name == "" and $git_email == "" then {} else {git: ({}
            + (if $git_name == "" then {} else {name: $git_name} end)
            + (if $git_email == "" then {} else {email: $git_email} end))} end))' \
      "$IDENTITIES_FILE" >"$temporary")
    mv "$temporary" "$IDENTITIES_FILE"

    if [[ "$mode" == isolated ]]; then
      profile_dir="$(identity_dir "$id")"
      (umask 077 && mkdir -p "$profile_dir/gh" "$profile_dir/git" "$profile_dir/ssh" \
        && touch "$profile_dir/git/config" "$profile_dir/git/credentials" "$profile_dir/ssh/known_hosts")
      chmod 700 "$IDENTITIES_DIR" "$profile_dir"
      printf 'created isolated identity %s at %s\n' "$id" "$profile_dir"
      printf '\nNo authentication was performed. Authenticate as %s explicitly, for example:\n' "$account"
      printf '  GitHub:    GH_CONFIG_DIR=%q gh auth login --hostname github.com --git-protocol %s --insecure-storage\n' "$profile_dir/gh" "$transport"
      printf '  GitLab:    GLAB_CONFIG_DIR=%q glab auth login\n' "$profile_dir/glab"
      printf '  Jira:      place config.yml or credentials in %q\n' "$profile_dir/jira"
      printf '  Bitbucket: add an https://<user>:<token>@bitbucket.org line to %q\n' "$profile_dir/git/credentials"
      printf '  SSH:       place a key as %q and provider host keys in %q\n' "$profile_dir/ssh/id_ed25519" "$profile_dir/ssh/known_hosts"
      printf '\nTokens are stored in files under the profile so containers can use them.\n'
    else
      printf 'created host identity %s; it uses host credentials (~/.ssh, SSH agent, keychain, global CLI logins)\n' "$id"
    fi
    printf 'Reference it from config/projects.json as repository.identity, then run: %s check %s\n' "$0" "$id"
    ;;
  check)
    [[ "$#" -eq 1 ]] || { usage; exit 2; }
    if [[ "$1" == --all ]]; then
      validate_identities
      status=0
      while IFS= read -r id; do
        identity_check "$id" || status=1
      done < <(jq -r '.identities | keys[]' "$IDENTITIES_FILE")
      exit "$status"
    fi
    identity_check "$1"
    ;;
  env)
    [[ "$#" -eq 1 ]] || { usage; exit 2; }
    identity_env_lines "$1"
    ;;
  *)
    usage
    exit 2
    ;;
esac
