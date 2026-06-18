# Memory Architecture

Long-lived agents need persistent memory that survives context resets. This
document describes the layered memory architecture used in the Mira Fleet,
from fast boot context through long-term semantic storage.

---

## Memory layers (fastest → deepest)

### Layer 0 — Boot context (auto-read every session)

Files injected into the agent's context at session start. The agent reads
these before every turn.

| File | Purpose |
|------|---------|
| `AGENTS.md` | Role, routing rules, and session-start checklist |
| `SOUL.md` | Core personality and non-negotiable principles |
| `PREFLIGHT_INJECT.md` | Hard stops that can never be bypassed |
| `MEMORY.md` | Hand-curated index of active memories (≤150 lines) |
| `memory/YYYY-MM-DD.md` | Today's and yesterday's raw session notes |
| `memory/active-tasks.md` | In-progress task state |
| `memory/violation-log.md` | Last 20 protocol violations (recency beats familiarity) |

**Design principle:** boot context is always small. Long-form detail lives
in deeper layers; boot context is the index, not the encyclopedia.

---

### Layer 1 — Curated flat-file memory

A directory of typed markdown files, each with YAML frontmatter:

```
memory/
  MEMORY.md                    # hand-curated index
  feedback_*.md                # behavioral rules from corrections
  project_*.md                 # who/what/why for active work
  reference_*.md               # pointers to external systems
  user_*.md                    # facts about the operator
```

Every file follows the same shape:

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

**Write targets:** new facts → individual typed files. Index → `MEMORY.md`
(hand-curated or rewritten nightly by synthesizer). Never append raw session
output directly to `MEMORY.md`.

**Why flat files:**
- Auditable: every change is a git diff.
- Editable by hand: operator corrects wrong beliefs by editing a file.
- Composable: two agents can walk the same store via symmetric templates.
- Synthesized, not appended: the index is rewritten from source files; bloat
  goes to a dated archive (`MEMORY.md.archive-YYYY-MM-DD`).

---

### Layer 2 — Daily raw log

`memory/YYYY-MM-DD.md` captures raw session events, decisions, and notes
for the current and prior day. Not curated — that's layer 1's job. Rotated
nightly; prior days compressed to summaries.

---

### Layer 3 — Semantic memory palace (vector store)

A SQLite + vector-embedding store with 9,000+ entries, shared across
agents. Used for fuzzy recall of prior decisions, project history, contact
facts, and anything that didn't make it into the flat-file curated layer.

**Access:** explicit search call (`search_memory(query)`). Not auto-read
at boot — too large.

**Write targets:** durable facts that should survive across months. Always
write to both flat files AND the palace; the palace alone is not read at
boot and will be missed.

Schema per entry:

```
key          — unique slug (e.g., "project_atlas_status")
value        — the memory content
category     — personal, work, legal, technical, general
importance   — 1–5 (5 = critical)
tags         — list of topic tags
project      — optional project bucket
wing/room    — palace location for hierarchical browsing
```

Memory palace hierarchy:
- **Wing** — domain (e.g., `work`, `personal`, `legal`, `infrastructure`)
- **Room** — topic within a wing (e.g., `deployment`, `seo`, `custody-case`)
- **Hall** — memory type: `fact`, `event`, `decision`, `preference`, `advice`, `problem`

---

### Layer 4 — Agent diaries

Per-agent append-only diary entries (structured logs with tags and
importance scores). Used for: session reflections, pattern discovery,
important events. Queryable by tag or importance.

---

### Layer 5 — Project memories

Memories tagged to a named project bucket. Support: timelines, summary
views, relationship graphs between project memories. Projects: e.g.
`content-pipeline`, `infrastructure`, `research-initiative`.

---

### Layer 6 — Compressed context

Pre-computed AAAK-compressed representations of memory scopes (up to ~30×
smaller). Used for: loading large memory contexts efficiently into a single
model call, project briefings, handoff generation.

---

### Layer 7 — Relationship graph

Typed directed relationships between memories:

| Type | Meaning |
|------|---------|
| `related_to` | general semantic connection |
| `causes` | A causes B |
| `part_of` | A is a component of B |
| `contradicts` | A and B conflict |
| `updates` | A supersedes B |
| `references` | A cites B |

Traversal: `get_related(key, depth=2)` for neighborhood, `get_memory_graph(key)` for full subgraph.

---

### Layer 8 — Handoff documents

Structured markdown files written at session end, consumed at the start of
the next session. Format:

```
handoff-YYYY-MM-DD-{from}-to-{to}.md

# Handoff — {from} → {to} — {date}

## What I just finished
## What's open
## What I'd like you to look at next
## Anything fragile
```

---

### Layer 9 — Operational state files

Files that track in-flight work and violations:

| File | Purpose |
|------|---------|
| `memory/active-tasks.md` | In-progress tasks with status |
| `memory/reminders.json` | Scheduled reminders |
| `memory/violation-log.md` | Protocol violations (last 20) |
| `memory/autonomous-work-log.md` | Log of autonomous actions taken |
| `memory/trigger-state.json` | Cron trigger state |

---

## Write discipline

**Hard rule: search before claiming you don't know.** Before telling the
operator you have no context on a topic, search the memory palace. "I don't
have context" when memories exist is a protocol violation.

**Write targets by type:**

| What | Where |
|------|-------|
| Hard rules / lessons learned | `LESSONS_LEARNED.md` |
| Operational state | EOD block in `MEMORY.md` |
| Durable facts | Flat-file + memory palace (both) |
| Project decisions | Project memory entry + wiki page |
| Session events | `memory/YYYY-MM-DD.md` |
| Important events | Agent diary (importance ≥ 4) |

**Mental notes don't survive restarts. Write things down.**

---

## Privacy boundaries

Memory is partitioned by agent. Each agent only reads its assigned memory
namespace. Boundaries are enforced at the session configuration level, not
by convention.

Hard stops:
- Never write private data (PII, credentials, private project details) to
  shared memory layers.
- Agent diaries and project memories may contain operational detail but
  must not contain credentials or identifying information.
- Compressed context exports strip any entry flagged as private before
  compressing.

---

## Quickstart: memory-init

To drop a memory directory into any project:

```bash
./scripts/memory-init.sh /path/to/your/project
```

Creates `memory/MEMORY.md` and `memory/_template.md`. See
`examples/memory/` for working examples of each file type.
