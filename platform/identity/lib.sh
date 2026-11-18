#!/usr/bin/env bash

set -euo pipefail

IDENTITY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$IDENTITY_ROOT/platform/repositories/lib.sh"

IDENTITIES_FILE="${IDENTITIES_FILE:-$IDENTITY_ROOT/.local/state/identities.json}"
IDENTITIES_DIR="${IDENTITIES_DIR:-$IDENTITY_ROOT/.local/state/identities}"
# Where a work item's isolated profile is mounted inside its runtime container.
IDENTITY_CONTAINER_BASE='/home/vscode/.identity'

# Credential variables that would override an isolated profile if inherited.
IDENTITY_ISOLATED_UNSET=(
  SSH_AUTH_SOCK SSH_ASKPASS GIT_ASKPASS GIT_CONFIG_PARAMETERS
  GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
  GITLAB_TOKEN GLAB_TOKEN
)

validate_identity_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid identity id: $1"
}

validate_identities() {
  require_command jq
  [[ -f "$IDENTITIES_FILE" ]] \
    || die "identity profiles not configured: $IDENTITIES_FILE (create one with platform/identity/identity.sh init)"
  jq -e '
    .version == 1 and
    (.identities | type == "object") and
    all(.identities | to_entries[];
      (.key | test("^[a-z0-9][a-z0-9-]*$")) and
      (.value.mode == "isolated" or .value.mode == "host") and
      (.value.account == null or (.value.account | type == "string" and length > 0)) and
      (.value.mode == "host" or .value.account != null) and
      ((.value.transport // "https") == "https" or .value.transport == "ssh") and
      (.value.git == null or (
        (.value.git | type == "object") and
        (.value.git.name == null or (.value.git.name | type == "string")) and
        (.value.git.email == null or (.value.git.email | type == "string"))
      ))
    )
  ' "$IDENTITIES_FILE" >/dev/null || die "invalid identity profiles: $IDENTITIES_FILE"
}

identity_profile() {
  validate_identity_id "$1"
  validate_identities
  jq -e --arg id "$1" '.identities[$id] // empty' "$IDENTITIES_FILE" \
    || die "identity profile not found: $1"
}

identity_dir() {
  validate_identity_id "$1"
  printf '%s/%s\n' "$IDENTITIES_DIR" "$1"
}

# Print the identity a project uses for `repository` or `issues` operations.
# The issue source falls back to the repository identity.
project_identity() {
  local project="$1"
  local kind="$2"
  local id
  case "$kind" in
    repository) id="$(jq -r '.repository.identity // empty' <<<"$project")" ;;
    issues) id="$(jq -r '.issues.identity // .repository.identity // empty' <<<"$project")" ;;
    *) die "invalid identity kind: $kind" ;;
  esac
  [[ -n "$id" ]] || die "project $(jq -r '.id' <<<"$project") has no $kind identity; set repository.identity in config/projects.json (a host-mode profile keeps host credentials)"
  validate_identity_id "$id"
  printf '%s\n' "$id"
}

