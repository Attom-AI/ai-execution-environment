# Work pipeline

```text
issue intake -> work-item state -> design -> implementation -> verification
             -> review -> pull request -> close
```

Agents resume from the work item, not from a runtime. The worktree and
container may be recreated without losing intent, decisions, or artifacts.
