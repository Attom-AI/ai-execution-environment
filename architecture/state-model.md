# State model

There are three memory layers:

1. invocation-local reasoning, which is never persisted;
2. artifacts passed between adjacent stages under `artifacts/`;
3. global work-item state readable by every stage.

The global layer contains `meta.json`, `session-state.md`, and `history.log`.
`meta.json` is JSON deliberately: platform scripts already depend on `jq`, so
state updates are deterministic without introducing a YAML writer. Its schema
tracks identity, lifecycle stage, gates, bounded loops, branch and PR
references, CI/review status, resume target, blocking and closure state, and
runtime pointers.

`session-state.md` is overwritten at each transition and always contains
status, next action, open questions, key decisions, and files in flight.
`history.log` is append-only and is consulted only when the transition history
is needed.

Every stage reads the global files before acting and updates all three before
returning. A stage that cannot safely continue sets the structured blocked
state with a reason and timestamp.
