# Workspace scaffolder

The scaffolder resolves a project workspace through `config/projects.json`,
normalizes an external issue through a source adapter, initializes durable state
without overwriting an existing work item, safely synchronizes the canonical
repository, and starts or resumes its runtime unless `--no-start` is supplied.

```bash
./platform/workspace-scaffolder/scaffold.sh eiakoji-me-blog 12 --type FEAT
```
