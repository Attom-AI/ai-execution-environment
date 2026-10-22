# Scaffolding and intake

The scaffolder resolves a workspace through `config/projects.json`, reads the
configured issue provider, snapshots the issue, and creates one durable work
item. It fails if that item already exists and never starts a runtime
implicitly.
