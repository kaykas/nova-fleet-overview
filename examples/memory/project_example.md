---
name: project-example
description: Example of an active-work memory — who, what, why, by when
metadata:
  type: project
---

The auth-middleware rewrite is being driven by compliance, not tech-debt
cleanup. Legal flagged it 2026-01-31 for storing session tokens in a way
that does not meet the new regulatory requirements coming into force
2026-04-01.

**Why:** Compliance deadline is hard — the regulation is in force as of
2026-04-01, and the company's audit posture depends on demonstrating
remediation.

**How to apply:** Any scope decisions on this work should favor compliance
correctness over developer ergonomics. If the trade-off is "this is a
slightly nicer API but doesn't meet the regulation" vs "uglier API that
meets it," choose the uglier API.

Status: middleware ready 2026-03-12, integration tests in progress, target
production deploy by 2026-03-25 to leave buffer.
