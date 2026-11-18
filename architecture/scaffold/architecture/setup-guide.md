# Setup guide

1. Copy `architecture/scaffold/` to the target machine.
2. Preview setup without changing the environment:

   ```sh
   ./platform/install/setup.sh plan \
     --mode devcontainer \
     --provider github \
     --interface codex
   ```

3. Choose an execution mode:
   - `devcontainer` isolates project tools in the shared container and mounts
     only the work item's isolated identity profile into it.
   - `host` runs directly in the dedicated worktree and intentionally shares
     host tools and credentials.
   - `guidance` prints recommendations and cannot apply changes.
4. Apply the confirmed profile with the same options. This creates ignored
   instance directories, seeds `.env`, validates the platform, and saves the
   preferences under `.local/state/setup/`. It does not install global tools,
   authenticate, clone repositories, or alter remotes.
5. Link the unified CLI globally (recommended):
   ```sh
   mkdir -p ~/.local/bin
   ln -sf "$(pwd)/bin/aee" ~/.local/bin/aee
   ```
   Ensure `~/.local/bin` is in your `$PATH`. The CLI is directory-aware: it searches
   upward for `aee-workspace.yaml` to detect the workspace root, current worktree,
   and work-item context, and fails fast outside an `aee` workspace.
   
   > [!IMPORTANT]
   > Do **not** use a hardcoded shell alias (such as `alias aee="/path/to/bin/aee"`).
   > Hardcoded aliases bind execution to a fixed directory and break directory
   > discovery and context inference.

6. Optionally enable shell completions for your environment:
   ```sh
   # Zsh (in ~/.zshrc)
   eval "$(aee completion zsh)"

   # Bash (in ~/.bashrc)
   eval "$(aee completion bash)"
   ```
7. Create an identity profile for each account with
   `platform/identity/identity.sh init`, choosing `isolated` or `host` mode
   (see `identity-model.md`), then authenticate it through the relevant CLI as a
   separate, explicit action. Verify with `platform/identity/identity.sh check`.
8. Register each project and workspace in `config/projects.json`, including the
   identity it uses (`repository.identity`, and `issues.identity` when the issue
   source uses a different account).
9. Explicitly clone registered projects with
   `platform/repositories/clone.sh`, or allow the first scaffolding command to
   ensure its selected project.
10. Create a work item with
    `platform/workspace-scaffolder/scaffold.sh <workspace> <issue-ref>`.
11. Resume later through `ticket-coordinator`, using `meta.json` and
    `session-state.md` rather than prior conversation context.

The host needs Git, GitHub CLI, jq, envsubst, Docker, the Dev Container CLI,
ShellCheck, ripgrep, Hugo, and SDKMAN. Credentials stay in host-local identity
profiles; a runtime receives only its work item's isolated profile.

The runtime pool defaults to five exclusive worktree containers. Override
`RUNTIME_POOL_SIZE` in the ignored root `.env` when a different capacity is
required. Containers share the built image, not credentials, a workspace, or a
writable container filesystem.
