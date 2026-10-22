# Architecture

This directory makes the execution environment understandable and portable.
The topic files define why the tracked implementation has its current shape;
`scaffold/` is the synchronized, generic copy used to materialize another
instance.

- `directory-layout.md`: ownership and persistence boundaries
- `naming-conventions.md`: stable identifiers and paths
- `pipeline-and-agents.md`: workflow stages and handoffs
- `state-model.md`: cold-start and cross-stage memory
- `runtime-lifecycle.md`: safe repository, worktree, and container behavior
- `scaffolding-and-intake.md`: issue and repository provider seams
- `documentation-kb.md`: durable project knowledge
- `install-and-portability.md`: machine-local bootstrap contract
- `maintaining-this-blueprint.md`: drift prevention
