# mira-fleet-architecture

A public, sanitized architecture reference for long-lived AI agent systems
coordinated by Mira / OpenClaw. See README.md for full documentation.

## Working in this repo

This is a static documentation site. Content lives in:
- `README.md` — canonical markdown reference
- `public/index.html` — HTML site (deployed to Vercel)
- `docs/` — deep-dive documents per topic
- `scripts/` — transferable scripts (agent-pty-runner.py, agent-restart.sh, etc.)
- `examples/` — example memory files and launchd plists

## Privacy rules (hard stops)

This is a **public** repo. Never commit:
- Real operator names, emails, phone numbers, or chat IDs
- Real API tokens, secrets, bearer tokens, or credentials
- Private project names, customer or partner names
- Internal system URLs or access paths that identify a live deployment

Use `EXAMPLE_TOKEN`, `your-bot-token-here`, `{{HOME}}`, `ExampleCo`,
`Project Atlas`, etc. as placeholders.

Run `scripts/privacy-scan.sh` before any commit to catch obvious leaks.

## Surfaces

- **app** — the static site at public/index.html
- **docs** — markdown documentation under docs/
- **scripts** — transferable shell/Python scripts
