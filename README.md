# Nova Fleet — Architecture Overview

A technical deep-dive on the Nova / Mira agent fleet that runs alongside Jascha
Kaykas-Wolff's work — process model, MCP wiring, memory architecture,
loop+harness pattern, and the scripts a team can adopt.

**HTML version:** [nova-fleet-overview.vercel.app](https://nova-fleet-overview.vercel.app)
(the same content, with the Bauhaus styleguide and easier to skim).

**Audience:** Andrew Stone and the VM Engineering team. Written so an engineer
can replicate the parts that are useful, ignore the rest, and not have to
reverse-engineer the live system to do it.

**What's not here:** Anything personal. No family, legal, non-VM project URLs,
or credentials. This repo is bounded to the technical infrastructure VM
engineering might find useful.

---

## 1. Shape of the fleet

Three peers, not a tree. Nova and Mira are long-running peers on one Mac mini.
Vellum is a third peer on a different machine. None of them invokes the others
— the human operator is the courier when handoffs are needed.

```
            ┌─────────────────────────┐
            │     Jascha (human)      │
            │  Telegram · iMessage    │
            └────┬───────────────┬────┘
                 │               │
       ┌─────────┴─┐         ┌───┴───────────┐
       │  Mac mini │         │  Work laptop  │
       │           │         │               │
       │   Nova ◄──┼─ files ─┼──► Vellum     │
       │   Mira    │         │               │
       │   (subs)  │         └───────────────┘
       └───────────┘
```

| Agent      | Host          | Role                                                  |
|------------|---------------|-------------------------------------------------------|
| Nova       | Mac mini      | Coding agent: builds, deploys, refactors, peer review |
| Mira       | Mac mini      | Ops + research: monitoring, content, SEO, daily stats |
| Vellum     | Work laptop   | Deep-work executor: long-form research, big context   |
| Sub-agents | Ephemeral     | Spawned per-task; named so the operator can talk      |

## 2. Process model

A Claude process is a CLI invocation; by default it dies with the terminal.
For a long-running agent you need three layers:

```
launchd (com.nova.telegram)
  └─ python3 nova-pty-runner.py
       └─ claude --dangerously-skip-permissions --channels <plugin>
            └─ bun (MCP subprocess: telegram plugin)
```

- **launchd** is the macOS supervisor. The LaunchAgent plist auto-restarts the
  job on crash and survives login/logout. Run user-level, not system — the
  process needs user-keychain access and the same TCC permissions a desktop
  session has.
- **PTY runner** (`scripts/nova-pty-runner.py`) allocates a real pseudo-terminal
  and spawns Claude inside it. Claude wants a real TTY for interactive mode;
  the runner gives it one without depending on tmux. (Earlier shape was tmux;
  tmux died when the host's tmux server died.)
- **Claude CLI** runs with channels enabled. Inbound messages from the channel
  arrive in context as `<channel>` blocks.
- **bun MCP subprocess** is a child of Claude. If it dies silently, the agent
  keeps running but the channel goes mute — known failure mode, see the
  watchdog (§7).

Restart:

```bash
launchctl kickstart -k gui/$(id -u)/com.nova.telegram
```

Inspect the live tree:

```bash
pgrep -fl nova-pty-runner.py
pgrep -P $(pgrep -f nova-pty-runner) | xargs -I{} ps -fp {}
```

See `examples/launchd-plist/com.example.agent.plist` for a template you can
adapt.

## 3. MCP wiring

Every external system the agents touch — Telegram, Slack, Gmail, Drive,
Supabase, Vercel, Fathom — is wired as an MCP (Model Context Protocol) server.
The agent doesn't talk to APIs directly; it calls tools the MCP server exposes.

Two flavors in this fleet:

| Flavor          | Example                                  | Auth                          |
|-----------------|------------------------------------------|-------------------------------|
| Hosted          | `gmail`, `drive`, `slack`, `vercel`      | OAuth via Claude.ai           |
| Local plugin    | `plugin:telegram@claude-plugins-official`| Bot token + access.json       |

The Telegram MCP runs as a local subprocess of Claude. Inbound messages arrive
as `<channel source="..." chat_id="..." ...>` blocks; outbound goes through the
`reply` tool. Access is managed by a local file (never by remote message —
that's deliberate to prevent prompt-injection of allowlist changes).

**Gotcha:** The bun MCP subprocess inherits Claude's env. If your bot token is
in `~/.zshrc` instead of the launchd plist or `~/.claude/.mcp.json`, the
subprocess won't see it. The agent comes up clean, but Telegram drops messages
silently.

## 4. Memory architecture

Claude's context resets every conversation. To survive across sessions, the
agents read a memory directory before every turn. The memory is files on disk,
indexed by a small synthesizer that prunes bloat.

File layout:

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

Why a flat directory of files works:

- **Auditable.** Git-able markdown. You can diff what changed between sessions.
- **Editable by hand.** Operator can correct the agent's beliefs with `$EDITOR`.
- **Composable.** Two agents can walk the same store via a symmetric template.
- **Synthesized, not appended.** A nightly job rewrites `MEMORY.md` from files
  on disk; bloat goes to a dated archive. The index never grows monotonically.

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
- Falsifiable done-checks force the assertion before the code (TDD dressed as
  shell).
- One commit per step → readable `git log`, easy rollback, easy review.

Worked example: the `feat/property-hub-loop` work in saleshub. The build
harness was 12 ordered steps with per-step contracts in `dev-spec.md`,
done-checks in shell, and handoffs in markdown. Each step ran in its own
Claude invocation; the next agent picked up from `state.json` cleanly.

See `docs/loop-harness-pattern.md` and `.claude/skills/loop-harness/SKILL.md`
for the invocable form.

**Two different loops, often confused:**

- **Build harness** — transient, ships the feature, deleted when done.
- **Operational loop** — production scheduled job, runs forever.

Same loop+harness *pattern*, different lifecycle.

## 6. Coordination

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

## 7. Heartbeat & watchdog

Long-running agents fail in quiet ways. The MCP subprocess dies but the parent
keeps running; the model returns text to the terminal instead of Telegram;
state drifts. You need an explicit liveness signal and an explicit watchdog.

The pattern:

1. **Heartbeat stamp.** Every Telegram reply runs
   `date +%s > ~/.claude/nova-telegram-last-msg.txt`.
2. **Watchdog cron.** A separate process polls the stamp. If the timestamp is
   older than threshold *and* there's been an inbound message since the last
   reply, it fires.
3. **Watchdog action.** First action is a Telegram alert to the operator.
   Restart is operator-initiated — auto-restart masks root cause.

See `scripts/heartbeat-watchdog.sh` for a reference implementation.

## 8. Repo tree

```
nova-fleet-overview/
├── README.md                         # this file
├── public/index.html                 # HTML version with Bauhaus styling
├── vercel.json                       # static-site deploy config
│
├── scripts/
│   ├── nova-pty-runner.py            # PTY supervisor (sanitized)
│   ├── nova-restart.sh               # launchctl kickstart pattern
│   ├── memory-init.sh                # drop a memory skeleton into a project
│   └── heartbeat-watchdog.sh         # watchdog pattern
│
├── docs/
│   ├── process-model.md              # process tree, restart, gotchas
│   ├── memory-template.md            # canonical frontmatter
│   ├── loop-harness-pattern.md       # full pattern with example
│   └── coordination.md               # file-based handoff conventions
│
├── .claude/
│   └── skills/
│       └── loop-harness/SKILL.md     # invocable skill
│
├── examples/
│   ├── launchd-plist/com.example.agent.plist
│   └── memory/                        # working memory examples
│       ├── MEMORY.md
│       ├── feedback_example.md
│       ├── project_example.md
│       └── reference_example.md
└── .gitignore
```

## 9. What's worth adopting

| Adopt                                  | Skip                                           |
|----------------------------------------|------------------------------------------------|
| Loop+harness pattern                   | Two peer agents on one host (specific to us)  |
| File-based memory with synthesizer     | OpenClaw gateway (Mira's side)                 |
| launchd + PTY for long-running agents  | Telegram-as-primary surface (operator UX)      |
| Heartbeat + watchdog discipline        |                                                |

**Smallest valuable adoption:** pick one engineering task that benefits from
multi-iteration work — a migration, a long-tail content port, a per-property
sweep. Write `state.json` + `check-iteration.sh` + `run-next-iteration.sh` for
it. Write a falsifiable done-check for each step. Run it. See if the resume
property pays for itself.

---

Nova is on Slack (`U09J4DLAFNZ` via Andrew's existing DM thread) for pairing
on any of this.
