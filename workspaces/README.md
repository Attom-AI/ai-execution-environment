# Tool-specific workspace integrations

`config/workspaces.json` is the source of truth for named workspace membership.
This directory holds optional editor- or tool-specific integrations for those
logical workspaces; it does not define membership itself.

The existing platform VS Code workspace intentionally excludes managed
repositories from search and file watching. Add another integration only when
it provides a useful tool experience. A logical workspace may contain one or
more repositories and does not require a corresponding `.code-workspace` file.

Do not create an all-repositories workspace by default. A workspace is a
navigation aid and does not isolate repositories from editors or agents.

