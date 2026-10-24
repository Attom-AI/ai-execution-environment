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
if [[ "${DOCKER_DAEMON_DOWN:-0}" == 1 ]]; then
  printf 'Cannot connect to the Docker daemon\n' >&2
  exit 1
fi
case "${1:-}" in
  inspect)
    if [[ "${2:-}" == -f ]]; then
      id="${4:-}"
      if [[ ! -f "$state/$id" ]]; then
        printf 'Error: No such object: %s\n' "$id" >&2
        exit 1
      fi
      if [[ -f "$state/$id.running" ]]; then printf 'running\n'; else printf 'exited\n'; fi
    else
      if [[ ! -f "$state/${2:-}" ]]; then
        printf 'Error: No such object: %s\n' "${2:-}" >&2
        exit 1
      fi
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
  ps)
    if [[ -n "${DOCKER_PS_DELAY:-}" ]]; then
      sleep "$DOCKER_PS_DELAY"
    fi
    for f in "$state"/container-*; do
      [[ -f "$f" && "$f" != *.running ]] || continue
      basename "$f"
    done
    ;;
  *) exit 2 ;;
esac
EOF

cat >"$TEST_ROOT/bin/devcontainer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${DOCKER_STATE_DIR:?}"
[[ "${1:-}" == up ]]
if [[ "${DEVCONTAINER_FAIL:-0}" == 1 ]]; then
  printf 'devcontainer up failed\n' >&2
  exit 1
fi
counter=0
[[ ! -f "$state/counter" ]] || counter="$(<"$state/counter")"
counter=$((counter + 1))
printf '%s\n' "$counter" >"$state/counter"
id="container-$counter"
printf '%s\n' "$@" >"$state/$id.args"
touch "$state/$id" "$state/$id.running"
if [[ -n "${DEVCONTAINER_DELAY:-}" ]]; then
  sleep "$DEVCONTAINER_DELAY"
fi
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
mkdir -p "$TEST_ROOT/.local/state/identities/fixture/gh"
jq -n '{version: 1, identities: {fixture: {mode: "isolated", account: "fixture-bot"}}}' \
  >"$TEST_ROOT/.local/state/identities.json"

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
# The container receives exactly the work item's identity profile.
grep -Fxq "type=bind,source=$TEST_ROOT/.local/state/identities/fixture,target=/home/vscode/.identity" \
  "$DOCKER_STATE_DIR/$first_container.args"
grep -Fxq 'GH_CONFIG_DIR=/home/vscode/.identity/gh' "$DOCKER_STATE_DIR/$first_container.args"
[[ "$(grep -c -- '^--mount$' "$DOCKER_STATE_DIR/$first_container.args")" -eq 1 ]]
[[ "$(jq -r '.runtime.identity' "$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json")" == fixture ]]
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

# Slot management tests (slots.sh)
slots_out="$("$TEST_ROOT/platform/runtime/scripts/slots.sh" status)"
grep -Fq 'Pool capacity: 3 slots (3 running, 0 stopped, 0 reserved, 0 free)' <<<"$slots_out"

"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-2
slots_out="$("$TEST_ROOT/platform/runtime/scripts/slots.sh" status)"
grep -Fq 'Pool capacity: 3 slots (2 running, 1 stopped, 0 reserved, 0 free)' <<<"$slots_out"

feat2_container="$(jq -r '.runtime.containerId' "$TEST_ROOT/workspaces/fixture/FEAT-2/meta.json")"
"$TEST_ROOT/platform/runtime/scripts/slots.sh" release 2
[[ ! -e "$DOCKER_STATE_DIR/$feat2_container" ]]
[[ -d "$TEST_ROOT/worktrees/fixture-feat-2" ]]
jq -e '
  .lifecycleStage != "closed" and
  .runtime.status == "worktree-ready" and
  .runtime.worktree == "worktrees/fixture-feat-2" and
  .runtime.containerId == null and
  .runtime.poolSlot == null
' "$TEST_ROOT/workspaces/fixture/FEAT-2/meta.json" >/dev/null

