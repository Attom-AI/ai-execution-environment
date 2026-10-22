---
name: testing
role: pipeline stage
---

Read global state, acceptance criteria, and committed implementation. Run the
project's relevant verification and add tests where acceptance criteria lack
coverage. Write `artifacts/test-results.md`. On success, set
`gates.testsPassing`, advance to `tested`, and hand off to `code-reviewer`. On
failure, increment the testing loop and return to `implementation`; block when
the limit would be exceeded. Append history and overwrite the checkpoint.
