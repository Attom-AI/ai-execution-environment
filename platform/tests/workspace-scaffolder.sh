#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/workspaces" "$TEST_ROOT/worktrees"
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
      path: "repos/fixture",
      identity: "fixture"
    },
    issues: {
      provider: "github",
      owner: "example",
      repository: "fixture"
    }
  }]
}' >"$TEST_ROOT/config/projects.json"
mkdir -p "$TEST_ROOT/.local/state"
jq -n '{version: 1, identities: {fixture: {mode: "host"}}}' >"$TEST_ROOT/.local/state/identities.json"

gh() {
  jq -n '{
    issueType: {name: "Feature"},
    labels: [{name: "enhancement"}],
    title: "Exercise normalized intake",
    body: "Fixture issue body",
    number: 7,
    url: "https://github.com/example/fixture/issues/7",
    state: "OPEN"
  }'
}
export -f gh

"$TEST_ROOT/platform/workspace-scaffolder/scaffold.sh" fixture 7 --no-start
item="$TEST_ROOT/workspaces/fixture/FEAT-7"
jq -e '
  .source == "github" and
  .number == 7 and
  .type == "FEAT" and
  .raw.number == 7 and
  .workItem == "FEAT-7"
' "$item/ticket.json" >/dev/null
jq -e '
  .lifecycleStage == "scaffolded" and
  .design.branch == "feat/7-exercise-normalized-intake" and
  .identity == {repository: "fixture", issues: "fixture"} and
  .resume.nextAgent == "issue-refinement"
' "$item/meta.json" >/dev/null

jq '.lifecycleStage = "designed"' "$item/meta.json" >"$item/meta.json.tmp"
mv "$item/meta.json.tmp" "$item/meta.json"
"$TEST_ROOT/platform/workspace-scaffolder/scaffold.sh" fixture 7 --no-start
jq -e '.lifecycleStage == "designed"' "$item/meta.json" >/dev/null

[[ -f "$item/session-state.md" ]]
[[ -f "$item/README.md" ]]
[[ -f "$item/history.log" ]]
[[ -d "$item/artifacts" ]]
[[ ! -e "$TEST_ROOT/worktrees/fixture-feat-7" ]]

printf 'workspace scaffolder test passed\n'
