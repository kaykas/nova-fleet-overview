#!/usr/bin/env bash
# Drop a Claude-Code-compatible memory directory into a project.
#
# Usage: ./memory-init.sh <project-dir>
#
# Creates:
#   <project-dir>/memory/MEMORY.md
#   <project-dir>/memory/_template.md
#
# Convention: the agent reads <project-dir>/memory/ on every turn. New
# memory files land alongside MEMORY.md. Each file has YAML frontmatter
# naming its type (user / feedback / project / reference); the index in
# MEMORY.md is hand-curated (or rewritten by a synthesizer cron).

set -euo pipefail

DEST="${1:?usage: memory-init.sh <project-dir>}"
MEMDIR="${DEST}/memory"

if [ -e "${MEMDIR}" ]; then
  echo "memory/ already exists at ${MEMDIR}; refusing to overwrite"
  exit 1
fi

mkdir -p "${MEMDIR}"

cat > "${MEMDIR}/MEMORY.md" <<'EOF'
# MEMORY — Project Index
_Curate this by hand. Synthesizer (if present) appends below the divider._

## Index
- (add entries like: `- [Short label](file.md) — one-line hook`)

---

## Synthesizer output
_(synthesizer-managed; do not edit by hand)_
EOF

cat > "${MEMDIR}/_template.md" <<'EOF'
---
name: short-kebab-slug
description: one-line relevance hook used to decide if this memory is relevant
metadata:
  type: feedback   # user · feedback · project · reference
---

Rule, fact, or pointer.

**Why:** the reason this matters (often a past incident or preference).
**How to apply:** when and where this guidance kicks in.

Cross-link other memories with [[other-memory-slug]].
EOF

echo "▸ memory/ initialized at ${MEMDIR}"
echo "  - MEMORY.md  (curated index)"
echo "  - _template.md  (frontmatter template)"
