# Coordination — Two Agents, One Host, No Message Bus

Nova and Mira are peers. They don't call each other. They share a filesystem
and the human operator. Surprisingly robust for the work they do together.

## Shared filesystem layout

```
~/.openclaw/workspace/
├── memory/                              # symmetric memory store; both agents walk it
│   ├── MEMORY.md
│   ├── feedback_*.md
│   ├── project_*.md
│   ├── reference_*.md
│   └── user_*.md
│
├── handoff-{date}-{from-agent}-to-{to-agent}.md  # async handoff
│
├── intelligence/                        # shared data: SEO, monitoring, etc.
│   ├── agent-health.json
│   ├── daily-revenue-summary.json
│   └── …
│
└── hermes-fleet-improver/               # shared nightly improvement pipeline
    ├── nova-queue.md                    # work Mira would like Nova to consider
    └── scripts/
```

## Handoff convention

Filename: `handoff-YYYY-MM-DD-{from}-to-{to}.md`

Body:

```markdown
# Handoff — {from} → {to} — {date}

## What I just finished
- (one-liner per shipped thing)

## What's open
- (one-liner per unresolved thread, with file paths or URLs)

## What I'd like you to look at next
- (one-liner if there's a specific ask; otherwise omit)

## Anything fragile
- (one-liner if there's something that might break without you knowing)
```

That's the whole format. No JSON schema, no validation, no priority queue.

## Why this is OK

The agents are *cooperating*, not contending. There's no shared mutable state
that two writers might race on; each agent owns the directories it writes to,
and reads (but doesn't mutate) the other's. The memory store is the closest
thing to shared mutable state, and it's append-mostly-only with a synthesizer
that rewrites the index atomically.

The other thing keeping this simple: **the operator is in the loop.** If a
handoff goes unread for two days, the operator notices in the daily digest
and routes it. If both agents touch the same project at once, the operator
sees the divergence in the next status update. You don't need a message bus
if you have a human who reads diffs.

## When you'd need a real coordination layer

- Agents that need to race for the same work (you have one).
- Agents that mutate shared state with strict ordering (e.g., a shared
  counter, a shared queue with at-least-once semantics).
- Agents without a human routing layer.

In any of those cases, the right answer is probably a real job queue
(Redis / SQS / NATS) or a real workflow engine (Temporal / Inngest), not a
homegrown thing on top of files. Don't graduate prematurely; do graduate when
the cooperation pattern stops fitting.

## Adding a third agent

- Pick a name (one syllable preferred).
- Give it a memory namespace if it needs its own behavioral rules.
- Pick which directories it reads and which it writes.
- Add it to the handoff dictionary (who can hand off to whom).

Don't add a message bus.
