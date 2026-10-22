# State protocol

Every work item has three memory layers:

- stage-local reasoning, which is not persisted;
- artifacts passed between adjacent stages under `artifacts/`;
- global `meta.json` and `session-state.md`, read by every stage.

`meta.json` contains bounded structured state: lifecycle stage, gates, loop
counters, durable branch/PR references, resume pointer, blocking state, close
state, and runtime pointers. `session-state.md` is overwritten at every stage
transition with status, next step, open questions, decisions, and files in
flight. `history.log` is append-only.

Every stage must read both global files before acting. Before returning it must
update its gates and lifecycle stage, set `resume.nextAgent`, update the resume
audit fields, append one history entry, and overwrite the narrative checkpoint.
A loop that would exceed `maxAttempts` sets `blocked.isBlocked` and stops.
