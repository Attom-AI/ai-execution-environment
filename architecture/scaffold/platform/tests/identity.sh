#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/config" "$TEST_ROOT/home" "$TEST_ROOT/workspaces/ws/TASK-1"
cp -R "$SOURCE_ROOT/platform" "$TEST_ROOT/platform"
IDENTITY="$TEST_ROOT/platform/identity/identity.sh"
RUN="$TEST_ROOT/platform/identity/run.sh"

# Host credentials that isolated identities must never see.
export HOME="$TEST_ROOT/home"
export GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_GLOBAL
git config --global credential.helper "store --file=$HOME/.git-credentials"
printf 'https://host:hosttoken@bitbucket.org\nhttps://host:hostgithub@github.com\n' >"$HOME/.git-credentials"
export GH_TOKEN=leaked-host-token
export SSH_AUTH_SOCK="$TEST_ROOT/agent.sock"

# gh stub: reports the profile it was given and a configurable login.
cat >"$TEST_ROOT/bin/glab" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == 'api user' ]] || exit 2
[[ -z "${STUB_GLAB_LOGIN:-}" ]] || printf '{"username":"%s"}\n' "$STUB_GLAB_LOGIN"
EOF
chmod +x "$TEST_ROOT/bin/glab"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'auth git-credential') printf 'username=gh-user\npassword=gh:%s\n' "${GH_CONFIG_DIR:-global}" ;;
  'api user') printf '%s\n' "${STUB_GH_LOGIN:-}" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/gh"
export PATH="$TEST_ROOT/bin:$PATH"

jq -n '{
  version: 1,
  projects: [
    {id: "iso", workspace: "ws", repository: {provider: "github", owner: "example", name: "iso", url: "https://bitbucket.org/example/iso.git", path: "repos/iso", identity: "iso"}, issues: {provider: "github", owner: "example", repository: "iso"}},
    {id: "shared", workspace: "shared", repository: {provider: "github", owner: "example", name: "shared", url: "https://bitbucket.org/example/shared.git", path: "repos/shared", identity: "operator"}, issues: {provider: "github", owner: "example", repository: "shared"}},
    {id: "sshproject", workspace: "sshws", repository: {provider: "github", owner: "example", name: "sshproject", url: "git@github.com:example/sshproject.git", path: "repos/sshproject", identity: "sshid"}, issues: {provider: "github", owner: "example", repository: "sshproject"}},
    {id: "httpsproject", workspace: "httpsws", repository: {provider: "github", owner: "example", name: "httpsproject", url: "https://github.com/example/httpsproject.git", path: "repos/httpsproject", identity: "sshid"}, issues: {provider: "github", owner: "example", repository: "httpsproject"}},
    {id: "unbound", workspace: "unbound", repository: {provider: "github", owner: "example", name: "unbound", url: "https://example.invalid/unbound.git", path: "repos/unbound"}, issues: {provider: "github", owner: "example", repository: "unbound"}}
  ]
}' >"$TEST_ROOT/config/projects.json"

# Profile creation.
"$IDENTITY" init iso --mode isolated --account bot --git-name Bot --git-email bot@example.invalid >/dev/null
"$IDENTITY" init operator --mode host >/dev/null
profile="$TEST_ROOT/.local/state/identities/iso"
[[ -d "$profile/gh" && -f "$profile/git/config" && -f "$profile/ssh/known_hosts" ]] || fail "init did not create the profile layout"
[[ "$(stat -c %a "$profile" 2>/dev/null || stat -f %Lp "$profile")" == 700 ]] || fail "profile directory is not private"
if "$IDENTITY" init iso --mode isolated --account bot >/dev/null 2>&1; then fail "duplicate identity was accepted"; fi
if "$IDENTITY" init noaccount --mode isolated >/dev/null 2>&1; then fail "isolated identity without an account was accepted"; fi
listing="$("$IDENTITY" list)"
grep -Eq '^iso +isolated +bot ' <<<"$listing" || fail "list does not report the isolated identity"
printf 'https://bot:profiletoken@bitbucket.org\n' >"$profile/git/credentials"

credential() {
  printf 'protocol=https\nhost=%s\n\n' "$2" | "$RUN" --project "$1" -- git credential fill 2>/dev/null | sed -n 's/^password=//p'
}

# Isolated: only the profile's helpers answer; host store, global gh, and keychain are bypassed.
[[ "$(credential iso bitbucket.org)" == profiletoken ]] || fail "isolated identity did not use its own credential store"
[[ "$(credential iso github.com)" == "gh:$profile/gh" ]] || fail "isolated identity did not use its own gh profile"
# Host mode: host credentials are used deliberately.
[[ "$(credential shared bitbucket.org)" == hosttoken ]] || fail "host identity did not use host credentials"

environment="$("$RUN" --project iso -- env)"
grep -q '^GH_TOKEN=' <<<"$environment" && fail "isolated identity inherited GH_TOKEN"
grep -qx 'SSH_AUTH_SOCK=' <<<"$environment" || fail "isolated identity inherited the SSH agent"
grep -q '^GIT_SSH_COMMAND=.*-o IdentityAgent=none.*-i /dev/null' <<<"$environment" || fail "SSH is not confined without a profile key"
[[ "$("$RUN" --project iso -- git config user.email)" == bot@example.invalid ]] || fail "isolated identity commit email not applied"
grep -qx 'GH_TOKEN=leaked-host-token' <<<"$("$RUN" --project shared -- env)" || fail "host identity did not preserve host environment"