# Print the identity recorded for a work item, failing on drift from its project.
work_item_identity() {
  local workspace="$1"
  local work_item="$2"
  local kind="$3"
  local meta="$IDENTITY_ROOT/workspaces/$workspace/$work_item/meta.json"
  local project_id project expected recorded
  [[ "$workspace" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid workspace id: $workspace"
  [[ "$work_item" =~ ^[A-Z][A-Z0-9-]*$ ]] || die "invalid work-item id: $work_item"
  [[ -f "$meta" ]] || die "work item not found: $workspace/$work_item"
  validate_projects
  project_id="$(jq -r '.project' "$meta")"
  project="$(project_by_id "$project_id")" || die "project not found: $project_id"
  expected="$(project_identity "$project" "$kind")"
  recorded="$(jq -r --arg kind "$kind" '.identity[$kind] // empty' "$meta")"
  if [[ -n "$recorded" && "$recorded" != "$expected" ]]; then
    die "identity drift for $workspace/$work_item: meta.json records $kind identity $recorded but project $project_id uses $expected; resolve before running provider commands"
  fi
  printf '%s\n' "$expected"
}

# Print NAME=value lines for an identity. Paths are emitted below <base>, which
# is the profile directory on the host or its mount point in a container;
# file existence is always checked on the host profile directory.
identity_env_lines() {
  local id="$1"
  local base="${2:-}"
  local profile mode host_dir key_file ssh_config ssh_command git_name git_email
  local -a config=()
  profile="$(identity_profile "$id")"
  mode="$(jq -r '.mode' <<<"$profile")"
  printf 'AEE_IDENTITY=%s\n' "$id"
  printf 'AEE_IDENTITY_MODE=%s\n' "$mode"
  [[ "$mode" == isolated ]] || return 0

  host_dir="$(identity_dir "$id")"
  [[ -d "$host_dir" ]] || die "identity profile directory is missing: $host_dir"
  base="${base:-$host_dir}"

  printf 'GH_CONFIG_DIR=%s\n' "$base/gh"
  printf 'GLAB_CONFIG_DIR=%s\n' "$base/glab"
  printf 'JIRA_CONFIG_DIR=%s\n' "$base/jira"
  printf 'IDENTITY_SVN_CONFIG_DIR=%s\n' "$base/svn"
  printf 'GIT_CONFIG_NOSYSTEM=1\n'
  if [[ -f "$host_dir/git/config" ]]; then
    printf 'GIT_CONFIG_GLOBAL=%s\n' "$base/git/config"
  else
    printf 'GIT_CONFIG_GLOBAL=/dev/null\n'
  fi
  printf 'GIT_TERMINAL_PROMPT=0\n'
  printf 'SSH_AUTH_SOCK=\n'

  # An empty helper resets the list, so only the profile's helpers are consulted.
  config+=(credential.helper '')
  config+=(credential.helper "store --file=$base/git/credentials")
  config+=(credential.https://github.com.helper '')
  config+=(credential.https://github.com.helper '!gh auth git-credential')
  config+=(credential.https://gitlab.com.helper '')
  config+=(credential.https://gitlab.com.helper '!glab auth git-credential')
  git_name="$(jq -r '.git.name // empty' <<<"$profile")"
  git_email="$(jq -r '.git.email // empty' <<<"$profile")"
  [[ -z "$git_name" ]] || config+=(user.name "$git_name")
  [[ -z "$git_email" ]] || config+=(user.email "$git_email")
  local index
  printf 'GIT_CONFIG_COUNT=%s\n' "$((${#config[@]} / 2))"
  for ((index = 0; index < ${#config[@]}; index += 2)); do
    printf 'GIT_CONFIG_KEY_%s=%s\n' "$((index / 2))" "${config[index]}"
    printf 'GIT_CONFIG_VALUE_%s=%s\n' "$((index / 2))" "${config[index + 1]}"
  done

  # Never consult ~/.ssh, the SSH agent, or keychain-held keys.
  ssh_config=/dev/null
  [[ ! -f "$host_dir/ssh/config" ]] || ssh_config="$base/ssh/config"
  ssh_command="ssh -F $(printf '%q' "$ssh_config") -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$(printf '%q' "$base/ssh/known_hosts")"
  local key_count=0
  if [[ -d "$host_dir/ssh" ]]; then
    while IFS= read -r key_file; do
      ssh_command+=" -i $(printf '%q' "$base/ssh/$(basename "$key_file")")"
      key_count=$((key_count + 1))
    done < <(find "$host_dir/ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print | sort)
  fi
  # Without an explicit key, ssh would fall back to default ~/.ssh identities.
  [[ "$key_count" -gt 0 ]] || ssh_command+=' -i /dev/null'
  printf 'GIT_SSH_COMMAND=%s\n' "$ssh_command"
}

# Run a command under an identity.
identity_exec() {
  local id="$1"
  shift
  local -a assignments=()
  local -a unset_args=()
  local line mode lines
  # Capture first: a failed lookup must never run the command half-isolated.
  lines="$(identity_env_lines "$id")"
  while IFS= read -r line; do
    assignments+=("$line")
  done <<<"$lines"
  mode="$(jq -r '.mode' <<<"$(identity_profile "$id")")"
  if [[ "$mode" == isolated ]]; then
    for line in "${IDENTITY_ISOLATED_UNSET[@]}"; do
      unset_args+=(-u "$line")
    done
  fi
  env ${unset_args[@]+"${unset_args[@]}"} "${assignments[@]}" "$@"
}

# SSH remotes are `ssh://...` or scp-like `user@host:path`.
IDENTITY_SSH_URL='^(ssh://|[^@/:]+@[^:/]+:)'

# Print the hosts of an identity's projects that use SSH remotes.
identity_ssh_hosts() {
  local id="$1"
  validate_projects
  jq -r --arg id "$id" --arg ssh "$IDENTITY_SSH_URL" '
    .projects[]
    | select(.repository.identity == $id and (.repository.url | test($ssh)))
    | .repository.url
    | capture("^(?:ssh://)?(?:[^@/]+@)?(?<host>[^:/]+)").host
  ' "$PROJECTS_MANIFEST" | sort -u
}

# Print "<project> <url-transport>" for projects whose remote URL disagrees
# with the identity's declared transport.
identity_transport_mismatches() {
  local id="$1"
  local transport="$2"
  validate_projects
  jq -r --arg id "$id" --arg transport "$transport" --arg ssh "$IDENTITY_SSH_URL" '
    .projects[]
    | select(.repository.identity == $id)
    | {id, url_transport: (if (.repository.url | test($ssh)) then "ssh" else "https" end)}
    | select(.url_transport != $transport)
    | "\(.id) \(.url_transport)"
  ' "$PROJECTS_MANIFEST"
}

# Verify that every credential configured for an identity authenticates as its
# declared account. Never logs in or switches accounts.
identity_check() {
  local id="$1"
  local profile mode account transport host_dir login host output checked=0 failed=0
  profile="$(identity_profile "$id")"
  mode="$(jq -r '.mode' <<<"$profile")"
  account="$(jq -r '.account // empty' <<<"$profile")"
  transport="$(jq -r '.transport // "https"' <<<"$profile")"
  host_dir="$(identity_dir "$id")"

  if [[ -z "$account" ]]; then
    printf 'identity %s: host mode without a declared account; not verified\n' "$id"
    return 0
  fi

  report() {
    local tool="$1"
    local actual="$2"
    checked=$((checked + 1))
    if [[ "$actual" == "$account" ]]; then
      printf 'identity %s: %s authenticated as %s\n' "$id" "$tool" "$actual"
    else
      printf 'identity %s: %s authenticated as %s, expected %s\n' "$id" "$tool" "${actual:-<none>}" "$account" >&2
      failed=1
    fi
  }

  if { [[ "$mode" == isolated && -d "$host_dir/gh" ]] || [[ "$mode" == host ]]; } && command -v gh >/dev/null 2>&1; then
    login="$(identity_exec "$id" gh api user --jq .login 2>/dev/null || true)"
    if [[ -n "$login" || "$mode" == isolated ]]; then
      report gh "$login"
    fi
  fi
  if { [[ "$mode" == isolated && -d "$host_dir/glab" ]] || [[ "$mode" == host ]]; } && command -v glab >/dev/null 2>&1; then
    login="$(identity_exec "$id" glab api user 2>/dev/null | jq -r '.username // empty' 2>/dev/null || true)"
    if [[ -n "$login" || "$mode" == isolated ]]; then
      report glab "$login"
    fi
  fi
  if { [[ "$mode" == isolated && -d "$host_dir/jira" ]] || [[ "$mode" == host ]]; } && command -v jira >/dev/null 2>&1; then
    login="$(identity_exec "$id" jira me 2>/dev/null | jq -r '.name // .displayName // .email // empty' 2>/dev/null || true)"
    if [[ -n "$login" || "$mode" == isolated ]]; then
      report jira "$login"
    fi
  fi
  local mismatch project url_transport
  while IFS= read -r mismatch; do
    [[ -n "$mismatch" ]] || continue
    project="${mismatch% *}"
    url_transport="${mismatch#* }"
    printf 'identity %s: project %s uses an %s remote but the identity declares %s transport\n' \
      "$id" "$project" "$url_transport" "$transport" >&2
    failed=1
  done <<<"$(identity_transport_mismatches "$id" "$transport")"
  if [[ "$transport" == ssh ]]; then
    while IFS= read -r host; do
      [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { printf 'identity %s: skipping invalid host: %s\n' "$id" "$host" >&2; failed=1; continue; }
      # Providers print the authenticated user and then refuse a shell.
      output="$(identity_exec "$id" sh -c "\$GIT_SSH_COMMAND -T git@$host" 2>&1 </dev/null || true)"
      login="$(sed -nE 's/.*Hi ([^!]+)!.*/\1/p; s/.*Welcome to GitLab, @([^!]+)!.*/\1/p; s/.*logged in as ([^ .]+).*/\1/p' <<<"$output" | head -n 1)"
      report "ssh $host" "$login"
    done < <(identity_ssh_hosts "$id")
  fi

  if [[ "$checked" -eq 0 ]]; then
    printf 'identity %s: no configured credential could be verified\n' "$id" >&2
    return 1
  fi
  [[ "$failed" -eq 0 ]]
}

# Print `devcontainer up` arguments, one per line, that give a runtime container
# exactly one identity: its isolated profile mounted at IDENTITY_CONTAINER_BASE
# and the matching environment. Host-mode identities receive no credentials.
identity_container_args() {
  local id="$1"
  local mode host_dir line lines
  mode="$(jq -r '.mode' <<<"$(identity_profile "$id")")"
  if [[ "$mode" != isolated ]]; then
    printf 'warning: identity %s uses host mode; its runtime container receives no credentials\n' "$id" >&2
    return 0
  fi
  host_dir="$(identity_dir "$id")"
  [[ "$host_dir" != *,* ]] || die "identity profile path must not contain a comma: $host_dir"
  lines="$(identity_env_lines "$id" "$IDENTITY_CONTAINER_BASE")"
  printf -- '--mount\ntype=bind,source=%s,target=%s\n' "$host_dir" "$IDENTITY_CONTAINER_BASE"
  while IFS= read -r line; do
    printf -- '--remote-env\n%s\n' "$line"
  done <<<"$lines"
}
