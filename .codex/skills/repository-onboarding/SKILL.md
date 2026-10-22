---
name: repository-onboarding
description: Add a Git repository to this workspace's managed repository manifest, validate its location, optionally clone it when explicitly requested, and report its status. Use when registering, adding, or onboarding a repository to the managed workspace; do not use for arbitrary clones inside a managed project.
---

# Repository Onboarding

Onboard one repository without broadening the requested operation to other
repositories or Git actions.

## Inputs and defaults

Require the repository URL, project id, workspace id, and issue source. Accept
an optional managed path.

- Derive a missing project id from the final repository URL component and remove a
  trailing `.git`.
- Default the managed path to `repos/<project-id>`.
- Confirm that the repository belongs to the workspace's selected trust domain
  when its scope is ambiguous. Do not add out-of-scope code, credentials, or
  data.

## Preflight

Read the root `AGENTS.md`, `config/projects.json`, and the repository-management
scripts before changing anything. Preserve the manifest version and entry
schema.

Reject the request or ask for a corrected value when:

- the project id, workspace id, URL, or path duplicates an existing entry;
- the path is absolute, is outside `repos/`, or contains `.` or `..` segments;
- the path is an ancestor or descendant of another managed repository path;
- an existing path component is a symlink whose resolved location escapes the
  workspace's canonical `repos/` directory; or
- the target exists but is not the expected Git checkout.

Do not authenticate, alter credentials, create remotes, fetch, push, switch
branches, or rewrite a working tree as part of onboarding.

## Register the repository

1. Add exactly one project object matching the existing schema to
   `config/projects.json`.
2. Sort project objects by `id` for stable diffs. Preserve unrelated
   entries and formatting.
3. Run `./platform/validate.sh`. If it fails, report the error and repair only the
   onboarding change when the cause is within scope.

Registration without cloning is a valid completed outcome.

## Optional clone

Clone only when the user's prompt explicitly requests it or the user separately
authorizes it. Before running `./platform/repositories/clone.sh`, determine every configured
repository currently missing from disk.

- When the requested repository is the only missing checkout, run
  `./platform/repositories/clone.sh`.
- When the command would clone any additional repository, stop and identify the
  complete additional set. Ask for explicit permission before expanding the
  operation; do not bypass the workspace command with a direct clone.

Do not interpret permission to register a repository as permission to clone or
perform any other network operation.

## Verify and report

After an authorized clone, run `./platform/repositories/status.sh`. Report:

- the registered project id, workspace id, URL, managed path, and issue source;
- whether the manifest validation passed;
- whether cloning was skipped, completed, or remains awaiting permission; and
- for a cloned checkout, its branch, working-tree state, and upstream state.

Report failures visibly with the repository name and leave unrelated manifest
entries and checkouts unchanged.