feat3_old_container="$(jq -r '.runtime.containerId' "$TEST_ROOT/workspaces/fixture/FEAT-3/meta.json")"
"$TEST_ROOT/platform/runtime/scripts/slots.sh" recreate 3
feat3_new_container="$(jq -r '.runtime.containerId' "$TEST_ROOT/workspaces/fixture/FEAT-3/meta.json")"
[[ "$feat3_new_container" != "$feat3_old_container" ]]
[[ ! -e "$DOCKER_STATE_DIR/$feat3_old_container" ]]
[[ -f "$DOCKER_STATE_DIR/$feat3_new_container.running" ]]
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-3/meta.json")" == 3 ]]

unset RUNTIME_POOL_SIZE
"$TEST_ROOT/platform/runtime/scripts/slots.sh" resize 3
if "$TEST_ROOT/platform/runtime/scripts/slots.sh" resize 2 2>/dev/null; then
  printf 'error: resize shrank pool below allocated slot 3\n' >&2
  exit 1
fi
"$TEST_ROOT/platform/runtime/scripts/slots.sh" add 1
grep -Fxq 'RUNTIME_POOL_SIZE=4' "$TEST_ROOT/.env"
"$TEST_ROOT/platform/runtime/scripts/slots.sh" allocate fixture FEAT-2 --slot 4
[[ "$(jq -r '.runtime.poolSlot' "$TEST_ROOT/workspaces/fixture/FEAT-2/meta.json")" == 4 ]]

touch "$DOCKER_STATE_DIR/container-99"
slots_out="$("$TEST_ROOT/platform/runtime/scripts/slots.sh" status)"
grep -Fq 'orphaned-container' <<<"$slots_out"
"$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup --dry-run >/dev/null
[[ -f "$DOCKER_STATE_DIR/container-99" ]]
"$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >/dev/null
[[ ! -e "$DOCKER_STATE_DIR/container-99" ]]

# Worktree management tests (worktrees.sh)
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-4
wt_active="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" list --active)"
grep -Fq 'worktrees/fixture-feat-2' <<<"$wt_active"
grep -Fq 'worktrees/fixture-feat-3' <<<"$wt_active"
if grep -Fq 'worktrees/fixture-feat-4' <<<"$wt_active"; then
  printf 'error: stopped worktree listed as active\n' >&2
  exit 1
fi

wt_inactive="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" list --inactive)"
grep -Fq 'worktrees/fixture-feat-4' <<<"$wt_inactive"

wt_inspect="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" inspect fixture/FEAT-3)"
grep -Fq 'Link mode:       relative' <<<"$wt_inspect"
grep -Fq 'Pool slot:       3' <<<"$wt_inspect"

mkdir -p "$TEST_ROOT/worktrees/orphan-clean"
mkdir -p "$TEST_ROOT/worktrees/orphan-dirty"
git init -q "$TEST_ROOT/worktrees/orphan-dirty"
printf 'dirty\n' >"$TEST_ROOT/worktrees/orphan-dirty/untracked.txt"

wt_orphaned="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" list --orphaned)"
grep -Fq 'worktrees/orphan-clean' <<<"$wt_orphaned"
grep -Fq 'worktrees/orphan-dirty' <<<"$wt_orphaned"

"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup --dry-run >/dev/null
[[ -d "$TEST_ROOT/worktrees/orphan-clean" ]]
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ ! -e "$TEST_ROOT/worktrees/orphan-clean" ]]
[[ -d "$TEST_ROOT/worktrees/orphan-dirty" ]]
[[ -d "$TEST_ROOT/worktrees/fixture-feat-4" ]]

"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup --inactive >/dev/null 2>&1
[[ ! -e "$TEST_ROOT/worktrees/fixture-feat-4" ]]
jq -e '
  .lifecycleStage != "closed" and
  .runtime.status == "stopped" and
  .runtime.worktree == null and
  .runtime.poolSlot == null
' "$TEST_ROOT/workspaces/fixture/FEAT-4/meta.json" >/dev/null

# Regression 1: Absolute-link repair in worktrees.sh repair
repo_real="$(cd "$TEST_ROOT/repos/fixture" && pwd -P)"
printf 'gitdir: %s/.git/worktrees/fixture-feat-3\n' "$repo_real" >"$TEST_ROOT/worktrees/fixture-feat-3/.git"
wt_inspect_abs="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" inspect fixture/FEAT-3)"
grep -Fq 'Link mode:       absolute' <<<"$wt_inspect_abs"
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" repair >/dev/null
wt_inspect_rel="$("$TEST_ROOT/platform/runtime/scripts/worktrees.sh" inspect fixture/FEAT-3)"
grep -Fq 'Link mode:       relative' <<<"$wt_inspect_rel"
grep -Eq '^gitdir: \.\./\.\./repos/fixture/\.git/worktrees/' "$TEST_ROOT/worktrees/fixture-feat-3/.git"

