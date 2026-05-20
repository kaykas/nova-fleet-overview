---
name: reference-example
description: Example of an external-systems pointer memory
metadata:
  type: reference
---

Pipeline bugs are tracked in Linear project `INGEST`. Use this when the
operator references a bug ID without naming the system.

The on-call latency dashboard is at `grafana.internal/d/api-latency`. Check
it when editing request-path code.

CI hook source lives in `tooling/hooks/pre-commit.sh` — referenced by
[[feedback-example]].
