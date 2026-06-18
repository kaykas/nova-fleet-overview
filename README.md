# Mira Fleet Architecture

A public, sanitized architecture reference for long-lived AI agent systems
coordinated by Mira / OpenClaw. Covers process model, MCP wiring, memory
architecture, loop+harness pattern, and transferable scripts.

**HTML version:** [nova-fleet-overview.vercel.app](https://nova-fleet-overview.vercel.app)
(same content, Bauhaus styling, easier to skim; note: site URL reflects original repo name — repo rename to `mira-fleet-architecture` is a separate recommended step).

**Audience:** Engineers who want to replicate the useful parts and stand up
their own persistent agent fleet. Written so you can pick and choose — adopt
the loop pattern without the full fleet, or adopt the full fleet without
the private project context.

**What's not here:** Anything personal. No operator names, company names,
private project URLs, real credentials, or personal data. This repo is
bounded to the technical infrastructure patterns any team might find useful.
See the [privacy checklist](docs/privacy-checklist.md) for what was
deliberately excluded.

---

## 1. Shape of the fleet

Mira is the coordinator. Specialist agents are peers, not workers. No
orchestrator — the human operator is the routing layer when handoffs happen.

```
            ┌─────────────────────────┐
            │   Operator (human)      │
            │   chat channel          │
            └────┬───────────────┬────┘
                 │               │
       ┌─────────┴─┐         ┌───┴───────────┐
       │   Host A  │         │    Host B     │
       │           │         │               │
       │  Mira  ◄──┼─ files ─┼──► Vellum     │
       │  Peers    │         │               │
       │  (subs)   │         └───────────────┘
       └───────────┘
```

| Agent       | Host      | Role                                                             |
|-------------|-----------|------------------------------------------------------------------|
| Mira        | Host A    | Coordinator: ops, research, monitoring, content, publishing      |
| Peer agent  | Host A    | Specialist: coding, builds, deploys, long-form work              |
| Hermes      | Host A    | Substrate: nightly improvement pipeline (not a chat agent)       |
| Vellum      | Host B    | Remote executor: deep-work, web research, large context          |
| Sub-agents  | Ephemeral | Spawned per-task; named so the operator can talk about them      |

## 2. Process model

A Claude process is a CLI invocation; by default it dies with the terminal.
For a long-running agent you need three layers:

```
launchd (com.example.agent)
  └─ python3 agent-pty-runner.py
       └─ claude --dangerously-skip-permissions --channels <plugin>
            └─ bun (MCP subprocess: channel plugin)
```

- **launchd** is the macOS supervisor. The LaunchAgent plist auto-restarts
  the job on crash and survives login/logout. Run user-level, not system —
  the process needs user-keychain access and the same TCC permissions a
  desktop session has.
- **PTY runner** (`scripts/agent-pty-runner.py`) allocates a real
  pseudo-terminal and spawns Claude inside it. Claude wants a real TTY for
  interactive mode; the runner gives it one without depending on tmux.
- **Claude CLI** runs with channels enabled. Inbound messages from the
  channel arrive in context as `<channel>` blocks.
- **bun MCP subprocess** is a child of Claude. If it dies silently, the
  agent keeps running but the channel goes mute — known failure mode,
  see the watchdog (§9).

Restart pattern:

```bash
launchctl kickstart -k gui/$(id -u)/com.example.agent
```

Inspect the live tree:

```bash
pgrep -fl agent-pty-runner.py
pgrep -P $(pgrep -f agent-pty-runner) | xargs -I{} ps -fp {}
```

See `examples/launchd-plist/com.example.agent.plist` for a template you can
adapt. See `docs/process-model.md` for the full runbook.

## 3. MCP wiring

Every external system the agents touch is wired as an MCP (Model Context
Protocol) server. The agent doesn't talk to APIs directly; it calls tools
the MCP server exposes.

Two flavors in this fleet:

| Flavor          | Example                              | Auth                          |
|-----------------|--------------------------------------|-------------------------------|
| Hosted          | `gmail`, `drive`, `slack`, `vercel`  | OAuth via gateway account     |
| Local plugin    | `plugin:channel@claude-plugins-official` | Bot token + access.json    |

The channel MCP plugin runs as a local subprocess of Claude. Inbound messages
arrive as `<channel source="..." ...>` blocks; outbound goes through the
`reply` tool. Access is managed by a local file (never by remote message —
that's deliberate to prevent prompt-injection of allowlist changes).

**Gotcha:** The bun MCP subprocess inherits Claude's env. If your bot token
is in `~/.zshrc` instead of the launchd plist or `~/.claude/.mcp.json`,
the subprocess won't see it. The agent comes up clean, but the channel drops
messages silently.

## 4. Memory architecture

Claude's context resets every conversation. To survive across sessions,
agents read a layered memory system before every turn. See
`docs/memory-architecture.md` for the full deep-dive.

### Memory layers (fastest → deepest)

| Layer | What | When read |
|-------|------|-----------|
| 0 — Boot context | AGENTS.md, SOUL.md, PREFLIGHT_INJECT.md, MEMORY.md, today's log | Every session start (auto) |
| 1 — Flat-file memory | Typed markdown files: feedback, project, reference, user | On demand, or via boot context links |
| 2 — Daily raw log | `memory/YYYY-MM-DD.md` — raw session events | Boot (today + yesterday) |
| 3 — Semantic memory palace | Vector/embedding store, 9k+ entries, shared across agents | Explicit search call |
| 4 — Agent diaries | Per-agent append-only logs, tagged + scored | Explicit query |
| 5 — Project memories | Named project buckets with timelines and graphs | Explicit query |
| 6 — Compressed context | AAAK-compressed memory scopes (~30× smaller) | Explicit load |
| 7 — Relationship graph | Typed directed links between memories | Traversal calls |
| 8 — Handoff documents | `handoff-YYYY-MM-DD-{from}-to-{to}.md` | Next session start |
| 9 — Operational state | active-tasks.md, reminders.json, violation-log.md | Boot |

### Flat-file memory shape

```
memory/
  MEMORY.md                          # hand-curated index (≤150 lines)
  feedback_*.md                      # behavioral rules from corrections
  project_*.md                       # who/what/why for active work
  reference_*.md                     # pointers to external systems
  user_*.md                          # facts about the operator
```

Every memory file follows the same frontmatter:

```markdown
---
name: short-kebab-slug
description: one-line relevance hook
metadata:
  type: feedback   # user · feedback · project · reference
---

Rule, fact, or pointer.

**Why:** the reason this matters.
**How to apply:** when this guidance kicks in.

Cross-link other memories: [[other-memory-slug]]
```

Why flat files work:
- **Auditable.** Git-able markdown. Diff what changed between sessions.
- **Editable by hand.** Operator can correct the agent's beliefs with `$EDITOR`.
- **Composable.** Two agents walk the same store via a symmetric template.
- **Synthesized, not appended.** A nightly job rewrites `MEMORY.md` from
  files on disk; bloat goes to a dated archive. The index never grows monotonically.

### Memory write discipline

**Hard rule: search before claiming you don't know.** Before saying "I have
no context on X," search the memory palace. Skipping this when memories
exist is a protocol violation.

**Write targets:**
- Hard rules → `LESSONS_LEARNED.md`
- Operational state → EOD block in `MEMORY.md`
- Durable facts → flat-file + memory palace (both; palace alone is not read at boot)
- Project decisions → project memory + wiki

Drop-in scaffold: `scripts/memory-init.sh path/to/project` creates a `memory/`
dir with the canonical template and a starter `MEMORY.md`. See
`examples/memory/` for working examples.

## 5. Loop + harness pattern

For anything that takes more than one turn, the agent writes a falsifiable
assertion, runs one iteration, checks the assertion, decides the next step.
Three artifacts on disk. Resumable across context resets.

```
state.json                Source of truth: next_step, completed, last_failure
check-iteration.sh        Done-check. Exit 0 = current iteration passed.
run-next-iteration.sh     Reads state, executes next step only, updates state.
```

Why this is worth adopting:

- Multi-iteration work survives context resets — the agent finishing step 7
  doesn't have to be the agent that started step 1.
- Falsifiable done-checks force the assertion before the code (TDD dressed
  as shell).
- One commit per step → readable `git log`, easy rollback, easy review.

**Two different loops, often confused:**

- **Build harness** — transient, ships the feature, deleted when done.
- **Operational loop** — production scheduled job, runs forever.

Same loop+harness *pattern*, different lifecycle.

See `docs/loop-harness-pattern.md` and `.claude/skills/loop-harness/SKILL.md`
for the invocable form.

## 6. Hermes — nightly fleet improver

Hermes is the cron-driven substrate that runs while everyone sleeps. It reads
what the fleet did during the day, drafts what to surface next, and leaves
each agent a curated brief to start tomorrow with.

Pipeline shape:

```
activity-aggregator   reads logs, receipts, git, message buffer
        │
        ▼
planner               turns activity into proposed work items
        │
        ▼
contract-creator      writes each work item as a falsifiable contract
        │
        ▼
executor              runs contracts that don't need human approval
        │
        ▼
qa-verifier+curator   grades outputs, files acceptance, archives misses
        │
        ▼
preflight-generator   writes per-agent next-session briefings
```

What lands on disk each night:

| Artifact                       | Purpose                                                  |
|--------------------------------|----------------------------------------------------------|
| `coordinator-queue.md`         | Backlog of contracts waiting for the coordinator to claim |
| `contracts/*.json`             | One file per work item, falsifiable success criteria      |
| `plans/*.md`                   | Longer-form plans (promoted to contracts later)           |
| `preflight-{agent}.md`         | Next-session briefing injected on session start           |
| `deltas/`, `receipts/`         | Audit trail                                              |

Why a pipeline and not a single agent:
- **Composable.** Each stage is a small script with a single responsibility.
- **Restartable.** Any stage can re-run on its inputs.
- **Watchable.** Watchdogs run between stages and catch problems Hermes
  itself can't see.
- **Cron-friendly.** Stages run on independent schedules.

**Portable pattern:** even without agents, a daily "read what changed in
your repos + what's open in your tracker + what merged that might affect you"
cron is a useful version of the same idea.

## 7. HTML brain — the operator's window

Everything Hermes produces is rendered to HTML at a private auth-gated site.
The operator opens it to see fleet state, approve or reject contracts, read
EOD reports, and reference the canonical design system.

Key surfaces:

| Surface                  | What it shows                                       |
|--------------------------|-----------------------------------------------------|
| `/index.html`            | Landing — index of every artifact emitted today     |
| `/dashboard/`            | Live fleet dashboard                                |
| `/eod/{date}/`           | End-of-day reports                                  |
| `/fleet-{date}.html`     | Daily fleet snapshot                                |
| `/hermes/`               | Hermes pipeline outputs                             |
| `/api/approve`           | Bearer-auth approve/reject endpoint                 |
| `/api/health`            | Public health check (no auth)                       |

Auth model: Edge Middleware checks a key in the query string on first visit,
sets an HTTP-only cookie good for 90 days, redirects to a clean URL.
`/api/health` is intentionally public. Mutating endpoints require a
bearer token (separate from the cookie).

**Portable pattern:** static-site deploy + edge auth + nightly cron rendering
the day's state to HTML + git push. No SaaS. No shared backend. Add edge
auth when the data sensitivity justifies it.

## 8. Coordination

Two agents on one host, no message bus. Shared filesystem, file-based async
handoffs, human operator as the routing layer.

```
shared/
  memory/                            # symmetric memory store
  handoff-YYYY-MM-DD-{from}-to-{to}.md
  intelligence/                      # shared data
```

No locks, no queues, no retry semantics. Two cooperating peers writing files
in a shared directory. Works because the operator is in the loop — if you
removed the operator you'd need real coordination primitives.

For a third agent: add a directory and a memory namespace. Don't add a
message bus. Stay flat for as long as it stays useful.

See `docs/coordination.md` for the full pattern.

## 9. Heartbeat & watchdog

Long-running agents fail in quiet ways. The MCP subprocess dies but the
parent keeps running; the model returns text to the terminal instead of
the channel; state drifts. You need an explicit liveness signal and a
watchdog.

The pattern:

1. **Heartbeat stamp.** Every channel reply runs
   `date +%s > ~/.claude/agent-last-output.txt`.
2. **Watchdog cron.** A separate process polls the stamp. If the timestamp is
   older than threshold *and* there's been an inbound message since the last
   reply, it fires.
3. **Watchdog action.** First action is an alert to the operator.
   Restart is operator-initiated — auto-restart masks root cause.

See `scripts/heartbeat-watchdog.sh` for a reference implementation.

## 10. Repo tree

```
mira-fleet-architecture/
├── README.md                          # this file
├── public/index.html                  # HTML version (Bauhaus styling)
├── vercel.json                        # static-site deploy config
│
├── scripts/
│   ├── agent-pty-runner.py            # PTY supervisor (generic)
│   ├── agent-restart.sh               # launchctl kickstart pattern
│   ├── memory-init.sh                 # drop a memory skeleton into a project
│   ├── heartbeat-watchdog.sh          # watchdog pattern
│   └── privacy-scan.sh                # scan for sensitive terms before commit
│
├── docs/
│   ├── process-model.md               # process tree, restart, gotchas
│   ├── memory-architecture.md         # full 10-layer memory architecture
│   ├── loop-harness-pattern.md        # full pattern with worked example
│   ├── coordination.md                # file-based handoff conventions
│   └── privacy-checklist.md           # what to check before any public commit
│
├── .claude/
│   └── skills/
│       └── loop-harness/SKILL.md      # invocable skill
│
├── examples/
│   ├── launchd-plist/com.example.agent.plist
│   └── memory/
│       ├── MEMORY.md                  # index template
│       ├── feedback_example.md
│       ├── project_example.md
│       ├── reference_example.md
│       ├── daily-log.md               # raw daily session log template
│       ├── active-tasks.md            # in-progress work tracker template
│       └── handoff-template.md        # handoff format template
└── .gitignore
```

## 11. What's worth adopting

| Adopt                                       | Skip                                                         |
|---------------------------------------------|--------------------------------------------------------------|
| Loop+harness pattern                        | Two peer agents on one host (specific to this fleet shape)   |
| Full layered memory architecture            | OpenClaw gateway (more than most teams need to start)        |
| launchd + PTY for long-running agents       | Telegram-as-primary surface (operator UX preference)         |
| Heartbeat + watchdog discipline             | All 9 watchdogs (start with one; earn the rest)              |
| Hermes-style nightly pipeline               |                                                              |
| HTML brain (static site + edge auth)        |                                                              |
| File-based memory with synthesizer          |                                                              |
| Semantic memory palace (vector store)       | (add after flat-file layer is working)                       |

**Smallest valuable adoption:** pick one engineering task that benefits from
multi-iteration work — a migration, a long-tail content port, a per-property
sweep. Write `state.json` + `check-iteration.sh` + `run-next-iteration.sh` for
it. Write a falsifiable done-check for each step. Run it. See if the resume
property pays for itself.

---

## 12. Transferable quickstart

Clone this repo and hand it plus a brief prompt to a fresh Claude Code agent:

```
Read the Mira Fleet Architecture companion repo at <repo-url>.

In a new directory, set me up a single persistent agent:
- launchd + PTY runner so it survives terminal close
- file-based memory/ dir with the synthesizer
- the loop+harness skill
- a heartbeat stamp + watchdog cron

Skip the second agent and the OpenClaw side for now — one agent,
the plumbing, nothing I have to reverse-engineer. Tell me what to
fill in (tokens, paths, launchd label) as you go.
```

That's the whole point of writing this down: the patterns are portable, and
the repo plus a prompt is enough to start.

### Directory scaffold to drop in

```bash
./scripts/memory-init.sh ./my-agent
# Creates:
#   my-agent/memory/MEMORY.md
#   my-agent/memory/_template.md
```

Then copy `examples/launchd-plist/com.example.agent.plist` to
`~/Library/LaunchAgents/com.example.agent.plist`, fill in `{{HOME}}` and
your script paths, and run:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.agent.plist
launchctl kickstart gui/$(id -u)/com.example.agent
```

### Env placeholders

| Variable | What it is | Where to set it |
|----------|-----------|-----------------|
| `ANTHROPIC_API_KEY` | LLM provider API key | launchd plist EnvironmentVariables |
| `CHANNEL_BOT_TOKEN` | Your channel's bot token | launchd plist EnvironmentVariables |
| `GATEWAY_API_KEY` | OpenClaw gateway key (if using) | launchd plist EnvironmentVariables |

Never put secrets in `~/.zshrc` — launchd doesn't source it.

### Privacy checklist (run before any public commit)

```bash
./scripts/privacy-scan.sh
```

See `docs/privacy-checklist.md` for the full manual checklist.

---

## 13. Operating principles

The architecture above is the easy half. These principles are the spine that
keeps a persistent fleet from quietly rotting.

**Pick the metric that tracks your contribution, not the noisy aggregate.**
Gate on the axis you control. A threshold on the wrong metric is worse than
no threshold — it trains you to ignore the alarm.

**When you ingest human feedback, read the surface humans actually use.**
A pipeline that reads the wrong surface fails quietly. Verify you're capturing
the channel people actually talk in, and test with a real message.

**Never trust a status field. Verify the artifact it describes.**
Status fields record intent, not outcome. Before you believe "done," read
the thing it claims to have changed.

**Encode the rule at the gate, once. Don't rely on catching it each time.**
Your most important "remember to…" should become a check that runs
automatically — not something you rely on attention to enforce.

**Loops and harnesses are the default, not the exception.**
Write the falsifiable check first. Change the artifact. Keep the change
only if the check improves. Revert on regression.

**The single host is the proving ground, not the destination.**
The patterns here rehearse an architecture that can lift to a multi-tenant
platform. The interfaces — file memory, loop+harness, heartbeat, the brief
pipeline — survive the move; the single-host plumbing is what gets replaced.
