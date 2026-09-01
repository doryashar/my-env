---
name: whatsapp-notify
description: Use when the user asks to be contacted, notified, pinged, or messaged via WhatsApp specifically, or asks to send a file/photo to their phone when Telegram is not the requested channel. Also covers WhatsApp send failures like 401, empty instance list, or "no connected instance".
---

# WhatsApp Notify

## Overview

**Core principle: send the user a WhatsApp message via the Evolution API — one script call, no discovery needed.**

**Script:** `~/.config/opencode/skills/whatsapp-notify/scripts/whatsapp-send.sh`
**Config:** `~/.config/opencode/skills/whatsapp-notify/whatsapp.env` (API key contains `$` — never `source` it; the script parses it safely)

## When to Use

- User says "whatsapp me", "send it to my whatsapp", asks for WhatsApp specifically
- Long task finished / error needs attention AND the user asked for WhatsApp (otherwise prefer the `telegram-notify` skill)
- NOT for: trivial ops, or when the user is actively watching the session

## Quick Reference

| Intent | Command |
|---|---|
| Send text | `whatsapp-send.sh "✅ Build passed (12 tests)"` |
| Send to other number | `whatsapp-send.sh --to 972XXXXXXXXX "text"` (digits only) |
| Send file | `whatsapp-send.sh --file /path/report.pdf "caption"` |
| Send photo | `whatsapp-send.sh --photo /path/img.png "caption"` |
| Wait for reply (blocking) | `whatsapp-send.sh --wait ["greeting"] [--timeout 300]` |
| Listen (capture) | `whatsapp-send.sh --listen >> /tmp/opencode/wa-listen.log 2>&1 &` |
| **Wake-on-WhatsApp daemon** | `whatsapp-watch.sh &` (injects incoming messages into the opencode session) |
| Surface new messages manually | `whatsapp-send.sh --follow --idle 180` (blocks, exits 0 with the new `[wa]` line, 3 on idle) |
| Diagnose instances | `whatsapp-send.sh --list` |
| Find current session id | python sqlite3 RO on `~/.local/share/opencode/opencode.db`: `select id from session where directory='<cwd>' order by time_updated desc limit 1` |

## Wake-on-WhatsApp (whatsapp-watch.sh) — the autonomous reply daemon

**The full stack, when armed:** `--listen` (captures to `/tmp/opencode/wa-listen.log`) → `whatsapp-watch.sh` daemon (blocks on `--follow`) → `opencode run --session <id> "[whatsapp-notify] ... <the [wa] line>"` → the message arrives as a **user turn in the live session** and the agent replies via `whatsapp-send.sh` without anyone touching the CLI.

- Start: `nohup ~/.config/opencode/skills/whatsapp-notify/scripts/whatsapp-watch.sh >> /tmp/opencode/wa-watch-daemon.log 2>&1 &`
- Stop: `kill $(cat ~/.cache/whatsapp-notify/watch.pid)` (listener separately: `listen.pid`)
- The target session id is `WA_OPENCODE_SESSION` in `whatsapp.env` — update it when the session changes (see "Find current session id" above).
- Loops are impossible: agent replies are `fromMe` → filtered by the listener; the injected preamble tells the agent not to echo it.
- If the daemon dies or the session id is stale, fall back to manual `--follow` discipline (below) and restart it with the current session id.

Default recipient: the user's phone (in `whatsapp.env`). Sends **from** instance `system_ailaw` ("Peleg"). Exit codes: 0 ok/received, 1 API error, 2 config error, 3 wait timed out.

## Receiving messages (--wait / --listen / watch daemon)

**Architecture:** `--listen` captures incoming messages to a log; `whatsapp-watch.sh` (daemon) turns new log lines into injected turns in a live opencode session via `opencode run --session <id>` — the agent wakes and responds WITHOUT being poked in the CLI. `--wait`/`--follow` are manual fallbacks.

