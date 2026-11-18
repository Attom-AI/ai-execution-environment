#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'usage: %s <issue-key-or-url-or-number> [--repo <owner/project-key>]\n' "$0" >&2
}

issue_ref=''
repository_arg=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo) repository_arg="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      [[ -z "$issue_ref" ]] || { usage; exit 2; }
      issue_ref="$1"
      shift
      ;;
  esac
done

[[ -n "$issue_ref" ]] || { usage; exit 2; }

owner=''
project_key=''
number=''

# 1. Full Jira URL: https://<domain>/browse/<KEY>-<NUM> or https://<domain>/jira/browse/<KEY>-<NUM>
if [[ "$issue_ref" =~ ^https?://([^/]+)(/[^/]+)*/browse/([A-Za-z0-9_]+)-([0-9]+)/?$ ]]; then
  owner="${BASH_REMATCH[1]}"
  project_key="$(printf '%s' "${BASH_REMATCH[3]}" | tr '[:lower:]' '[:upper:]')"
  number="${BASH_REMATCH[4]}"

# 2. Key format: <KEY>-<NUM> (e.g. PROJ-123 or KAN-42)
elif [[ "$issue_ref" =~ ^([A-Za-z0-9_]+)-([0-9]+)$ ]]; then
  project_key="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
  number="${BASH_REMATCH[2]}"
  if [[ "$repository_arg" =~ ^([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
  fi

# 3. Bare number: <NUM> with --repo <owner/project-key> or --repo <project-key>
elif [[ "$issue_ref" =~ ^[0-9]+$ ]]; then
  number="$issue_ref"
  if [[ "$repository_arg" =~ ^([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    project_key="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]')"
  elif [[ -n "$repository_arg" ]]; then
    project_key="$(printf '%s' "$repository_arg" | tr '[:lower:]' '[:upper:]')"
  else
    printf 'error: pass a Jira issue key (e.g. PROJ-123) or a number with --repo owner/project\n' >&2
    exit 2
  fi
else
  printf 'error: unable to parse Jira issue reference: %s\n' "$issue_ref" >&2
  exit 2
fi

key="${project_key}-${number}"

if [[ -z "$owner" ]]; then
  if [[ "$repository_arg" =~ ^([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
  else
    owner="${JIRA_HOST:-${JIRA_URL:-atlassian}}"
    owner="${owner#https://}"
    owner="${owner#http://}"
    owner="${owner%%/*}"
  fi
fi

# Determine issue URL
if [[ "$owner" == *.* ]]; then
  issue_url="https://${owner}/browse/${key}"
  jira_base_url="https://${owner}"
else
  issue_url="https://${owner}.atlassian.net/browse/${key}"
  jira_base_url="https://${owner}.atlassian.net"
fi

raw=''

# --- Data Fetch Ladder ---

# Ladder 1: Test / Mock Payload
if [[ -n "${AEE_TEST_JIRA_PAYLOAD:-}" ]]; then
  if [[ -f "$AEE_TEST_JIRA_PAYLOAD" ]]; then
    raw="$(cat "$AEE_TEST_JIRA_PAYLOAD")"
  else
    raw="$AEE_TEST_JIRA_PAYLOAD"
  fi
elif [[ -n "${JIRA_MOCK_PAYLOAD:-}" ]]; then
  if [[ -f "$JIRA_MOCK_PAYLOAD" ]]; then
    raw="$(cat "$JIRA_MOCK_PAYLOAD")"
  else
    raw="$JIRA_MOCK_PAYLOAD"
  fi

# Ladder 2: jira-cli (if available)
elif command -v jira >/dev/null 2>&1; then
  raw="$(jira issue view "$key" --output json 2>/dev/null || true)"
fi

# Ladder 3: Direct Jira REST API via curl
if [[ -z "$raw" ]]; then
  jira_token="${JIRA_API_TOKEN:-}"
  jira_user="${JIRA_USER:-${JIRA_EMAIL:-}}"
  jira_cfg="${JIRA_CONFIG_DIR:-}"

  if [[ -z "$jira_token" && -n "$jira_cfg" && -f "$jira_cfg/credentials" ]]; then
    # Load credentials file if formatted as JIRA_API_TOKEN=...
    # shellcheck disable=SC1090,SC1091
    source "$jira_cfg/credentials" 2>/dev/null || true
    jira_token="${JIRA_API_TOKEN:-}"
    jira_user="${jira_user:-${JIRA_USER:-${JIRA_EMAIL:-}}}"
  fi

  if [[ -n "$jira_token" ]]; then
    auth_header=""
    if [[ -n "$jira_user" ]]; then
      auth_b64="$(printf '%s:%s' "$jira_user" "$jira_token" | base64)"
      auth_header="Authorization: Basic ${auth_b64}"
    else
      auth_header="Authorization: Bearer ${jira_token}"
    fi

    api_endpoint="${jira_base_url}/rest/api/2/issue/${key}"
    raw="$(curl -s -f -H "Accept: application/json" -H "$auth_header" "$api_endpoint" 2>/dev/null || true)"
  fi
fi

if [[ -z "$raw" ]]; then
  printf 'error: unable to fetch Jira issue %s. Ensure jira CLI is installed or configure Jira credentials in your identity profile.\n' "$key" >&2
  exit 1
fi

# Extract and normalize fields
title="$(jq -r '.fields.summary // .summary // empty' <<<"$raw")"
if [[ -z "$title" ]]; then
  title="$key"
fi

body="$(jq -r '
  if .fields.description == null then ""
  elif (.fields.description | type == "string") then .fields.description
  elif (.fields.description | type == "object") then ([.. | .text? // empty] | join(" "))
  else (.fields.description | tostring)
  end
' <<<"$raw")"

native_type="$(jq -r '.fields.issuetype.name // .issuetype.name // .issueType.name // empty | ascii_downcase' <<<"$raw")"
case "$native_type" in
  bug) item_type=FIX ;;
  story|feature|*feature*) item_type=FEAT ;;
  task|sub-task|subtask|*task*|spike|chore) item_type=TASK ;;
  improvement|enhancement) item_type=FEAT ;;
  *) item_type='' ;;
esac

if [[ -z "$item_type" ]]; then
  labels_str=",$(jq -r '[.fields.labels[]? // .labels[]? // empty | ascii_downcase] | join(",")' <<<"$raw"),"
  if [[ "$labels_str" == *',bug,'* ]]; then
    item_type=FIX
  elif [[ "$labels_str" == *',feature,'* || "$labels_str" == *',enhancement,'* ]]; then
    item_type=FEAT
  elif [[ "$labels_str" == *',task,'* || "$labels_str" == *',chore,'* ]]; then
    item_type=TASK
  fi
fi

if [[ -z "$item_type" ]]; then
  title_lower="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"
  if [[ "$title_lower" =~ (fix|bug|patch|resolv|correct|crash|broken) ]]; then
    item_type=FIX
  elif [[ "$title_lower" =~ (feat|add|support|new|implement|replac|redesign|enhanc) ]]; then
    item_type=FEAT
  else
    item_type=TASK
  fi
fi

jq -n \
  --arg source jira \
  --arg key "$key" \
  --arg owner "$owner" \
  --arg repository "$project_key" \
  --argjson number "$number" \
  --arg url "$issue_url" \
  --arg title "$title" \
  --arg body "$body" \
  --arg type "$item_type" \
  --argjson raw "$raw" \
  '{
    source: $source,
    key: $key,
    owner: $owner,
    repository: $repository,
    number: $number,
    url: $url,
    title: $title,
    body: $body,
    type: (if $type == "" then null else $type end),
    labels: [($raw.fields.labels[]? // $raw.labels[]? // empty)],
    raw: $raw
  }'
