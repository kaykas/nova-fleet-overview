---
name: loop-harness
description: For multi-iteration work — sets up state.json + check-iteration.sh + run-next-iteration.sh in the current project and seeds an initial step.
---

# Loop + Harness Skill

Invoke this when starting any work that will take more than one turn or one
session. It sets up the three artifacts that make multi-iteration agent work
survivable across context resets.

## Inputs the operator needs to provide

1. **Feature name** (kebab-case): e.g. `property-hub-claremont`.
2. **Total steps** (rough estimate): e.g. 12.
3. **Step 1 contract:** a one-paragraph description of what step 1 does and
   what its done-check is.

If any are missing, ask.

## What this skill produces

```
state.json                Initialized with feature, phase=1, next_step=1, empty completed[].
check-iteration.sh        Stub with a single dispatch case for step 1.
run-next-iteration.sh     Reads state, runs check-iteration.sh, advances on pass.
dev-spec.md               Empty contract list with step 1 filled in.
```

## What this skill enforces

- **Falsifiable done-checks.** Step 1's done-check must be a shell command
  that exits non-zero on fail. If the operator proposes "looks good" as the
  check, push back and ask for something greppable.
- **One step at a time.** The skill installs the harness but does not
  execute step 1 — that's the next iteration.
- **State.json invariants.** `next_step` starts at 1; `completed_steps` is
  empty; `last_failure` is null.

## What happens next

After this skill runs, you (or the next agent) should:

1. Read `state.json` to see `next_step`.
2. Read the step contract in `dev-spec.md`.
3. Execute the step.
4. Run `./check-iteration.sh`.
5. If pass: `./run-next-iteration.sh` advances state and commits.
6. If fail: write the failure to `state.json.last_failure` and stop.

## When NOT to use this skill

- Bug fixes you can finish in one turn.
- Work where step 1 is irreversible (sends email, mutates prod DB) — wrap
  those in a separate confirmation gate, don't bury them in a loop.
- Work where the spec might shift mid-flight — write the spec first.