# Regression 2: Registered orphan cleanup removes both directory and git worktree registration
git -C "$TEST_ROOT/repos/fixture" worktree add -q -b feat/registered-orphan \
  "$TEST_ROOT/worktrees/registered-orphan" origin/main
[[ -d "$TEST_ROOT/repos/fixture/.git/worktrees/registered-orphan" ]]
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ ! -e "$TEST_ROOT/worktrees/registered-orphan" ]]
[[ ! -e "$TEST_ROOT/repos/fixture/.git/worktrees/registered-orphan" ]]

# Regression 3: Malformed persisted worktree path (.. traversal) is never deleted outside worktrees/
mkdir -p "$TEST_ROOT/escape-target"
printf 'keep\n' >"$TEST_ROOT/escape-target/keep.txt"
feat1_meta="$TEST_ROOT/workspaces/fixture/FEAT-1/meta.json"
jq '.runtime.worktree = "worktrees/../escape-target"' "$feat1_meta" >"${feat1_meta}.tmp"
mv "${feat1_meta}.tmp" "$feat1_meta"
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ -f "$TEST_ROOT/escape-target/keep.txt" ]]
[[ "$(jq -r '.runtime.worktree // "null"' "$feat1_meta")" == "null" ]]

# Regression 4: worktrees.sh cleanup on a closed work item preserves live containerId/poolSlot for slots.sh cleanup
touch "$DOCKER_STATE_DIR/container-77" "$DOCKER_STATE_DIR/container-77.running"
jq '
  .runtime.worktree = "worktrees/fixture-feat-1" |
  .runtime.containerId = "container-77" |
  .runtime.poolSlot = 1
' "$feat1_meta" >"${feat1_meta}.tmp"
mv "${feat1_meta}.tmp" "$feat1_meta"
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
jq -e '
  .runtime.worktree == null and
  .runtime.containerId == "container-77" and
  .runtime.poolSlot == 1
' "$feat1_meta" >/dev/null
"$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >/dev/null
[[ ! -e "$DOCKER_STATE_DIR/container-77" ]]
jq -e '
  .runtime.worktree == null and
  .runtime.containerId == null and
  .runtime.poolSlot == null
' "$feat1_meta" >/dev/null

# Regression 5: slots.sh cleanup preserves live pool.lock and removes stale pool.lock
lock_dir="$TEST_ROOT/.local/state/runtime/pool.lock"
mkdir -p "$lock_dir"
sleep 30 &
live_pid=$!
printf '%s\n' "$live_pid" >"$lock_dir/pid"
if RUNTIME_POOL_LOCK_RETRIES=2 "$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup 2>/dev/null; then
  printf 'error: slots.sh cleanup proceeded while live pool.lock was held\n' >&2
  exit 1
fi
[[ -d "$lock_dir" ]]
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
"$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >/dev/null
[[ ! -d "$lock_dir" ]]

# Regression 6: Docker daemon failure aborts slots.sh cleanup without clearing containerId
feat3_meta="$TEST_ROOT/workspaces/fixture/FEAT-3/meta.json"
feat3_cid="$(jq -r '.runtime.containerId' "$feat3_meta")"
if DOCKER_DAEMON_DOWN=1 "$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup 2>/dev/null; then
  printf 'error: slots.sh cleanup succeeded while Docker daemon was down\n' >&2
  exit 1
fi
[[ "$(jq -r '.runtime.containerId' "$feat3_meta")" == "$feat3_cid" ]]

# Regression 7: slots.sh release rejects active runtimes unless --force is passed
if "$TEST_ROOT/platform/runtime/scripts/slots.sh" release 3 2>/dev/null; then
  printf 'error: slots.sh release allowed releasing a running runtime without --force\n' >&2
  exit 1
