#!/usr/bin/env python3
"""
PTY supervisor for a long-running Claude Code process.

A generic PTY runner for any agent that needs a real terminal. Drop this in,
fill in your own COMMAND + channel flags, and supervise via launchd / systemd.

What it does:
  1. Allocates a real pseudo-terminal (Claude wants a real TTY in interactive
     mode; tmux works but adds a dependency, and tmux servers die).
  2. Spawns the child (Claude) inside the PTY.
  3. Forwards stdin/stdout through the PTY.
  4. Stamps a heartbeat file every time the child writes output (safety net
     so the watchdog has signal even if the agent forgets to stamp).
  5. Exits cleanly on SIGTERM so the supervisor can restart it.

What it doesn't do:
  - Restart the child on crash (let launchd / systemd do that).
  - Buffer or rate-limit (let the supervisor backoff).
  - Parse channel events (the MCP plugin does that).
"""

import os
import pty
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

# ─── Configure these ──────────────────────────────────────────────────────
COMMAND = [
    "claude",
    "--dangerously-skip-permissions",
    # "--channels", "plugin:YOUR_CHANNEL_PLUGIN",
    # add your own channel(s) here
]
HEARTBEAT_FILE = Path.home() / ".claude" / "agent-last-output.txt"
LOG_FILE = Path.home() / ".claude" / "agent-runner.log"
# ──────────────────────────────────────────────────────────────────────────


def log(msg: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a") as f:
        f.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {msg}\n")


def stamp_heartbeat() -> None:
    HEARTBEAT_FILE.parent.mkdir(parents=True, exist_ok=True)
    HEARTBEAT_FILE.write_text(str(int(time.time())))


def run() -> int:
    log(f"runner starting: {' '.join(COMMAND)}")

    pid, fd = pty.fork()

    if pid == 0:
        # child — exec the command with the PTY as stdin/stdout
        try:
            os.execvp(COMMAND[0], COMMAND)
        except FileNotFoundError:
            sys.stderr.write(f"command not found: {COMMAND[0]}\n")
            os._exit(127)

    # parent — relay I/O between our stdin/stdout and the PTY
    def handle_sigterm(_signum: int, _frame) -> None:
        log("SIGTERM received, forwarding to child")
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGTERM, handle_sigterm)

    last_stamp = 0.0

    while True:
        try:
            ready, _, _ = select.select([sys.stdin, fd], [], [], 1.0)
        except KeyboardInterrupt:
            log("keyboard interrupt")
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            break

        if sys.stdin in ready:
            try:
                data = os.read(sys.stdin.fileno(), 4096)
            except OSError:
                data = b""
            if data:
                os.write(fd, data)

        if fd in ready:
            try:
                data = os.read(fd, 4096)
            except OSError:
                # child exited; PTY closed
                data = b""
            if not data:
                break
            os.write(sys.stdout.fileno(), data)
            # safety-net heartbeat (max once per second)
            now = time.time()
            if now - last_stamp > 1.0:
                stamp_heartbeat()
                last_stamp = now

        # reap the child if it has exited
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                log(f"child exited with status {status}")
                return os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
        except ChildProcessError:
            break

    return 0


if __name__ == "__main__":
    sys.exit(run())
