# Maintaining the blueprint

The blueprint and implementation change together:

1. update executable behavior under `platform/`;
2. update only the architecture pages whose contract changed;
3. run `./platform/validate.sh`;
4. verify no materialized path is tracked.

`sync-scaffold.sh` copies the portable tracked tree to an empty destination for
distribution testing.
