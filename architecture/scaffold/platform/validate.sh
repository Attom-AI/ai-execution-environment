#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

validate_projects

required_paths=(
  .codex/skills/work-item-execution/SKILL.md
  platform/install/templates/.env.example
  platform/repositories/providers/github.sh
  platform/runtime/.devcontainer/devcontainer.json
  platform/state/templates/meta.json
  platform/workflows/agents/ticket-coordinator.md
  platform/workspace-scaffolder/sources/github.sh
)
for required_path in "${required_paths[@]}"; do
  [[ -e "$ROOT/$required_path" ]] || die "required portable component is missing: $required_path"
done

jq -e '
  .schemaVersion == 1 and
  (.lifecycleStage | type == "string") and
  (.gates | type == "object") and
  (.loops | type == "object") and
  (.resume | type == "object") and
  (.blocked | type == "object") and
  (.closed | type == "object") and
  (.runtime | type == "object")
' "$ROOT/platform/state/templates/meta.json" >/dev/null \
  || die "invalid work-item state template"

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_materialized="$(git -C "$ROOT" ls-files \
    'repos/**' 'workspaces/**' 'worktrees/**' '.local/**' '.env')"
  [[ -z "$tracked_materialized" ]] || die "materialized paths are tracked:\n$tracked_materialized"
fi

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT" \
  -path "$ROOT/repos" -prune -o \
  -path "$ROOT/workspaces" -prune -o \
  -path "$ROOT/worktrees" -prune -o \
  -path "$ROOT/.local" -prune -o \
  -name '*.sh' -type f -print | sort)

if command -v shellcheck >/dev/null 2>&1; then
  shell_scripts=()
  while IFS= read -r script; do
    shell_scripts+=("$script")
  done < <(find "$ROOT" \
    -path "$ROOT/repos" -prune -o \
    -path "$ROOT/workspaces" -prune -o \
    -path "$ROOT/worktrees" -prune -o \
    -path "$ROOT/.local" -prune -o \
    -name '*.sh' -type f -print | sort)
  if [[ "${#shell_scripts[@]}" -gt 0 ]]; then
    (cd "$ROOT" && shellcheck "${shell_scripts[@]}")
  fi
else
  printf 'warning: shellcheck not installed; static shell analysis skipped\n' >&2
fi

while IFS= read -r json_file; do
  jq -e . "$json_file" >/dev/null
done < <(find "$ROOT" \
  -path "$ROOT/repos" -prune -o \
  -path "$ROOT/workspaces" -prune -o \
  -path "$ROOT/worktrees" -prune -o \
  -path "$ROOT/.local" -prune -o \
  -name '*.json' -type f -print)

if [[ -d "$ROOT/architecture/scaffold" ]]; then
  jq -e '.version == 1 and .projects == []' \
    "$ROOT/architecture/scaffold/config/projects.json" >/dev/null \
    || die "portable scaffold must contain an empty project inventory"
  portable_paths=(.codex .editorconfig .github .gitignore AGENTS.md README.md backlog documentation platform)
  for portable_path in "${portable_paths[@]}"; do
    diff -qr "$ROOT/$portable_path" "$ROOT/architecture/scaffold/$portable_path" >/dev/null \
      || die "portable scaffold is stale: $portable_path"
  done
  diff -qr --exclude=scaffold "$ROOT/architecture" "$ROOT/architecture/scaffold/architecture" >/dev/null \
    || die "portable scaffold is stale: architecture"
fi

printf 'execution environment is valid\n'
