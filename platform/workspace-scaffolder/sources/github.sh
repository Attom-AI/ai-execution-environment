#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'usage: %s <owner> <repository> <issue-number>\n' "$0" >&2
  exit 2
fi

owner="$1"
repository="$2"
issue_number="$3"

command -v gh >/dev/null 2>&1 || {
  printf 'error: required command not found: gh\n' >&2
  exit 1
}

gh issue view "$issue_number" \
  --repo "$owner/$repository" \
  --json number,title,body,state,url,labels,assignees