fi
[[ -f "$DOCKER_STATE_DIR/$feat3_cid.running" ]]
[[ "$(jq -r '.runtime.poolSlot' "$feat3_meta")" == 3 ]]
"$TEST_ROOT/platform/runtime/scripts/slots.sh" release 3 --force >/dev/null
[[ "$(jq -r '.runtime.poolSlot // "null"' "$feat3_meta")" == "null" ]]
"$TEST_ROOT/platform/runtime/scripts/slots.sh" allocate fixture FEAT-3 --slot 3 >/dev/null
feat3_cid="$(jq -r '.runtime.containerId' "$feat3_meta")"

# Regression 8: Concurrent slots.sh add/resize serializes on pool.lock
"$TEST_ROOT/platform/runtime/scripts/slots.sh" add 1 >/dev/null &
pid_a=$!
"$TEST_ROOT/platform/runtime/scripts/slots.sh" add 1 >/dev/null &
pid_b=$!
wait "$pid_a" "$pid_b"
grep -Fxq 'RUNTIME_POOL_SIZE=6' "$TEST_ROOT/.env"
"$TEST_ROOT/platform/runtime/scripts/slots.sh" resize 4 >/dev/null

# Regression 9: Locked registered worktree refuses removal instead of falling back to rm -rf
git -C "$TEST_ROOT/repos/fixture" worktree add -q -b feat/locked-orphan \
  "$TEST_ROOT/worktrees/locked-orphan" origin/main
git -C "$TEST_ROOT/repos/fixture" worktree lock "$TEST_ROOT/worktrees/locked-orphan"
if "$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup 2>/dev/null; then
  printf 'error: worktrees.sh cleanup bypassed locked git worktree protection\n' >&2
  exit 1
fi
[[ -d "$TEST_ROOT/worktrees/locked-orphan" ]]
git -C "$TEST_ROOT/repos/fixture" worktree unlock "$TEST_ROOT/worktrees/locked-orphan"
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ ! -e "$TEST_ROOT/worktrees/locked-orphan" ]]

# Regression 10: Failed start.sh precondition preserves existing running runtime status
jq -e '.runtime.status == "running" and .runtime.poolSlot == 3' "$feat3_meta" >/dev/null
if "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-3 --slot 4 2>/dev/null; then
  printf 'error: start.sh allowed claiming already allocated slot 4\n' >&2
  exit 1
fi
jq -e '.runtime.status == "running" and .runtime.poolSlot == 3 and .runtime.containerId != null' "$feat3_meta" >/dev/null

