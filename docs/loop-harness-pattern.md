# The Loop + Harness Pattern

For any non-trivial agent task — anything that takes more than one turn — the
agent writes a falsifiable assertion, runs one iteration, checks the
assertion, decides the next step. Three artifacts on disk. Resumable across
context resets.

## Three artifacts

```
state.json                Source of truth: next_step, completed[], last_failure
check-iteration.sh        Done-check. Exit 0 = current iteration passed.
run-next-iteration.sh     Reads state, executes next step only, updates state.
```

That's it. The pattern is small on purpose — the value is the *discipline* of
writing the done-check before the code, not the framework.

## state.json shape

```json
{
  "feature": "property-hub-claremont",
  "phase": 1,
  "steps_total": 12,
  "next_step": 7,
  "completed_steps": [1, 2, 3, 4, 5, 6],
  "last_run_at": "2026-05-15T18:34:00Z",
  "last_done_check_results": {
    "step_6": "pass",
    "details": "FAQPage schema renders, 6 questions present, jsonld valid"
  },
  "last_failure": null,
  "open_questions": [
    "Q7: confirm DB property record uses post-rebrand name",
    "Q9: BWT account access + verification token on prod"
  ]
}
```

Hard rules:
- **state is the truth.** If `next_step=4` and you think it should be 5,
  *stop*. Either fix state deliberately (recording why in the next handoff)
  or do step 4. Never silently skip.
- **idempotent.** Running the same step twice produces the same on-disk
  result. State stays consistent.
- **one failure mode per step.** If a check fails, write the failure to
  `last_failure` AND to a handoff file, then stop. Human reads, decides
  retry vs change plan.

## check-iteration.sh shape

```bash
#!/usr/bin/env bash
# Done-check for step N. Exit 0 = pass. Anything else = fail.
# Pulls the step number from state.json and dispatches.

set -euo pipefail
STEP="$(jq -r .next_step state.json)"

case "${STEP}" in
  1)
    test -f apps/web-next/src/app/properties/[id]/page.tsx
    ;;
  2)
    # JSON-LD on the rendered page contains LodgingBusiness schema
    curl -fsSL "${PREVIEW_URL}/properties/4042" \
      | grep -q '"@type":"LodgingBusiness"'
    ;;
  3)
    # FAQ schema renders ≥6 questions
    N=$(curl -fsSL "${PREVIEW_URL}/properties/4042" \
        | grep -o '"@type":"Question"' | wc -l)
    [ "${N}" -ge 6 ]
    ;;
  # … more steps …
esac
```

The pattern: every check is something you can run from a shell and grep.
"Looks good" is not allowed. If you can't write a done-check for a step, the
step isn't well-specified yet.

## run-next-iteration.sh shape

```bash
#!/usr/bin/env bash
# Run the next step. Reads state, looks up the step contract,
# invokes the agent (or executes inline), commits, updates state.

set -euo pipefail
STEP="$(jq -r .next_step state.json)"
CONTRACT="$(jq -r ".steps[\"${STEP}\"]" dev-spec.json)"

echo "▸ running step ${STEP}…"
# … execute the step (this is where the agent gets invoked) …

if ./check-iteration.sh; then
  jq ".completed_steps += [${STEP}] | .next_step += 1 | .last_failure = null | .last_run_at = now | .last_run_at |= todate" state.json > state.json.tmp
  mv state.json.tmp state.json
  git add -A
  git commit -m "feat(scope): step ${STEP} complete"
  echo "▸ step ${STEP} ok"
else
  jq ".last_failure = \"step ${STEP} done-check failed\" | .last_run_at = now | .last_run_at |= todate" state.json > state.json.tmp
  mv state.json.tmp state.json
  echo "▸ step ${STEP} FAILED — human review required"
  exit 1
fi
```

## Worked example: feat/property-hub-loop

Phase 1 of the Property Hub feature in saleshub was built as a 12-step loop:

| Step | Done-check                                                  |
|------|-------------------------------------------------------------|
| 1    | route file exists, type-check green                         |
| 2    | LodgingBusiness JSON-LD in HTML                             |
| 3    | FAQPage schema, ≥6 questions                                |
| 4    | meta + OG tags present, og:image is a valid URL             |
| 5    | dual CTA renders (direct booking + lead-gen)                |
| 6    | sameAs entity links present, each URL resolves              |
| 7    | robots.txt has train-vs-cite split                          |
| 8    | IndexNow endpoint responds 200                              |
| 9    | Bing Webmaster verification meta tag in head                |
| 10   | GA4 dataLayer initializes with AI-referrer channel group    |
| 11   | CWV budget green (LCP < 2.5s, no lazy on hub render path)   |
| 12   | demo gate — human review before Phase 2 expansion           |

When Phase 1 shipped, the build harness closed: `state.json`,
`run-next-iteration.sh`, and the per-step handoffs were deleted. They were
build tracking, not the operational product. The B9 *operational* loop
(weekly GSC + GA4 ingest, research subagent, safe-changes applied, audit log)
is separate Phase 4 work — same pattern, different lifecycle, built as
scheduled-job infrastructure instead of a JSON file in the repo.

## When NOT to use this pattern

- **One-shot work.** A bugfix you can hold in your head doesn't need
  state.json. The overhead beats the value.
- **Genuinely irreversible steps.** If step 3 sends an email or migrates a
  prod database, "idempotent on rerun" is a lie. Wrap those steps in a
  separate confirmation gate.
- **Work where the spec is wrong.** The loop assumes the step contracts are
  right. If you find yourself rewriting `dev-spec.md` mid-loop, stop the
  loop and re-spec first.

## When this pattern shines

- Multi-iteration work that might span days.
- Work where the agent that finishes step 7 might not be the agent that
  started step 1 (different sessions, different humans).
- Work where you want a readable `git log` and easy rollback at any step.
- Work where you genuinely don't know if step N will succeed and want a
  clean failure surface.
