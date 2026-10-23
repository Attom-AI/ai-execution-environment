#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p \
  "$TEST_ROOT/bin" \
  "$TEST_ROOT/config" \
  "$TEST_ROOT/docker-state" \
  "$TEST_ROOT/repos" \
  "$TEST_ROOT/workspaces/fixture" \
  "$TEST_ROOT/worktrees"
cp -R "$SOURCE_ROOT/platform" "$TEST_ROOT/platform"

cat >"$TEST_ROOT/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${DOCKER_STATE_DIR:?}"
case "${1:-}" in
  inspect)
    if [[ "${2:-}" == -f ]]; then
      id="${4:-}"
      [[ -f "$state/$id" ]] || exit 1
      if [[ -f "$state/$id.running" ]]; then printf 'running\n'; else printf 'exited\n'; fi
    else
      [[ -f "$state/${2:-}" ]]
    fi
    ;;
  start)
    [[ -f "$state/${2:-}" ]]
    touch "$state/${2:-}.running"
    ;;
  stop)
    [[ -f "$state/${2:-}" ]]
    rm -f "$state/${2:-}.running"
    ;;
  rm)
    id="${@: -1}"
    rm -f "$state/$id" "$state/$id.running"
    ;;
  *) exit 2 ;;
esac
EOF

cat >"$TEST_ROOT/bin/devcontainer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${DOCKER_STATE_DIR:?}"
[[ "${1:-}" == up ]]
counter=0
[[ ! -f "$state/counter" ]] || counter="$(<"$state/counter")"
counter=$((counter + 1))
printf '%s\n' "$counter" >"$state/counter"
id="container-$counter"
touch "$state/$id" "$state/$id.running"
printf '{"containerId":"%s"}\n' "$id"
EOF
chmod +x "$TEST_ROOT/bin/docker" "$TEST_ROOT/bin/devcontainer"
export DOCKER_STATE_DIR="$TEST_ROOT/docker-state"
export PATH="$TEST_ROOT/bin:$PATH"
export RUNTIME_POOL_SIZE=3

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

create_item() {
  local number="$1"
  local item="FEAT-$number"
  local directory="$TEST_ROOT/workspaces/fixture/$item"
  mkdir -p "$directory"
  jq \
    --arg item "$item" \
    --arg branch "feat/$number-fixture" \
    '.workspace = "fixture"
     | .workItem = $item
     | .project = "fixture"
     | .design.branch = $branch' \
    "$SOURCE_ROOT/platform/state/templates/meta.json" >"$directory/meta.json"
  : >"$directory/history.log"
}

for number in 1 2 3 4; do
  create_item "$number"
done

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
grep -Eq '^gitdir: \.\./\.\./repos/fixture/\.git/worktrees/' \
  "$TEST_ROOT/worktrees/fixture-feat-1/.git"

printf 'uncommitted\n' >>"$TEST_ROOT/worktrees/fixture-feat-1/README.md"
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-1
[[ -d "$TEST_ROOT/worktrees/fixture-feat-1" ]]
git -C "$TEST_ROOT/worktrees/fixture-feat-1" restore README.md

"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1
first_container="$(jq -r '.runtime.containerId' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json")"
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json")" == 1 ]]
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1
[[ "$(jq -r '.runtime.containerId' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json")" == "$first_container" ]]

"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-2
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-3
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-2/meta.json")" == 2 ]]
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-3/meta.json")" == 3 ]]
if "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 2>/dev/null; then
  printf 'error: fourth container exceeded the configured pool capacity\n' >&2
  exit 1
fi

"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-1
[[ -f "$DOCKER_STATE_DIR/$first_container" ]]
[[ ! -f "$DOCKER_STATE_DIR/$first_container.running" ]]
[[ -d "$TEST_ROOT/worktrees/fixture-feat-1" ]]
jq -e \
  --arg id "$first_container" \
  '.runtime.status == "stopped" and
   .runtime.containerId == $id and
   .runtime.poolSlot == 1' \
  "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json" >/dev/null

"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-1
[[ -f "$DOCKER_STATE_DIR/$first_container.running" ]]
printf 'uncommitted\n' >>"$TEST_ROOT/worktrees/fixture-feat-1/README.md"
if "$TEST_ROOT/platform/runtime/scripts/close.sh" fixture FEAT-1 abandoned 2>/dev/null; then
  printf 'error: close removed a dirty worktree\n' >&2
  exit 1
fi
git -C "$TEST_ROOT/worktrees/fixture-feat-1" restore README.md
"$TEST_ROOT/platform/runtime/scripts/close.sh" fixture FEAT-1 abandoned
[[ ! -e "$DOCKER_STATE_DIR/$first_container" ]]
[[ ! -e "$TEST_ROOT/worktrees/fixture-feat-1" ]]

"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-4/meta.json")" == 1 ]]

jq -e '
  .lifecycleStage == "closed" and
  .closed.reason == "abandoned" and
  .runtime.status == "stopped" and
  .runtime.worktree == null and
  .runtime.containerId == null and
  .runtime.poolSlot == null
' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json" >/dev/null

printf 'runtime lifecycle test passed\n'