- **Full auto (preferred):** `nohup whatsapp-send.sh --listen >> /tmp/opencode/wa-listen.log 2>&1 &` then `nohup whatsapp-watch.sh >> /tmp/opencode/wa-watch-daemon.log 2>&1 &`. Requires `WA_OPENCODE_SESSION=<session-id>` in `whatsapp.env`. Find the session id (newest for this project's directory):
  `.venv/bin/python -c "import sqlite3;db=sqlite3.connect('file:/home/yashar/.local/share/opencode/opencode.db?mode=ro',uri=True);print(*db.execute(\"select id from session where directory='/home/yashar/projects/financial_status' order by time_updated desc limit 1\"))"`
  (ro sqlite3 works from any venv; or `sqlite3` if installed). The session id changes per conversation — update `whatsapp.env` at session start. Stop: `kill $(cat ~/.cache/whatsapp-notify/{listen,watch}.pid)`.
- The injected turn arrives as a user message containing the `[wa]` line(s) — treat it as the user talking on WhatsApp; reply via `whatsapp-send.sh`. Do not re-inject or echo the preamble.
- `--wait ["greeting"] [--timeout N]` blocks until any message arrives (exit 0/3). Don't run alongside `--listen` (shared state race).
- `--follow --idle N` blocks until the listen log gains a real `[wa]` line (exit 0 with lines / 3 on idle). Only needed if the watch daemon isn't running.
- **Incoming user messages arrive under an `@lid` JID** (e.g. `127818293858341@lid`), NOT `972548826569@s.whatsapp.net` — never filter by phone JID; the script accepts every non-fromMe message.
- Read the user's reply from the `--wait` output / listen log and act on it.
- **NEVER modify the listen log in place** (`sed -i`/`mv`/`rm`) while `--listen` runs — orphans its stdout to a deleted inode, lines vanish silently (verified failure). The listener reopens per write so rotation is safe; to reset: stop it first. Stop listeners/daemons by **pidfile**, never `pkill -f` by pattern (self-matches your own shell — verified failure).
- **After ANY listen-log reset/truncation, restart BOTH the listener and the watch daemon** — the follow child's byte offset goes stale (old offset > new file size → new lines never fire). Verified failure.

## Validation (independent health checking)

`whatsapp-health.sh [--probe] [--alert]` validates each stage SEPARATELY; exit 1 on any failure:
- S1 Evolution API + instance `open` — catches API/auth death
- S2 listener pid alive + loop cycling (state.json mtime < 30s) — catches dead/stuck loops; orphaned stdout = warn (emit() bypasses it)
- S3 watch daemon + its `--follow` child — catches "alive but can't wake"
- S4 inbound freshness (age of newest non-fromMe message in store) — catches the **silent linked-device desync** (instance says `open` but nothing arrives; fix: `POST /instance/restart/{name}` — NEVER `/instance/logout` — then have the user send a test message)
- `--probe` = full local chain self-test: appends a `[healthprobe]` line, expects the daemon to inject it within 8s (arrives as an ignorable session turn)
- `--alert` = on failure: WhatsApp message + Telegram fallback (independent stack), deduped hourly, auto-resolves. Installed: cron `*/10 * * * * ... whatsapp-health.sh --alert >> /tmp/opencode/wa-health-cron.log`

Full validation = health green + `--probe` green + **a real message from the user's phone** end-to-end. Anything less has already been proven to lie (the 01:07 "Test" worked, the next one didn't).

## Troubleshooting (verified dead ends — do not rediscover)

| Symptom | Cause / Fix |
|---|---|
| 401 Unauthorized | Key rotated. Re-read live key: `ssh ubuntu@10.147.17.136 docker exec ailaw-staging-backend-1 sh -c 'env \| grep EVOLUTION_API_KEY'` and update `whatsapp.env` |
| Local Evolution `localhost:8082` (`ailaw-evolution-1`) returns `[]` | That deployment has **no paired instances — it is a dead end**. The live API is `https://evolution-whatsapp.cap.yashar.us` (dokploy on staging host) |
| `firm_ailaw` instance | Stuck at `connecting`, unpaired — only `system_ailaw` sends |
| `fetchInstances` parse prints `None` | Field is `name`/`connectionStatus`, not `instanceName` |
| `status: "PENDING"` in response | Normal on accept; message delivered asynchronously. Success = `.key.id` present |
| 400 "Owned media must be a url or base64" | `media` must be PLAIN base64 (no `data:` URI prefix) or a URL — the script handles this; means the payload was mangled |
| Number rejected | Strip `+` — Evolution wants digits only (`972548826569`) |
| User says they replied but nothing arrives | Instance stores only messages received while connected (`syncFullHistory: false`); check `--list` shows `system_ailaw` `open`, then re-run `--wait`. Their reply may show up minutes later under an `@lid` JID |
| Listener alive but lines never appear in the log | Its stdout was orphaned — someone `sed -i`/`mv`/`rm`-ed the live log (check `ls -l /proc/<pid>/fd/1` for "(deleted)"). The listener re-opens per write now, but DON'T mutate the live log; rotate only after stopping it. Stop listeners by pidfile, never `pkill -f` (self-match kills your own shell) |
| Injection arrives but in the wrong session / nothing happens | Stale `WA_OPENCODE_SESSION` in `whatsapp.env` — re-read the current session id from `opencode.db` and restart the daemon |
