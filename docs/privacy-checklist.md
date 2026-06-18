# Privacy Checklist

Use this checklist before committing to any public repository, publishing a
document, or deploying a public artifact from an agent fleet.

Run the automated scan first:

```bash
./scripts/privacy-scan.sh
```

Then work through this checklist manually for items the scanner can't catch.

---

## Automated scan (required before every public commit)

```bash
# From the repo root:
./scripts/privacy-scan.sh
```

The scan checks for:
- Operator names and personal identifiers
- Company or private organization names
- Chat IDs, Slack user IDs, phone numbers
- Token/secret/password patterns (non-placeholder)
- Credential file paths that identify live setups

**Zero findings required.** If the scan finds hits, fix them before committing.

---

## Manual checklist

### Names and identity
- [ ] No real operator first or last names
- [ ] No employee or team member names
- [ ] No client, customer, or partner names
- [ ] No agent names that are also real people's names (use generic: `coordinator`, `peer-agent`, `ExampleCo agent`)

### Organizations and projects
- [ ] No private company names
- [ ] No internal project names that identify a live deployment
- [ ] No private GitHub org or repo slugs
- [ ] No URLs pointing to private or auth-gated resources

### Contact surfaces
- [ ] No phone numbers
- [ ] No email addresses (unless `example@example.com` placeholder)
- [ ] No Slack user IDs (format: `U09XXXXXXX`)
- [ ] No Telegram chat IDs or user IDs
- [ ] No Discord server IDs or user snowflakes

### Credentials and tokens
- [ ] No API keys, bearer tokens, or secrets — only clearly fake placeholders
  (e.g., `EXAMPLE_TOKEN`, `your-api-key-here`, `sk-XXXX`)
- [ ] No OAuth client IDs or secrets
- [ ] No cookie values or session tokens
- [ ] No SSH keys or fingerprints
- [ ] No `.env` file contents

### Paths and infrastructure
- [ ] No absolute paths that identify a live user account (`/Users/real-name/...`)
  — use `{{HOME}}`, `~/`, or `/path/to/your/project/`
- [ ] No internal hostnames, IPs, or private DNS names
- [ ] No database connection strings with real hosts
- [ ] No Vercel project names, Supabase project refs, or similar that identify
  a live deployment (unless the document is specifically about that public deployment)

### Content and data
- [ ] No private conversation excerpts or message content
- [ ] No legal, medical, or financial details about real individuals
- [ ] No private project roadmap items that haven't been publicly announced
- [ ] No competitive intelligence gathered under NDA or private access

---

## What is OK to include

- Generic role names: `the operator`, `coordinator agent`, `ExampleCo`
- Clearly fake placeholders: `EXAMPLE_TOKEN`, `com.example.agent`, `your-bot-token-here`
- Generic path patterns: `~/.claude/`, `{{HOME}}/path/to/scripts/`
- Anonymized worked examples: `a content-ingestion pipeline`, `Project Atlas`
- Architecture patterns that don't name the live deployment

---

## Before deploying a public artifact

1. Run `scripts/privacy-scan.sh` from the repo root.
2. Work through this checklist.
3. If anything is unclear, err on the side of generalizing — replace with a
   placeholder and note in a comment what the real value would look like.
4. Review image files separately (the scanner doesn't read image text).
   Use image inspection tools or manual review for diagrams.

---

## After a privacy incident

If private data was accidentally committed to a public repo:

1. Immediately make the repository private (if possible).
2. Rotate any exposed credentials.
3. Use `git filter-repo` or BFG Repo Cleaner to purge the sensitive content
   from git history.
4. Force-push the clean history.
5. Re-make the repository public only after confirming the purge.
6. Document the incident and update this checklist to catch the category
   that slipped through.
