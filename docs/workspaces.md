# Work-item folders

A workspace is a local folder that organizes one specific work item. It is not
defined by an editor file, repository boundary, or fixed directory schema.

Create workspaces on demand beneath the ignored materialized directory:

```text
workspaces/
└── <work-item>/
```

A work-item folder may contain whatever local organization the activity needs,
such as notes, references to managed repositories, generated artifacts, or
editor configuration. Keep source repositories independently managed under
`repos/`, and keep the authoritative copy of durable content in its designated
remote repository or content system.

The platform intentionally does not prescribe subdirectories or metadata for a
work item. Conventions should be added only after repeated use demonstrates a
stable need.

Editor integrations are optional. A tool may generate a `.code-workspace` or
similar file inside a work-item folder, but the file remains ignored local
state and does not define the workspace itself.
