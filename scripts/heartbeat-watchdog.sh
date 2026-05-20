#!/usr/bin/env bash
# Heartbeat watchdog. Run as a cron every 5 minutes.
#
# Alerts when:
#   1. heartbeat file is older than ALERT_AFTER_SECONDS, AND
#   2. there's been recent inbound activity (channel inbox modified
#      since last heartbeat) — to avoid alerting on a healthy idle agent.
#
# Restart is NOT automatic. Auto-restart masks root cause. The watchdog
# tells the operator; the operator restarts.

set -euo pipefail

# ─── Configure ──────────────────────────────────────────────────────────
HEARTBEAT_FILE="${HOME}/.claude/agent-last-output.txt"
INBOX_DIR="${HOME}/.claude/channels/telegram/inbox"
ALERT_AFTER_SECONDS=900       # 15 minutes
ALERT_COOLDOWN_SECONDS=3600   # don't re-alert for 1 hour
COOLDOWN_FILE="${HOME}/.claude/agent-watchdog-cooldown.txt"
ALERT_CMD="${ALERT_CMD:-osascript -e 'display notification \"Agent heartbeat stale\" with title \"Watchdog\"'}"
# ────────────────────────────────────────────────────────────────────────

now="$(date +%s)"

if [ ! -f "${HEARTBEAT_FILE}" ]; then
  echo "$(date) — no heartbeat file at ${HEARTBEAT_FILE} (agent never started?)"
  exit 0
fi

last="$(cat "${HEARTBEAT_FILE}")"
age=$(( now - last ))

if [ "${age}" -lt "${ALERT_AFTER_SECONDS}" ]; then
  echo "$(date) — heartbeat ok (${age}s)"
  exit 0
fi

# Heartbeat is stale. Is there recent inbound to justify alerting?
if [ -d "${INBOX_DIR}" ]; then
  recent_inbound="$(find "${INBOX_DIR}" -type f -newer "${HEARTBEAT_FILE}" 2>/dev/null | head -1)"
  if [ -z "${recent_inbound}" ]; then
    echo "$(date) — heartbeat stale (${age}s) but no recent inbound; not alerting"
    exit 0
  fi
fi

# Cooldown
if [ -f "${COOLDOWN_FILE}" ]; then
  last_alert="$(cat "${COOLDOWN_FILE}")"
  if [ $(( now - last_alert )) -lt "${ALERT_COOLDOWN_SECONDS}" ]; then
    echo "$(date) — heartbeat stale but inside cooldown; not alerting"
    exit 0
  fi
fi

echo "$(date) — ALERT: heartbeat stale ${age}s with recent inbound"
echo "${now}" > "${COOLDOWN_FILE}"
eval "${ALERT_CMD}"
