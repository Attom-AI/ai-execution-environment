# Identity

Named credential profiles that every Git and provider operation runs under. See
`architecture/identity-model.md` for the model.

- `identity.sh list`: profiles, modes, accounts, and the projects using them.
- `identity.sh init <id> --mode isolated --account <login> [--transport https|ssh] [--git-name <name>] [--git-email <email>]`:
  declare a profile and create its private directory. It prints the explicit
  authentication commands and performs none of them.
- `identity.sh init <id> --mode host [--account <login>]`: declare a profile
  that deliberately uses host credentials.
- `identity.sh check <id>|--all`: verify that each configured credential
  authenticates as the declared account. This contacts providers and never
  switches accounts.
- `identity.sh env <id>`: print the environment an identity applies (paths
  only, no secrets).
- `run.sh <workspace> <work-item> [--issues] -- <command>`: run a command under
  a work item's recorded identity. `--project <id>` and `--identity <id>` select
  an identity directly. Pushes and pull-request creation or merging are verified
  first.
- `lib.sh`: resolution, environment construction, container arguments, and
  verification shared by platform scripts.

Authenticating an isolated profile, for example:

```sh
GH_CONFIG_DIR=.local/state/identities/<id>/gh gh auth login --insecure-storage
GLAB_CONFIG_DIR=.local/state/identities/<id>/glab glab auth login
```

For SSH, place the private key as `.local/state/identities/<id>/ssh/id_ed25519`
and the provider's published host keys in `ssh/known_hosts`. For HTTPS
providers without a CLI helper, add `https://<user>:<token>@<host>` to
`git/credentials`.
