# Process Model — Long-Running Claude Agents

A Claude Code process is a CLI invocation. By default it lives as long as the
terminal that launched it. To get a long-running agent you need three layers:
a supervisor that survives terminal closure, a PTY allocator that satisfies
Claude's interactive mode, and a clean restart story.

## The tree

```
launchd (com.example.agent)              ← user-level LaunchAgent
  └─ python3 agent-pty-runner.py         ← PTY supervisor
       └─ claude --dangerously-skip-permissions \
                 --channels plugin:YOUR_CHANNEL_PLUGIN
            └─ bun                       ← MCP subprocess(es)
```

## Why each layer

**launchd** — macOS process supervisor. A LaunchAgent plist registers the job
under `gui/<uid>`, restarts it on crash, and survives login/logout. Use
user-level (`~/Library/LaunchAgents/`), not system-level — the process needs
user-keychain access and the same TCC permissions a desktop session has.

**PTY runner** — small Python script that allocates a real pseudo-terminal
and spawns Claude inside it as a child process. Claude wants a real TTY in
interactive mode. The earlier shape was `tmux`; that worked but had a hard
dependency on a tmux server staying alive, and the tmux server died sometimes
(host reboots, OOM kills). The PTY runner removes that dependency.

**Claude CLI** — the agent itself. `--channels` mounts an MCP channel
plugin; inbound messages from that channel arrive in the agent's context as
`<channel>` blocks.

**bun MCP subprocess** — runtime for local MCP plugins (e.g. a messaging
channel). It's a child of the Claude process, not the runner. If it dies, the
Claude process stays alive but the channel goes mute. Known failure mode.

## Sample launchd plist

See `examples/launchd-plist/com.example.agent.plist`. Important details:

- `RunAtLoad: true` and `KeepAlive: true` for a long-running agent.
- `StandardOutPath` and `StandardErrorPath` to actual log files — debugging
  a dead supervisor without logs is miserable.
- `EnvironmentVariables` for any secrets the agent or MCP subprocesses need.
  Don't rely on `~/.zshrc` — launchd doesn't source it.
- `ProgramArguments` should call `python3` (or your interpreter) with the
  absolute path to the runner, never relying on `$PATH`.

## Restart

```bash
launchctl kickstart -k gui/$(id -u)/com.example.agent
```

`-k` kills the running instance first. Without `-k`, kickstart no-ops if the
job is already running.

## Inspect

```bash
pgrep -fl agent-pty-runner.py
pgrep -P $(pgrep -f agent-pty-runner) | xargs -I{} ps -fp {}
```

## Known failure modes

| Symptom                                       | Cause                                                  | Fix                                           |
|----------------------------------------------|--------------------------------------------------------|-----------------------------------------------|
| Agent stops replying on channel               | bun MCP subprocess died silently                       | `launchctl kickstart -k` (tears down tree)    |
| Agent output appears in terminal, not channel | Channel binding lost; MCP plugin not in active list    | Restart; verify plugin in `--channels` flag   |
| Agent up but channel reports "no recent activity" | MCP subprocess can't reach channel API              | Check token in plist `EnvironmentVariables`   |
| launchd respawns infinitely (rapid loop)      | Child exiting too quickly; missing arg or auth        | Check `StandardErrorPath`; add `ThrottleInterval` |

## Conceptual port to Linux

- `launchd` → `systemd` user units (`~/.config/systemd/user/`).
- `gui/<uid>` → `--user` systemctl scope.
- PTY runner script is unchanged (Python `pty` module works on Linux).
- Watchdog is unchanged.

Everything else is the same.
