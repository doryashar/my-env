#!/usr/bin/env bash
set -euo pipefail

HASS_CONTAINER="homeassistant"
HASS_AUTH="/config/.storage/auth"
TTS_ENTITY="tts.google_en_com"
PLAYER_ENTITY="media_player.q_series_soundbar"
TOKEN_CLIENT="soundbar-tts"

message="${1:-}"
if [[ -z "$message" ]]; then
    echo "Usage: $0 <message> [language]"
    echo "  language defaults to 'iw' (Hebrew)"
    exit 1
fi

language="${2:-iw}"

get_token_jwt() {
    docker exec "$HASS_CONTAINER" python3 -c "
import json, jwt, time
with open('$HASS_AUTH') as f:
    data = json.load(f)
for rt in data['data']['refresh_tokens']:
    if rt.get('client_name') == '$TOKEN_CLIENT':
        payload = {'iss': rt['id'], 'iat': int(time.time()), 'exp': int(time.time()) + 3600}
        print(jwt.encode(payload, rt['jwt_key'], algorithm='HS256'))
        break
"
}

speak() {
    local token="$1"
    local msg="$2"
    local lang="$3"
    local tts_entity="$4"
    local player_entity="$5"

    python3 - "$token" "$msg" "$lang" "$tts_entity" "$player_entity" << 'PYEOF'
import asyncio, websockets, json, sys

async def main():
    token, message, language, tts_entity, player_entity = sys.argv[1:6]
    url = "ws://localhost:8123/api/websocket"
    async with websockets.connect(url) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": token}))
        resp = json.loads(await ws.recv())
        if resp.get("type") != "auth_ok":
            print("Authentication failed", file=sys.stderr)
            sys.exit(1)

        await ws.send(json.dumps({
            "id": 1, "type": "call_service",
            "domain": "media_player", "service": "turn_on",
            "target": {"entity_id": [player_entity]}
        }))

        await ws.send(json.dumps({
            "id": 2, "type": "call_service",
            "domain": "media_player", "service": "volume_set",
            "target": {"entity_id": [player_entity]},
            "service_data": {"volume_level": 1.0}
        }))

        await asyncio.sleep(2)

        await ws.send(json.dumps({
            "id": 3, "type": "call_service",
            "domain": "tts", "service": "speak",
            "target": {"entity_id": [tts_entity]},
            "service_data": {
                "message": message,
                "media_player_entity_id": player_entity,
                "language": language,
                "cache": False
            }
        }))

        done = 0
        while done < 3:
            resp = json.loads(await ws.recv())
            if resp.get("type") == "result" and resp.get("id") in (1, 2, 3):
                if not resp.get("success"):
                    print(f"Error: {resp.get('error')}", file=sys.stderr)
                    sys.exit(1)
                done += 1

asyncio.run(main())
PYEOF
}

access_token=$(get_token_jwt)
if [[ -z "$access_token" ]]; then
    echo "Error: could not get access token. Is HA running?" >&2
    exit 1
fi

speak "$access_token" "$message" "$language" "$TTS_ENTITY" "$PLAYER_ENTITY"
echo "Done."
