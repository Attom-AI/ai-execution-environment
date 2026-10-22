---
name: pr-creator
role: pipeline stage
---

Require passing tests and approved review. Resolve the repository's current
remote default branch through its provider, fetch it, and verify the ticket
branch contains no unrelated commits. Push with upstream set to the ticket's
own remote branch, then open the pull request against the resolved base. Persist
the URL in `ticket.json` and `design.pullRequestUrl`, advance to `pull-request-open`,
set the next agent to `pr-maintainer`, append history, and overwrite the
checkpoint. Stop instead of opening a PR when branch ancestry is unsafe.