# Regression 11: Concurrent start.sh and slots.sh cleanup serialize so new container is not deleted as orphan
prev_counter="$(<"$DOCKER_STATE_DIR/counter")"
DEVCONTAINER_DELAY=0.5 "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 >/dev/null &
start_pid=$!
for _ in $(seq 1 40); do
  if [[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]; then
    break
  fi
  sleep 0.05
done
[[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]
"$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >/dev/null
wait "$start_pid"
feat4_meta="$TEST_ROOT/workspaces/fixture/FEAT-4/meta.json"
feat4_cid="$(jq -r '.runtime.containerId' "$feat4_meta")"
[[ -n "$feat4_cid" && -f "$DOCKER_STATE_DIR/$feat4_cid.running" ]]

# Regression 12: Concurrent start.sh and worktrees.sh cleanup --inactive serialize on pool.lock
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-4 >/dev/null
"$TEST_ROOT/platform/runtime/scripts/slots.sh" release fixture FEAT-4 --remove-worktree >/dev/null
[[ ! -e "$TEST_ROOT/worktrees/fixture-feat-4" ]]
DEVCONTAINER_DELAY=0.5 "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 >/dev/null &
start_pid=$!
for _ in $(seq 1 40); do
  if [[ -e "$TEST_ROOT/worktrees/fixture-feat-4/.git" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]; then
    break
  fi
  sleep 0.05
done
[[ -e "$TEST_ROOT/worktrees/fixture-feat-4/.git" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup --inactive >/dev/null 2>&1
wait "$start_pid"
[[ -d "$TEST_ROOT/worktrees/fixture-feat-4" ]]
jq -e '.runtime.status == "running" and .runtime.worktree == "worktrees/fixture-feat-4"' "$feat4_meta" >/dev/null

# Regression 13: Failed git status is classified as error and refused by destructive cleanup/release
git -C "$TEST_ROOT/repos/fixture" worktree add -q -b feat/corrupt-orphan \
  "$TEST_ROOT/worktrees/corrupt-orphan" origin/main
printf 'corrupt' >"$TEST_ROOT/repos/fixture/.git/worktrees/corrupt-orphan/index"
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ -d "$TEST_ROOT/worktrees/corrupt-orphan" ]]
rm -f "$TEST_ROOT/repos/fixture/.git/worktrees/corrupt-orphan/index"
git -C "$TEST_ROOT/worktrees/corrupt-orphan" reset -q HEAD -- .
"$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup >/dev/null 2>&1
[[ ! -e "$TEST_ROOT/worktrees/corrupt-orphan" ]]

# Regression 14: Failed container recreation persists worktree-ready and null containerId after old container removal
old_feat3_cid="$(jq -r '.runtime.containerId' "$feat3_meta")"
if DEVCONTAINER_FAIL=1 "$TEST_ROOT/platform/runtime/scripts/slots.sh" recreate 3 2>/dev/null; then
  printf 'error: slots.sh recreate succeeded when devcontainer up failed\n' >&2
  exit 1
fi
[[ ! -e "$DOCKER_STATE_DIR/$old_feat3_cid" ]]
jq -e '
  .runtime.status == "worktree-ready" and
  .runtime.containerId == null and
  .runtime.poolSlot == 3
' "$feat3_meta" >/dev/null
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-3 >/dev/null

# Regression 15: .git pointer outside configured repository inventory is rejected by repair and cleanup
git init -q --initial-branch=main "$TEST_ROOT/external-repo"
printf 'ext\n' >"$TEST_ROOT/external-repo/README.md"
git -C "$TEST_ROOT/external-repo" add README.md
git -C "$TEST_ROOT/external-repo" -c user.name=Test -c user.email=test@example.invalid commit -q -m ext
git -C "$TEST_ROOT/external-repo" worktree add -q -b feat/ext "$TEST_ROOT/worktrees/external-wt" main
ext_real="$(cd "$TEST_ROOT/external-repo" && pwd -P)"
printf 'gitdir: %s/.git/worktrees/external-wt\n' "$ext_real" >"$TEST_ROOT/worktrees/external-wt/.git"
if "$TEST_ROOT/platform/runtime/scripts/worktrees.sh" repair 2>/dev/null; then
  printf 'error: worktrees.sh repair accepted a worktree pointing outside configured repositories\n' >&2
  exit 1
fi
if "$TEST_ROOT/platform/runtime/scripts/worktrees.sh" cleanup 2>/dev/null; then
  printf 'error: worktrees.sh cleanup accepted a worktree pointing outside configured repositories\n' >&2
  exit 1
fi
[[ -d "$TEST_ROOT/worktrees/external-wt" ]]
git -C "$TEST_ROOT/external-repo" worktree remove --force "$TEST_ROOT/worktrees/external-wt"

# Regression 16: Failed start.sh after new worktree creation persists worktree-ready and claimed slot
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-4 >/dev/null
"$TEST_ROOT/platform/runtime/scripts/slots.sh" release fixture FEAT-4 --remove-worktree >/dev/null
if DEVCONTAINER_FAIL=1 "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 2>/dev/null; then
  printf 'error: start.sh succeeded when devcontainer up failed\n' >&2
  exit 1
fi
[[ -d "$TEST_ROOT/worktrees/fixture-feat-4" ]]
jq -e '
  .runtime.status == "worktree-ready" and
  .runtime.worktree == "worktrees/fixture-feat-4" and
  .runtime.containerId == null and
  .runtime.poolSlot != null
' "$feat4_meta" >/dev/null
"$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 >/dev/null

# Regression 17: Unopted-in child process cannot bypass pool.lock via PPID
(
  # shellcheck source=platform/runtime/scripts/lib.sh
  source "$TEST_ROOT/platform/runtime/scripts/lib.sh"
  lock_path="$(acquire_pool_lock)"
  trap 'release_pool_lock "$lock_path"' EXIT
  if RUNTIME_POOL_LOCK_RETRIES=1 "$TEST_ROOT/platform/runtime/scripts/slots.sh" add 1 2>/dev/null; then
    printf 'error: child process bypassed pool.lock without explicit RUNTIME_POOL_LOCK_OWNER\n' >&2
    exit 1
  fi
)

# Regression 18: Two concurrent slots.sh cleanup runs on a stale pool.lock reclaim it once and preserve the live replacement lock
mkdir -p "$lock_dir"
printf '999999\n' >"$lock_dir/pid"
DOCKER_PS_DELAY=0.4 "$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >"$TEST_ROOT/cleanup-1.out" &
cleanup1_pid=$!
DOCKER_PS_DELAY=0.4 "$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup >"$TEST_ROOT/cleanup-2.out" &
cleanup2_pid=$!
for _ in $(seq 1 40); do
  if [[ -f "$lock_dir/pid" && "$(tr -d '[:space:]' <"$lock_dir/pid" 2>/dev/null || true)" != "999999" ]]; then
    break
  fi
  sleep 0.05
done
if RUNTIME_POOL_LOCK_RETRIES=1 "$TEST_ROOT/platform/runtime/scripts/slots.sh" add 1 2>/dev/null; then
  printf 'error: concurrent cleanup deleted the replacement live pool.lock\n' >&2
  exit 1
fi
wait "$cleanup1_pid" "$cleanup2_pid"
reclaim_count="$(grep -Fc 'removed stale runtime pool lock' "$TEST_ROOT/cleanup-1.out" "$TEST_ROOT/cleanup-2.out" | awk -F: '{s+=$2} END {print s+0}')"
[[ "$reclaim_count" -eq 1 ]]

# Regression 19: Abandoned pool.lock.reclaim guard is recovered during stale pool.lock reclamation
mkdir -p "$lock_dir" "${lock_dir}.reclaim"
printf '999999\n' >"$lock_dir/pid"
printf '999998\n' >"${lock_dir}.reclaim/pid"
reclaim_out="$("$TEST_ROOT/platform/runtime/scripts/slots.sh" cleanup)"
grep -Fq 'removed stale runtime pool lock' <<<"$reclaim_out"
[[ ! -d "$lock_dir" && ! -d "${lock_dir}.reclaim" ]]

# Regression 20: Concurrent start.sh vs stop.sh and start.sh vs close.sh serialize on pool.lock
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-4 >/dev/null
"$TEST_ROOT/platform/runtime/scripts/slots.sh" release fixture FEAT-4 --remove-worktree >/dev/null
prev_counter="$(<"$DOCKER_STATE_DIR/counter")"
DEVCONTAINER_DELAY=0.5 "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 >/dev/null &
start_pid=$!
for _ in $(seq 1 40); do
  if [[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]; then
    break
  fi
  sleep 0.05
done
[[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]
"$TEST_ROOT/platform/runtime/scripts/stop.sh" fixture FEAT-4 >/dev/null
wait "$start_pid"
feat4_cid="$(jq -r '.runtime.containerId' "$feat4_meta")"
[[ -n "$feat4_cid" && -f "$DOCKER_STATE_DIR/$feat4_cid" && ! -f "$DOCKER_STATE_DIR/$feat4_cid.running" ]]
jq -e '.runtime.status == "stopped" and .runtime.containerId != null' "$feat4_meta" >/dev/null

"$TEST_ROOT/platform/runtime/scripts/slots.sh" release fixture FEAT-4 --remove-worktree >/dev/null
prev_counter="$(<"$DOCKER_STATE_DIR/counter")"
DEVCONTAINER_DELAY=0.5 "$TEST_ROOT/platform/runtime/scripts/start.sh" fixture FEAT-4 >/dev/null &
start_pid=$!
for _ in $(seq 1 40); do
  if [[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]; then
    break
  fi
  sleep 0.05
done
[[ "$(<"$DOCKER_STATE_DIR/counter")" -gt "$prev_counter" && -f "$TEST_ROOT/.local/state/runtime/pool.lock/pid" ]]
"$TEST_ROOT/platform/runtime/scripts/close.sh" fixture FEAT-4 abandoned >/dev/null
wait "$start_pid"
[[ ! -e "$TEST_ROOT/worktrees/fixture-feat-4" ]]
jq -e '
  .lifecycleStage == "closed" and
  .runtime.status == "stopped" and
  .runtime.worktree == null and
  .runtime.containerId == null and
  .runtime.poolSlot == null
' "$feat4_meta" >/dev/null

printf 'runtime lifecycle test passed\n'
