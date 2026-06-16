---
name: telegram-notify
description: Use when the user asks to be notified, pinged, or messaged via Telegram, or when a long-running task completes, or when an error needs the user's attention. Also use when sending files, photos, audio, or video to the user via Telegram.
---

# Telegram Notify

## Overview

**Core principle: send the user a Telegram message at the right moment.**

Sends messages and files to the user via Telegram Bot API. Relies on `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` environment variables.

**Script:** `~/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh`

## When to Use

- **Explicit request:** "ping me", "notify me", "send me a message", "telegram me", "send me a [photo/file/audio]"
- **Long task completion:** build, test suite, deployment, or any task taking meaningful time
- **Errors needing the user's attention:** build failures, test failures, deployment errors, critical bugs found

### When NOT to Use

- Trivial operations (under a few seconds)
- Intermediate steps in an ongoing task
- When the user is actively watching the output

## Usage

### Quick Reference

| Intent | Command |
|---|---|
| Send text | `telegram-send.sh "message"` |
| Send file/document | `telegram-send.sh --file /path/to/doc.pdf` |
| Send photo | `telegram-send.sh --photo /path/to/img.png` |
| Send audio | `telegram-send.sh --audio /path/to/song.mp3` |
| Send video | `telegram-send.sh --video /path/to/clip.mp4` |
| Silent (default) | `telegram-send.sh --silent "message"` |
| Loud notification | `telegram-send.sh --loud "message"` |

### Message Formatting

| Type | Prefix | Example |
|---|---|---|
| Success | `✅ ` | `✅ Build passed (12 tests, 18s)` |
| Error | `❌ ` | `❌ Deploy failed: timeout at step 3` |
| File sent | `📎 ` | `📎 Report generated: `/path/report.pdf`` |
| Long task started | `⏳ ` | `⏳ Starting training run (est. 15 min)` |

Keep messages concise and informative. Include:
- **What** happened (not just "done")
- **Context** (path, command, error summary)
- **Actions needed** if applicable (e.g., "Check logs at /var/log/app.log")
