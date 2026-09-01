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
| Listen in background | `whatsapp-send.sh --listen >> /tmp/opencode/wa-listen.log 2>&1 &` |
| Diagnose instances | `whatsapp-send.sh --list` |

Default recipient: the user's phone (in `whatsapp.env`). Sends **from** instance `system_ailaw` ("Peleg"). Exit codes: 0 ok/received, 1 API error, 2 config error, 3 wait timed out.

## Receiving messages (--wait / --listen)

- `--wait` blocks until the user sends any WhatsApp message, prints one `[wa] <ts> from <jid> (<name>): <text>` line, exits 0. Timeout → exit 3. Optional positional arg = greeting sent before waiting.
- `--listen` runs a foreground poll loop printing every new incoming message. Run it **in background** (pattern above), then read the log file to propagate messages into the chat. Stop with `kill $(cat ~/.cache/whatsapp-notify/listen.pid)` (do NOT pkill by pattern — it self-matches your own shell).
- **Do NOT run `--wait` and `--listen` at the same time** (they would race on the shared state in `~/.cache/whatsapp-notify/`).
- **Incoming user messages arrive under an `@lid` JID** (e.g. `127818293858341@lid`), NOT `972548826569@s.whatsapp.net` — never filter by phone JID; the script accepts every non-fromMe message.
- Read the user's reply from the `--wait` output / listen log and act on it.

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
