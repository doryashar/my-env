#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2RTC_BIN="/tmp/go2rtc"
GO2RTC_CONFIG="/tmp/go2rtc_showcam.yaml"
CAM_USER="${CAM_USER:-${CAMERA_USER:-admin}}"
CAM_PASS="${CAM_PASS:-${CAMERA_PASS:-}}"
CAM_HOST="${CAM_HOST:-${CAMERA_HOST:-192.168.1.140}}"
CAM_PORT="${CAM_PORT:-8899}"
GO2RTC_PORT=19084
GO2RTC_RTSP_PORT=18584
WEB_PORT=9090
PIPE="/tmp/showcam_pipe"
PLAYER="${1:-mpv}"
GO2RTC_PID=""
FFMPEG_PID=""
WEB_PID=""

stop_all() {
    echo "Stopping camera view..."
    # Kill child components by specific patterns (these never match the
    # `show_cam.sh stop` process). The orchestrator exits naturally once its
    # waited child dies, firing its EXIT cleanup trap.
    pkill -f '/tmp/go2rtc' 2>/dev/null || true
    pkill -f 'cam_web.py' 2>/dev/null || true
    pkill -f 'localhost:19084/api/stream' 2>/dev/null || true
    pkill -f 'showcam_pipe' 2>/dev/null || true
    rm -f "$PIPE" 2>/dev/null || true
    sleep 0.3
    if pgrep -f '/tmp/go2rtc|cam_web.py' >/dev/null 2>&1; then
        echo "Warning: some processes may still be running." >&2
        return 1
    fi
    echo "Camera view stopped."
    return 0
}

if [[ "$PLAYER" == "stop" ]]; then
    stop_all
    exit $?
fi

probe_host() {
    local host="$1"
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$host/554" 2>/dev/null && return 0
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$host/$CAM_PORT" 2>/dev/null && return 0
    return 1
}

resolve_cam_host() {
    if probe_host "$CAM_HOST"; then
        return 0
    fi
    echo "Camera not reachable at $CAM_HOST; searching local network..." >&2
    local found
    found=$(python3 "$SCRIPT_DIR/cam_discover.py" --port "$CAM_PORT" 2>/dev/null)
    if [[ -n "$found" ]]; then
        echo "Using discovered camera IP: $found" >&2
        CAM_HOST="$found"
        return 0
    fi
    echo "Could not locate the camera on the local network." >&2
    return 1
}

if [[ ! -x "$GO2RTC_BIN" ]]; then
    echo "Downloading go2rtc..."
    curl -L \
        "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" \
        -o "$GO2RTC_BIN"
    chmod +x "$GO2RTC_BIN"
fi

resolve_cam_host || exit 1

cat > "$GO2RTC_CONFIG" <<EOF
streams:
  camera:
    - rtsp://${CAM_USER}:${CAM_PASS}@${CAM_HOST}:554/streamtype=0#transport=tcp
api:
  listen: ":$GO2RTC_PORT"
rtsp:
  listen: ":$GO2RTC_RTSP_PORT"
webrtc:
  listen: ":8443"
EOF

cleanup() {
    if [[ -n "$WEB_PID" ]]; then
        kill "$WEB_PID" 2>/dev/null || true
        wait "$WEB_PID" 2>/dev/null || true
    fi
    if [[ -n "$FFMPEG_PID" ]]; then
        kill "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
    if [[ -n "$GO2RTC_PID" ]]; then
        kill "$GO2RTC_PID" 2>/dev/null || true
        wait "$GO2RTC_PID" 2>/dev/null || true
    fi
    rm -f "$PIPE"
}
trap cleanup EXIT

wait_for_http() {
    local url="$1" name="$2" pid="$3"
    local max=30 i
    for ((i=1; i<=max; i++)); do
        if curl -sf -o /dev/null "$url" 2>/dev/null; then
            return 0
        fi
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            echo "$name process died during startup" >&2
            exit 1
        fi
        sleep 0.5
    done
    echo "$name did not become ready at $url within 15s" >&2
    exit 1
}

echo "Starting go2rtc..."
"$GO2RTC_BIN" -c "$GO2RTC_CONFIG" &
GO2RTC_PID=$!

wait_for_http "http://localhost:$GO2RTC_PORT/" "go2rtc" "$GO2RTC_PID"
echo "go2rtc ready (API :$GO2RTC_PORT, RTSP :$GO2RTC_RTSP_PORT)"

play_with_mpv() {
    echo "Opening camera stream in mpv..."
    mpv --profile=low-latency --no-cache --untimed \
        "http://localhost:$GO2RTC_PORT/api/stream.m3u8?src=camera"
}

play_with_vlc() {
    rm -f "$PIPE"
    mkfifo "$PIPE"

    vlc --network-caching=300 --demux=ts "$PIPE" &>/dev/null &
    local vlc_pid=$!
    sleep 2

    echo "Starting ffmpeg transcoder (go2rtc RTSP -> MPEG2 pipe)..."
    /usr/bin/ffmpeg -rtsp_transport tcp \
        -i "rtsp://localhost:$GO2RTC_RTSP_PORT/camera" \
        -map 0:0 -an -c:v mpeg2video -q:v 5 \
        -f mpegts -y "$PIPE" &>/dev/null &
    FFMPEG_PID=$!

    echo "Opening VLC... (close VLC window to stop)"
    wait $vlc_pid 2>/dev/null || true
}

play_with_web() {
    local web_script="$SCRIPT_DIR/cam_web.py"
    if [[ ! -f "$web_script" ]]; then
        echo "Error: cam_web.py not found in $SCRIPT_DIR"
        exit 1
    fi
    echo "Starting camera web UI..."
    python3 "$web_script" --port "$WEB_PORT" --open &
    WEB_PID=$!
    wait_for_http "http://localhost:$WEB_PORT/" "cam_web" "$WEB_PID"
    echo "Web UI ready at http://localhost:$WEB_PORT (Ctrl+C to stop)"
    wait $WEB_PID 2>/dev/null || true
}

case "$PLAYER" in
    vlc) play_with_vlc ;;
    mpv) play_with_mpv ;;
    web) play_with_web ;;
    *)
        echo "Usage: $0 [mpv|vlc|web|stop]"
        exit 1
        ;;
esac
