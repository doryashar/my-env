#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2RTC_BIN="/tmp/go2rtc"
GO2RTC_CONFIG="/tmp/go2rtc_showcam.yaml"
CAMERA_RTSP="rtsp://admin:1111@192.168.1.140:554/streamtype=0"
GO2RTC_PORT=19084
GO2RTC_RTSP_PORT=18584
PIPE="/tmp/showcam_pipe"
PLAYER="${1:-mpv}"
GO2RTC_PID=""
FFMPEG_PID=""
WEB_PID=""

if [[ ! -x "$GO2RTC_BIN" ]]; then
    echo "Downloading go2rtc..."
    curl -L \
        "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" \
        -o "$GO2RTC_BIN"
    chmod +x "$GO2RTC_BIN"
fi

cat > "$GO2RTC_CONFIG" <<EOF
streams:
  camera:
    - rtsp://admin:1111@192.168.1.140:554/streamtype=0#transport=tcp
api:
  listen: ":$GO2RTC_PORT"
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

echo "Starting go2rtc..."
"$GO2RTC_BIN" -c "$GO2RTC_CONFIG" &
GO2RTC_PID=$!

sleep 2

if ! kill -0 "$GO2RTC_PID" 2>/dev/null; then
    echo "go2rtc failed to start"
    exit 1
fi

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
    python3 "$web_script" --open &
    WEB_PID=$!
    echo "Web UI running (Ctrl+C to stop)"
    wait $WEB_PID 2>/dev/null || true
}

case "$PLAYER" in
    vlc) play_with_vlc ;;
    mpv) play_with_mpv ;;
    web) play_with_web ;;
    *)
        echo "Usage: $0 [mpv|vlc|web]"
        exit 1
        ;;
esac
