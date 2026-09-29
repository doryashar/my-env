---
name: homeassistant-control
description: Use when the user asks to control, check, automate, or diagnose anything in their Home Assistant - switches, lights, AC/climate, soundbar/music, locks, cameras, curtains, automations, or dashboards. Also use when HA API auth errors (401), unknown entities, or "is X on/off?" questions about the user's home appear.
---

# Home Assistant Control (yashar's home)

## Connect + Authenticate (never ask the user for a token)

Endpoints, in order:
1. `http://10.147.17.17:8123` (ZeroTier, private — preferred)
2. `https://rpi.yashar.us` (public, nginx-proxied)
3. `http://192.168.1.237:8123` (LAN)

**Primary credential** — long-lived token at `~/.config/hermes-ha-token` (verified working):

```bash
AT=$(cat ~/.config/hermes-ha-token)
```

**Fallback** (if that 401s) — refresh token at `~/.config/ha_refresh_token`:

```bash
AT=$(curl -s -X POST http://10.147.17.17:8123/auth/token \
  -d "grant_type=refresh_token&client_id=http://localhost:8123/" \
  --data-urlencode "refresh_token=$(cat ~/.config/ha_refresh_token)" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
```

If both are missing, SSH to `yashar@10.147.17.17` and read a refresh token from `/config/.storage/auth` (first refresh_tokens entry with client_id `http://localhost:8123/`), saving it to `~/.config/ha_refresh_token`.

```bash
# Core API calls
curl -H "Authorization: Bearer $AT" http://10.147.17.17:8123/api/states          # all entities
curl -H "Authorization: Bearer $AT" http://10.147.17.17:8123/api/states/<id>     # one entity
curl -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
  -d '{"entity_id":"switch.foo"}' http://10.147.17.17:8123/api/services/switch/turn_on
```

## Entity map

| What | Entity |
|---|---|
| AC מזגן (Midea, local) | `climate.midea_ac_151732607558239` |
| Soundbar (Chromecast) | `media_player.q_series_soundbar` |
| מראה איקאה / תאורת שירותים | `switch.mrh_yqh_switch_1` / `switch.tvrt_shyrvtym_switch_1` |
| טלוויזיה ושידה 1-4 | `switch.tvrt_tlvyzyh_vshydh_switch_1_2..4_2` |
| חימום מקלחון | `switch.khymvm_mqlkhvn_switch_1` |
| וילון | `cover.curtain_switch_curtain_2` |
| Lights by room | `light.unknown_light*` (מטבח 1-4, סלון תחתון 5-8), `light.tz3000_1nenkvye*` (סלון ראשי), `light.tz3000_ltgngnqz*` (מסדרון) |
| TV | `media_player.lg_webos_tv_oled77c36lc` |

Pattern: `GET /api/states` and grep friendly_name (Hebrew names) to discover anything else.

## Verified quirks (do not relearn these)

- `climate.turn_on` rejects `hvac_mode` (HTTP 400) → use `climate/set_hvac_mode`.
- Volume is 0.0-1.0: "volume 10" = `volume_level: 0.10`.
- **Music on YouTube is blocked** from this network (yt-dlp 403, all clients, even with cookies). Working route: search archive.org (`advancedsearch.php?q=title:(SONG) AND creator:(ARTIST)&output=json` → metadata → get .mp3 URL) → `media_player/play_media` with `media_content_type: audio/mpeg`. Verified with Air & Drake.
- The soundbar accepts ONE TCP connection; avoid other cast clients while HA is connected.
- `switch.mrh_yqh_switch_1` ↔ `light.unknown_light_7` and `switch.tvrt_shyrvtym_switch_1` ↔ `light.unknown_light_8` are two-way synced by automations — toggling one flips the other.
- Template states are strings: coerce with `| int(0)` / `| float(0)` and provide defaults before comparing.

## Writing automations (modern syntax, verified workflow)

```yaml
- id: "unique-stable-id"            # required — traces and reloads need it
  alias: Human name
  triggers:                         # plural keys, 'action:' not 'service:' (2024.10+)
  - trigger: state
    entity_id: switch.foo
    to: "on"
  conditions: []
  actions:
  - action: light.turn_on
    target:
      entity_id: light.bar
  mode: single
```

- Prefer **native triggers/conditions** (`numeric_state`, `state`, `time`) over template checks — they validate at load time. Templates only for state *comparisons* (like the sync guards).
- **Adding one**: append to `/home/yashar/homeassistant/automations.yaml` (SSH), then `POST /api/services/automation/reload` — no restart. Verify with `GET /api/states/automation.<slug>`.
- **Testing one**: `POST /api/services/automation/trigger` with `{"entity_id":"automation.x"}` — ⚠️ bypasses `conditions` by default (proves actions only). Pass `skip_condition: false` to test the full path.
- Prefer `target: entity_id:` over `device_id` (survives device re-pairing).

## Change discipline

| Change | Apply via |
|---|---|
| automations, scripts, scenes | domain reload service (instant) |
| configuration.yaml, integrations, dashboards registry | `ssh yashar@10.147.17.17 "sudo docker restart homeassistant"` (~2 min on this Pi) |

- **Verify, don't assume**: after any change → check entity state, then `GET /api/error_log` (or SSH `/home/yashar/homeassistant/home-assistant.log`) filtered to the change.
- **Before risky changes**: backup first — `POST /api/services/hassio/backup` won't work (docker install); use `ssh yashar@10.147.17.17 "sudo docker exec homeassistant python -m tarfile ..."` or at minimum `cp` the file being edited with a `.bak` suffix (existing pattern: `.storage/*.bak-*`).
- HA on this Pi boots SLOW (~2-3 min until entities settle) — wait before declaring failure.

## When SSH is required (`ssh yashar@10.147.17.17`)

For: HA restarts (`sudo docker restart homeassistant`), integration code patches, pip, `.storage` edits, reading logs (`/home/yashar/homeassistant/home-assistant.log`). Everything else works via the API.

## Regression tests (run after any HA change)

- `/home/yashar/tests/test_smartlife_integration.sh` (15)
- `/home/yashar/tests/test_button_sync_automations.sh` (8)
- `/home/yashar/tests/test_midea_ac.sh` (6)

Docs: `/home/yashar/docs/smartlife-integration.md`, `/home/yashar/docs/midea-ac.md`
