# opencode_ios_client local notes

- `xcodebuild build` and `xcodebuild test` must run **sequentially**, not in parallel, because this repo shares the same DerivedData/build database and concurrent runs commonly fail with `build.db: database is locked`.
- If you need both validations, run build first, wait for it to finish, then run tests.
- Keep chat input UI tests anchored on stable accessibility identifiers rather than `TextField`-specific queries, because the composer implementation may use UIKit bridges.
