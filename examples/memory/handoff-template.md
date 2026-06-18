# Handoff — {from-agent} → {to-agent} — YYYY-MM-DD

## What I just finished

- (one-liner per shipped thing, with artifact reference if relevant)
  - e.g.: "Completed content-pipeline steps 1–4. PR #88 open for review."
  - e.g.: "Fixed watchdog false-positive — updated threshold in heartbeat-watchdog.sh."

## What's open

- (one-liner per unresolved thread, with file path or URL)
  - e.g.: "Staging token missing — needed for step 5. Check plist EnvironmentVariables."
  - e.g.: "PR #89 waiting for reviewer approval before merging."

## What I'd like you to look at next

- (optional: a specific ask for the receiving agent)
  - e.g.: "Can you review the schema change in PR #89? Particularly the migration script."
  - (omit this section if there's no specific ask)

## Anything fragile

- (one-liner if there's something that might break without warning)
  - e.g.: "The cron job for weekly-analytics-ingest will run at 05:00 Monday. If step 5
    of content-pipeline isn't done by then, the ingest will use stale staging data."
  - (omit this section if nothing is fragile)

---

## Notes for adopters

This is the canonical handoff format used in the Mira Fleet Architecture. Keep it short.
The format is intentionally unstructured — the value is the discipline of writing it,
not a schema. If the handoff is longer than one screen, it's too long; summarize and
link to artifacts.

Filed at: `memory/handoffs/handoff-YYYY-MM-DD-{from}-to-{to}.md`
