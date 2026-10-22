#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'usage: %s clone <url> <target> | sync <repository> | default-branch <repository>\n' "$0" >&2
}

operation="${1:-}"
case "$operation" in
  clone)
    [[ "$#" -eq 3 ]] || { usage; exit 2; }
    git clone -- "$2" "$3"
    ;;
  sync)
    [[ "$#" -eq 2 ]] || { usage; exit 2; }
    repository="$2"
    default_branch="$(git -C "$repository" ls-remote --symref origin HEAD | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2; exit}')"
    [[ -n "$default_branch" ]] || {
      printf 'error: unable to resolve remote default branch for %s\n' "$repository" >&2
      exit 1
    }
    git -C "$repository" fetch --prune origin "$default_branch"
    git -C "$repository" remote set-head origin "$default_branch"
    printf '%s\n' "$default_branch"
    ;;
  default-branch)
    [[ "$#" -eq 2 ]] || { usage; exit 2; }
    git -C "$2" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##'
    ;;
  *)
    usage
    exit 2
    ;;
esac
