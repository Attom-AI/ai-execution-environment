#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/platform/install"
cp "$SOURCE_ROOT/platform/install/setup.sh" "$TEST_ROOT/platform/install/setup.sh"

# The single-quoted strings intentionally preserve variables for the fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"' \
  'mkdir -p "$ROOT/repos" "$ROOT/workspaces" "$ROOT/worktrees"' \
  ': >"$ROOT/.env"' \
  >"$TEST_ROOT/platform/install/install.sh"
chmod +x "$TEST_ROOT/platform/install/install.sh" "$TEST_ROOT/platform/install/setup.sh"

plan="$("$TEST_ROOT/platform/install/setup.sh" plan \
  --mode devcontainer --provider github --interface codex)"
[[ "$plan" == *"resolved mode:  devcontainer"* ]]
[[ "$plan" == *"provider:       github"* ]]
[[ "$plan" == *"interface:      codex"* ]]

if "$TEST_ROOT/platform/install/setup.sh" apply --mode guidance >/dev/null 2>&1; then
  printf 'error: guidance mode unexpectedly applied changes\n' >&2
  exit 1
fi

"$TEST_ROOT/platform/install/setup.sh" apply \
  --mode host --provider git --interface test >/dev/null

preferences="$TEST_ROOT/.local/state/setup/preferences.json"
jq -e '
  .version == 1 and
  .mode == "host" and
  .provider == "git" and
  .interface == "test"
' "$preferences" >/dev/null
[[ -f "$TEST_ROOT/.env" ]]
[[ -d "$TEST_ROOT/repos" ]]
[[ -d "$TEST_ROOT/workspaces" ]]
[[ -d "$TEST_ROOT/worktrees" ]]

status="$("$TEST_ROOT/platform/install/setup.sh" status)"
[[ "$status" == *'"mode": "host"'* ]]

printf 'setup profiles test passed\n'
