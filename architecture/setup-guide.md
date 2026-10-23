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
     host credentials only when needed.
   - `host` runs directly in the dedicated worktree and intentionally shares
     host tools and credentials.
   - `guidance` prints recommendations and cannot apply changes.
4. Apply the confirmed profile with the same options. This creates ignored
   instance directories, seeds `.env`, validates the platform, and saves the
   preferences under `.local/state/setup/`. It does not install global tools,
   authenticate, clone repositories, or alter remotes.
5. Review `.env` and authenticate through the relevant CLI as a separate,
   explicit action.
6. Register each project and workspace in `config/projects.json`.
7. Explicitly clone registered projects with
   `platform/repositories/clone.sh`, or allow the first scaffolding command to
   ensure its selected project.
8. Create a work item with
   `platform/workspace-scaffolder/scaffold.sh <workspace> <issue-ref>`.
9. Resume later through `ticket-coordinator`, using `meta.json` and
   `session-state.md` rather than prior conversation context.

The host needs Git, GitHub CLI, jq, envsubst, Docker, the Dev Container CLI,
ShellCheck, ripgrep, Hugo, and SDKMAN. Credentials stay in tool-owned or
host-local storage and are mounted into the runtime only when needed.

The runtime pool defaults to five exclusive worktree containers. Override
`RUNTIME_POOL_SIZE` in the ignored root `.env` when a different capacity is
required. Containers share the built image and mounted GitHub CLI state, not a
workspace or writable container filesystem.
