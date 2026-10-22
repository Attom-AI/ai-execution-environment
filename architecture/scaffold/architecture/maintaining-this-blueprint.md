# Maintaining the blueprint

`architecture/scaffold/` is a generated generic copy of the tracked control
plane. Any change to platform behavior, workflow definitions, architecture,
documentation shape, backlog shape, or root policy makes it stale.

For every such change:

1. update implementation and the affected architecture rationale together;
2. run `architecture/sync-scaffold.sh`;
3. inspect the scaffold diff for accidental instance data or missing files;
4. run `platform/validate.sh`;
5. commit the implementation and regenerated scaffold together.

Synchronization is mechanical. Deciding whether a behavioral change requires a
new explanation is the responsibility of the person making that change.
