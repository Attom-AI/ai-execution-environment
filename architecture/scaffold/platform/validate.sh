#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=platform/repositories/lib.sh
source "$ROOT/platform/repositories/lib.sh"

validate_projects

required_paths=(
  .agents/skills/work-item-execution/SKILL.md
  .claude/settings.json
  .claude/skills/work-item-execution/SKILL.md
  .codex/skills/work-item-execution/SKILL.md
  CLAUDE.md
  platform/context/scripts/init.sh
  platform/context/templates/manifest.json
  platform/install/setup.sh
  platform/install/templates/.env.example
  platform/interfaces/claude/hooks/guard-outbound.sh
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
  (.runtime | type == "object") and
  (.runtime.poolSlot == null)
' "$ROOT/platform/state/templates/meta.json" >/dev/null \
  || die "invalid work-item state template"

jq -e '
  .schemaVersion == 1 and
  (.activePartition == "main") and
  (.lastSeq == 0) and
  (.config | type == "object") and
  (.partitions | type == "object")
' "$ROOT/platform/context/templates/manifest.json" >/dev/null \
  || die "invalid context manifest template"

for skill in "$ROOT"/.agents/skills/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$skill")")"
  for interface_dir in .codex .claude; do
    cmp -s "$skill" "$ROOT/$interface_dir/skills/$skill_name/SKILL.md" \
      || die "interface skill differs from .agents: $interface_dir/skills/$skill_name/SKILL.md"
  done
done

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
  portable_paths=(.agents .claude .codex .editorconfig .github .gitignore AGENTS.md CLAUDE.md README.md backlog documentation platform)
  for portable_path in "${portable_paths[@]}"; do
    diff -qr "$ROOT/$portable_path" "$ROOT/architecture/scaffold/$portable_path" >/dev/null \
      || die "portable scaffold is stale: $portable_path"
  done
  diff -qr --exclude=scaffold "$ROOT/architecture" "$ROOT/architecture/scaffold/architecture" >/dev/null \
    || die "portable scaffold is stale: architecture"
fi

printf 'execution environment is valid\n'
