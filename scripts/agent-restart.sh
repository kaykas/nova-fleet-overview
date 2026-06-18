#!/usr/bin/env bash
# Restart a launchd-supervised agent and confirm the process tree is healthy.
#
# Usage:  ./agent-restart.sh <launchd-label>
# Example:./agent-restart.sh com.example.agent

set -euo pipefail

LABEL="${1:?label required, e.g. com.example.agent}"
UID_NUM="$(id -u)"

echo "▸ kickstarting ${LABEL}…"
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}"

echo "▸ waiting for runner process to appear…"
for i in $(seq 1 10); do
  if pgrep -fl "agent-pty-runner" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "▸ live process tree:"
RUNNER_PID="$(pgrep -f 'agent-pty-runner' | head -1 || true)"
if [ -z "${RUNNER_PID}" ]; then
  echo "  (no runner found — check launchd logs)"
  echo "  log -t com.apple.launchd --predicate 'process == \"launchd\" && eventMessage CONTAINS \"${LABEL}\"' --last 5m"
  exit 1
fi

echo "  runner pid: ${RUNNER_PID}"
echo "  children:"
pgrep -P "${RUNNER_PID}" | while read -r child; do
  ps -fp "${child}" | tail -1 | sed 's/^/    /'
done

echo "▸ ok."
