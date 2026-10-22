# Scaffolding and intake

Issue trackers and repository hosts are independent provider axes. Source
adapters normalize tickets to:

```text
source, key, owner, repository, number, url, title, body, type, labels, raw
```

Downstream stages depend only on that normalized shape. The original provider
payload remains under `raw`. Repository adapters own cloning, fetch-only
synchronization, and remote-default-branch resolution.

The scaffolder resolves a project through `config/projects.json`, invokes its
source adapter, derives stable names, refreshes `ticket.json`, and creates live
state files only when absent. Re-running intake therefore refreshes external
issue data without overwriting pipeline progress. It ensures the canonical
repository and starts or resumes the runtime unless explicitly told not to.

GitHub is implemented for both axes. Jira remains a visible adapter stub and
backlog item; adding it must not require downstream pipeline changes.
