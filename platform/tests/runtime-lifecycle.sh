#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p \
  "$TEST_ROOT/config" \
  "$TEST_ROOT/repos" \
  "$TEST_ROOT/workspaces/fixture/FEAT-1" \
  "$TEST_ROOT/worktrees"
cp -R "$SOURCE_ROOT/platform" "$TEST_ROOT/platform"

git init -q --bare --initial-branch=main "$TEST_ROOT/origin.git"
git init -q --initial-branch=main "$TEST_ROOT/seed"
printf 'fixture\n' >"$TEST_ROOT/seed/README.md"
git -C "$TEST_ROOT/seed" add README.md
git -C "$TEST_ROOT/seed" \
  -c user.name=Test -c user.email=test@example.invalid \
  commit -q -m fixture
git -C "$TEST_ROOT/seed" remote add origin "$TEST_ROOT/origin.git"
git -C "$TEST_ROOT/seed" push -q -u origin main
git clone -q "$TEST_ROOT/origin.git" "$TEST_ROOT/repos/fixture"

jq -n --arg url "$TEST_ROOT/origin.git" '{
  version: 1,
  projects: [{
    id: "fixture",
    workspace: "fixture",
    repository: {
      provider: "github",
      owner: "example",
      name: "fixture",
      url: $url,
      path: "repos/fixture"
    },
    issues: {
      provider: "github",
      owner: "example",
      repository: "fixture"
    }
  }]
}' >"$TEST_ROOT/config/projects.json"

jq '
  .workspace = "fixture"
  | .workItem = "FEAT-1"
  | .project = "fixture"
  | .design.branch = "feat/1-fixture"
' "$SOURCE_ROOT/platform/state/templates/meta.json" \
  >"$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json"
: >"$TEST_ROOT/workspaces/fixture/FEAT-1/history.log"

git -C "$TEST_ROOT/repos/fixture" switch -q -c human-work
printf 'human change\n' >>"$TEST_ROOT/repos/fixture/README.md"
canonical_branch_before="$(git -C "$TEST_ROOT/repos/fixture" branch --show-current)"
canonical_status_before="$(git -C "$TEST_ROOT/repos/fixture" status --porcelain)"

"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1 --no-container
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1 --no-container

[[ "$(git -C "$TEST_ROOT/repos/fixture" branch --show-current)" == "$canonical_branch_before" ]]
[[ "$(git -C "$TEST_ROOT/repos/fixture" status --porcelain)" == "$canonical_status_before" ]]
[[ "$(git -C "$TEST_ROOT/worktrees/fixture-feat-1" rev-parse HEAD)" == \
   "$(git -C "$TEST_ROOT/repos/fixture" rev-parse origin/main)" ]]

printf 'uncommitted\n' >>"$TEST_ROOT/worktrees/fixture-feat-1/README.md"
if "$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-1 2>/dev/null; then
  printf 'error: stop removed a dirty worktree\n' >&2
  exit 1
fi
git -C "$TEST_ROOT/worktrees/fixture-feat-1" restore README.md

"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-1
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1 --no-container
"$TEST_ROOT/platform/runtime/scripts/close.sh" fixture FEAT-1 abandoned

jq -e '
  .lifecycleStage == "closed" and
  .closed.reason == "abandoned" and
  .runtime.status == "stopped" and
  .runtime.worktree == null and
  .runtime.containerId == null
' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json" >/dev/null

printf 'runtime lifecycle test passed\n'
