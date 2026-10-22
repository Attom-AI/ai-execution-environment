# Setup guide

1. Copy `architecture/scaffold/` to the target machine.
2. Run `./platform/install/install.sh` from the copied root.
3. Review the generated `.env` and authenticate through the relevant CLI.
4. Register each project and workspace in `config/projects.json`.
5. Explicitly clone registered projects with
   `platform/repositories/clone.sh`, or allow the first scaffolding command to
   ensure its selected project.
6. Create a work item with
   `platform/workspace-scaffolder/scaffold.sh <workspace> <issue-ref>`.
7. Resume later through `ticket-coordinator`, using `meta.json` and
   `session-state.md` rather than prior conversation context.

The host needs Git, GitHub CLI, jq, envsubst, Docker, the Dev Container CLI,
ShellCheck, ripgrep, Hugo, and SDKMAN. Credentials stay in tool-owned or
host-local storage and are mounted into the runtime only when needed.
