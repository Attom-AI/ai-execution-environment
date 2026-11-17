#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cp -R "$SOURCE_ROOT/platform" "$TEST_ROOT/platform"
cp -R "$SOURCE_ROOT/bin" "$TEST_ROOT/bin"
mkdir -p \
  "$TEST_ROOT/config" \
  "$TEST_ROOT/workspaces/test-ws/TASK-100"

AEE="$TEST_ROOT/bin/aee"
CLI="$TEST_ROOT/platform/cli.sh"
RUNTIME_CLI="$TEST_ROOT/platform/runtime/runtime.sh"
RUNTIME_SCRIPTS_CLI="$TEST_ROOT/platform/runtime/scripts/runtime.sh"

[[ -x "$AEE" ]] || fail "bin/aee is not executable"
[[ -x "$CLI" ]] || fail "platform/cli.sh is not executable"
[[ -x "$RUNTIME_CLI" ]] || fail "platform/runtime/runtime.sh is not executable"
[[ -x "$RUNTIME_SCRIPTS_CLI" ]] || fail "platform/runtime/scripts/runtime.sh is not executable"

# 1. Test top-level help and version
help_out="$("$AEE" --help)"
grep -Fq 'aee - Unified CLI for the AI Execution Environment' <<<"$help_out" || fail "missing header in --help"
grep -Fq 'runtime' <<<"$help_out" || fail "missing runtime in --help"

version_out="$("$AEE" version)"
grep -Fq 'aee version 0.1.0' <<<"$version_out" || fail "unexpected version output: $version_out"

# 2. Test unknown command fails with exit 2
set +e
"$AEE" unknown-cmd 2>/dev/null
unknown_code=$?
set -e
[[ "$unknown_code" -eq 2 ]] || fail "unknown command did not exit with code 2 (got $unknown_code)"

# 3. Test runtime CLI wrapper directly
runtime_help="$("$RUNTIME_CLI" --help)"
grep -Fq 'runtime.sh start' <<<"$runtime_help" || fail "missing runtime.sh start in runtime help"

# Test unknown runtime action exits with 2
set +e
"$RUNTIME_CLI" invalid-action 2>/dev/null
invalid_runtime_code=$?
set -e
[[ "$invalid_runtime_code" -eq 2 ]] || fail "invalid runtime action did not exit with code 2"

# 4. Test work-items status
cat >"$TEST_ROOT/workspaces/test-ws/TASK-100/meta.json" <<'EOF'
{
  "schemaVersion": 1,
  "workspace": "test-ws",
  "workItem": "TASK-100",
  "project": "test-proj",
  "lifecycleStage": "implementation",
  "gates": {
    "definitionOfReadyMet": true,
    "clarifyingQuestionsResolved": true,
    "designApproved": true,
    "implementationComplete": false,
    "testsPassing": false,
    "reviewApproved": false,
    "ciPassing": false,
    "pullRequestMerged": false
  },
  "runtime": {
    "status": "worktree-ready",
    "worktree": "worktrees/test-ws-task-100",
    "containerId": "mock-cid-123",
    "poolSlot": 2
  },
  "identity": {
    "repository": "test-repo-id",
    "issues": "test-issues-id"
  },
  "blocked": {
    "isBlocked": false,
    "reason": null
  },
  "resume": {
    "nextAgent": "implementation"
  }
}
EOF

status_out="$("$AEE" work-items status test-ws TASK-100)"
grep -Fq 'Work Item: test-ws/TASK-100' <<<"$status_out" || fail "status missing work item name"
grep -Fq 'Stage:          implementation' <<<"$status_out" || fail "status missing stage"
grep -Fq 'Pool Slot:      2' <<<"$status_out" || fail "status missing pool slot"
grep -Fq 'definitionOfReadyMet: met' <<<"$status_out" || fail "status missing gate status"
grep -Fq 'implementationComplete: unmet' <<<"$status_out" || fail "status missing unmet gate"

# Non-existent work item status exits with 1
set +e
"$AEE" work-items status test-ws NON-EXISTENT 2>/dev/null
missing_task_code=$?
set -e
[[ "$missing_task_code" -eq 1 ]] || fail "missing work item status should exit with 1"

# 5. Test subcommands help output
repos_help="$("$AEE" repos --help 2>&1 || true)"
grep -Fq 'aee repos status' <<<"$repos_help" || fail "missing aee repos status in repos help"

work_items_help="$("$AEE" work-items --help 2>&1 || true)"
grep -Fq 'aee work-items scaffold' <<<"$work_items_help" || fail "missing aee work-items scaffold in help"

context_help="$("$AEE" context --help 2>&1 || true)"
grep -Fq 'aee context hydrate' <<<"$context_help" || fail "missing aee context hydrate in help"

# 6. Test shell completion generation
zsh_comp="$("$AEE" completion zsh)"
grep -Fq '_aee()' <<<"$zsh_comp" || fail "missing _aee in zsh completion"
grep -Fq 'compdef _aee aee' <<<"$zsh_comp" || fail "missing compdef in zsh completion"

bash_comp="$("$AEE" completion bash)"
grep -Fq '_aee_completions()' <<<"$bash_comp" || fail "missing _aee_completions in bash completion"
grep -Fq 'declare -f _init_completion' <<<"$bash_comp" || fail "missing declare -f check in bash completion"

# 7. Test identity subcommand dispatching
identity_list_out="$("$AEE" identity list)"
grep -Fq 'no identity profiles configured' <<<"$identity_list_out" || fail "unexpected identity list output: $identity_list_out"

printf 'runtime cli tests passed\n'
