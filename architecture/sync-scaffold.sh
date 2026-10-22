#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$ROOT/architecture/scaffold"
[[ "$SCAFFOLD" == "$ROOT/architecture/scaffold" ]] || {
  printf 'error: unexpected scaffold path\n' >&2
  exit 1
}

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/tree/config"

for path in .codex .editorconfig .github .gitignore AGENTS.md README.md architecture backlog documentation platform; do
  [[ -e "$ROOT/$path" ]] || continue
  tar -C "$ROOT" --exclude='architecture/scaffold' -cf - "$path" |
    tar -C "$temporary/tree" -xf -
done
cp "$ROOT/architecture/scaffold-source/projects.json" "$temporary/tree/config/projects.json"

mkdir -p "$SCAFFOLD"
find "$SCAFFOLD" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -R "$temporary/tree/." "$SCAFFOLD/"

git -C "$ROOT" diff --stat -- architecture/scaffold || true