touch "$profile/ssh/id_ed25519" "$profile/ssh/id_ed25519.pub"
# shellcheck disable=SC2016 # expanded by the child shell under the identity
ssh_command="$("$RUN" --project iso -- sh -c 'printf %s "$GIT_SSH_COMMAND"')"
[[ "$ssh_command" == *"-i $profile/ssh/id_ed25519"* && "$ssh_command" != *'-i /dev/null'* ]] || fail "profile SSH key not used"
[[ "$ssh_command" != *id_ed25519.pub* ]] || fail "public key offered as an identity"

# Missing identity bindings and profiles fail before running anything.
"$RUN" --project unbound -- true 2>"$TEST_ROOT/err" && fail "project without identity ran"
grep -q 'has no repository identity' "$TEST_ROOT/err" || fail "missing identity error is unclear"
jq '.identities.ghost = {mode: "isolated", account: "ghost"}' "$TEST_ROOT/.local/state/identities.json" >"$TEST_ROOT/ids.json"
mv "$TEST_ROOT/ids.json" "$TEST_ROOT/.local/state/identities.json"
"$RUN" --identity ghost -- touch "$TEST_ROOT/ran" 2>/dev/null && fail "missing profile directory did not fail"
[[ ! -e "$TEST_ROOT/ran" ]] || fail "command ran without its identity"

# Outbound commands verify the account first and never switch.
STUB_GH_LOGIN=someone-else "$RUN" --project iso -- git -C "$TEST_ROOT/nowhere" push 2>"$TEST_ROOT/err" && fail "push ran under the wrong account"
grep -q 'authenticated as someone-else, expected bot' "$TEST_ROOT/err" || fail "account mismatch not reported"
STUB_GH_LOGIN=bot "$RUN" --project iso -- git -C "$TEST_ROOT/nowhere" push 2>"$TEST_ROOT/err" || true
grep -q 'gh authenticated as bot' "$TEST_ROOT/err" || fail "verified push did not report the account"
grep -q 'failed verification' "$TEST_ROOT/err" && fail "matching account failed verification"
# Global flags before the subcommand must not skip verification.
for publish in 'gh -R example/iso pr create --fill' 'gh --repo example/iso pr merge 1' 'gh pr create'; do
  read -ra publish_command <<<"$publish"
  STUB_GH_LOGIN=someone-else "$RUN" --project iso -- "${publish_command[@]}" 2>"$TEST_ROOT/err" \
    && fail "unverified publish ran: $publish"
  grep -q 'failed verification' "$TEST_ROOT/err" || fail "publish skipped verification: $publish"
done
STUB_GH_LOGIN=someone-else "$RUN" --project iso -- gh pr view 1 2>"$TEST_ROOT/err" || true
grep -q 'failed verification' "$TEST_ROOT/err" && fail "read-only gh command was treated as publishing"

# SSH identities: only SSH remotes are probed, and transport mismatches are reported.
"$IDENTITY" init sshid --mode isolated --account sshbot --transport ssh >/dev/null
# shellcheck source=platform/identity/lib.sh
source "$TEST_ROOT/platform/identity/lib.sh"
[[ "$(identity_ssh_hosts sshid)" == github.com ]] || fail "SSH hosts include non-SSH remotes"
STUB_GH_LOGIN=sshbot "$IDENTITY" check sshid >"$TEST_ROOT/out" 2>&1 && fail "transport mismatch passed verification"
grep -q 'project httpsproject uses an https remote but the identity declares ssh transport' "$TEST_ROOT/out" \
  || fail "transport mismatch not reported"
grep -q 'git@https' "$TEST_ROOT/out" && fail "HTTPS remote probed over SSH"

# Host mode verifies glab like gh when an account is declared.
"$IDENTITY" init gitlab-host --mode host --account glbot >/dev/null
STUB_GLAB_LOGIN=glbot "$IDENTITY" check gitlab-host >"$TEST_ROOT/out" 2>&1 || fail "host-mode glab account not accepted"
grep -q 'glab authenticated as glbot' "$TEST_ROOT/out" || fail "host-mode glab not verified"
STUB_GLAB_LOGIN=someone-else "$IDENTITY" check gitlab-host >/dev/null 2>&1 && fail "host-mode glab mismatch passed"

# Work items: the recorded identity must match the project.
jq -n '{workspace: "ws", workItem: "TASK-1", project: "iso", identity: {repository: "iso", issues: "iso"}}' \
  >"$TEST_ROOT/workspaces/ws/TASK-1/meta.json"
"$RUN" ws TASK-1 -- true || fail "work item with matching identity failed"
jq '.identity.repository = "operator"' "$TEST_ROOT/workspaces/ws/TASK-1/meta.json" >"$TEST_ROOT/meta.json"
mv "$TEST_ROOT/meta.json" "$TEST_ROOT/workspaces/ws/TASK-1/meta.json"
"$RUN" ws TASK-1 -- true 2>"$TEST_ROOT/err" && fail "identity drift was not detected"
grep -q 'identity drift' "$TEST_ROOT/err" || fail "identity drift error is unclear"

# Containers receive one profile at a fixed mount point; host mode receives none.
container_args="$(identity_container_args iso)"
grep -Fxq "type=bind,source=$profile,target=/home/vscode/.identity" <<<"$container_args" || fail "profile not mounted"
grep -Fxq 'GH_CONFIG_DIR=/home/vscode/.identity/gh' <<<"$container_args" || fail "container gh profile path wrong"
grep -q '^GIT_SSH_COMMAND=.*-i /home/vscode/.identity/ssh/id_ed25519' <<<"$container_args" || fail "container SSH key path wrong"
grep -q "$TEST_ROOT/.local/state/identities/iso/" <<<"$(grep -v '^type=bind' <<<"$container_args")" && fail "host paths leaked into container environment"
[[ -z "$(identity_container_args operator 2>/dev/null)" ]] || fail "host identity mounted credentials"

printf 'identity test passed\n'
