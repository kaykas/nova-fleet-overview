---
name: feedback-example
description: Example of how to capture a behavioral rule learned from a correction
metadata:
  type: feedback
---

Run the lint task before committing — don't rely on the CI pre-commit hook
catching obvious issues, because the hook isn't installed on the macOS dev
boxes.

**Why:** The CI hook silently degrades on macOS because of a node-version
mismatch between the hook env and the local dev env. Discovered after three
PRs landed with formatting drift, 2026-02-14.

**How to apply:** Before any commit on this repo, run `pnpm lint:fix` and
`pnpm typecheck` locally. Don't trust the pre-commit hook to catch it.

Cross-references: [[reference-example]] for where the hook lives.
