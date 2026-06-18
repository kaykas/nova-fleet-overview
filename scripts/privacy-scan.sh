#!/usr/bin/env bash
# Privacy scanner for public repos.
#
# Scans text files for patterns that must not appear in a public repository:
# operator names, company names, chat IDs, non-placeholder tokens, etc.
#
# Usage: ./scripts/privacy-scan.sh [--dir <directory>]
#
# Returns exit code 1 if any forbidden patterns are found.

set -euo pipefail

SCAN_DIR="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# ─── Forbidden patterns ──────────────────────────────────────────────────
# Add operator-specific names/identifiers here.
# Format: "PATTERN|description"
PATTERNS=(
  # Operator personal names — replace with your own list
  # "RealFirstName|operator first name"
  # "RealLastName|operator last name"

  # Slack user IDs
  "U[0-9A-Z]{10}|Slack user ID"

  # Phone numbers (US format)
  "[0-9]{10}|10-digit phone number"
  "\+1[0-9]{10}|US phone number with country code"

  # Token/secret patterns (not placeholder)
  "sk-[a-zA-Z0-9]{20,}|OpenAI-style API key"
  "ghp_[a-zA-Z0-9]{36}|GitHub personal access token"
  "xoxb-[a-zA-Z0-9-]{40,}|Slack bot token"
  "Bearer [a-zA-Z0-9._-]{20,}|Bearer token value"

  # Telegram bot token format
  "[0-9]{8,}:AA[a-zA-Z0-9_-]{33}|Telegram bot token"
)

# ─── File extensions to scan ─────────────────────────────────────────────
EXTENSIONS=("*.md" "*.html" "*.htm" "*.txt" "*.py" "*.sh" "*.js" "*.ts" "*.json" "*.yaml" "*.yml" "*.plist" "*.toml" "*.env.example")

# ─── Directories to skip ─────────────────────────────────────────────────
SKIP_DIRS=(".git" ".vercel" "node_modules" ".next" "dist" "build")

FOUND=0

echo "▸ Privacy scan: ${SCAN_DIR}"
echo ""

# Build find exclusion args
FIND_PRUNE=""
for dir in "${SKIP_DIRS[@]}"; do
  FIND_PRUNE="${FIND_PRUNE} -path '*/${dir}' -prune -o"
done

for pattern_entry in "${PATTERNS[@]}"; do
  PATTERN="${pattern_entry%%|*}"
  DESC="${pattern_entry##*|}"

  # Build include args for find
  INCLUDE_ARGS=()
  for ext in "${EXTENSIONS[@]}"; do
    INCLUDE_ARGS+=(-name "${ext}" -o)
  done
  # Remove trailing -o
  unset 'INCLUDE_ARGS[${#INCLUDE_ARGS[@]}-1]'

  HITS=$(find "${SCAN_DIR}" \
    -path '*/.git' -prune -o \
    -path '*/.vercel' -prune -o \
    -path '*/node_modules' -prune -o \
    -type f \( "${INCLUDE_ARGS[@]}" \) \
    -print0 2>/dev/null \
    | xargs -0 grep -l -E "${PATTERN}" 2>/dev/null || true)

  if [ -n "${HITS}" ]; then
    echo "❌ FOUND: ${DESC} (pattern: ${PATTERN})"
    while IFS= read -r file; do
      REL="${file#${SCAN_DIR}/}"
      grep -n -E "${PATTERN}" "${file}" | head -5 | while IFS= read -r line; do
        echo "   ${REL}:${line}"
      done
    done <<< "${HITS}"
    echo ""
    FOUND=$((FOUND + 1))
  fi
done

# Also scan for placeholder-looking values that appear to have real data
# (e.g., EXAMPLE_TOKEN used as a key name but actual value filled in)
REAL_TOKEN_HITS=$(find "${SCAN_DIR}" \
  -path '*/.git' -prune -o \
  -path '*/.vercel' -prune -o \
  -path '*/node_modules' -prune -o \
  -type f -name "*.env" \
  -print0 2>/dev/null \
  | xargs -0 grep -l "" 2>/dev/null || true)

if [ -n "${REAL_TOKEN_HITS}" ]; then
  echo "⚠️  WARNING: .env file(s) found (should not be committed):"
  while IFS= read -r file; do
    REL="${file#${SCAN_DIR}/}"
    echo "   ${REL}"
  done <<< "${REAL_TOKEN_HITS}"
  echo ""
  FOUND=$((FOUND + 1))
fi

if [ "${FOUND}" -eq 0 ]; then
  echo "✅ No forbidden patterns found."
  exit 0
else
  echo "❌ ${FOUND} issue(s) found. Fix before committing to a public repository."
  exit 1
fi
