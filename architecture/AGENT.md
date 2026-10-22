# Architecture maintenance

Treat this directory as the portable specification for the implementation in
`platform/`. Preserve these approved deviations from the benchmark:

- canonical clones are under `repos/`, not `code/`;
- workspaces are project containers with flat work items beneath them;
- worktrees are flat, globally unique, and separate from canonical clones;
- there is no root installer or Makefile;
- `.env` is root-local and its template belongs to `platform/install/`;
- the shared runtime includes Hugo and SDKMAN.

Do not introduce another deviation silently. Change the implementation and the
relevant architecture contract together, regenerate `architecture/scaffold/`,
then run `platform/validate.sh`.
