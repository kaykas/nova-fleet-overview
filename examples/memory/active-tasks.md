# Active Tasks

In-progress work items. Updated by the agent at each session start and end.

## In progress

### content-pipeline Phase 2
- **Status:** step 3 of 8
- **Blocked on:** staging token in environment config
- **Next action:** confirm token is set in launchd plist EnvironmentVariables
- **Harness:** `projects/content-pipeline/state.json`
- **Last updated:** 2026-01-15

### weekly-analytics-ingest cron
- **Status:** running; last successful run 2026-01-14 05:00
- **Blocked on:** nothing
- **Next action:** review output report for anomalies
- **Cron:** `0 5 * * 1` (Monday 5am)
- **Last updated:** 2026-01-15

## Pending (not yet started)

- Migrate staging database to new schema (waiting on schema freeze, ETA 2026-01-20)
- Add second watchdog for the analytics pipeline (currently unmonitored)

## Recently completed

- content-pipeline Phase 1 — shipped 2026-01-12, PR #87 merged
- Heartbeat threshold tuning — completed 2026-01-13, now at 20min instead of 15min

---

*Keep this file current. Stale entries here are worse than no entries — they mislead
the next agent session into thinking work is still in flight when it's done.*
