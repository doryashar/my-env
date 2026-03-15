#!/bin/bash
set -e

GO2RTC_BIN="/tmp/go2rtc"
GO2RTC_CONFIG="/tmp/go2rtc_showcam.yaml"
CAMERA_URL="rtsp://admin:1111@192.168.1.140:554/streamtype=0"
GO2RTC_PORT=1984

if [[ ! -x "$GO2RTC_BIN" ]]; then
    echo "Downloading go2rtc..."
    curl -L "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" -o "$GO2RTC_BIN"
    chmod +x "$GO2RTC_BIN"
fi

cat > "$GO2RTC_CONFIG" <<EOF
streams:
  camera:
    - rtsp://admin:1111@192.168.1.140:554/streamtype=0
    - "ffmpeg:camera#input=-rtsp_transport tcp"
api:
  listen: ":$GO2RTC_PORT"
EOF

cleanup() {
    if [[ -n "$GO2RTC_PID" ]]; then
        kill "$GO2RTC_PID" 2>/dev/null || true
        wait "$GO2RTC_PID" 2>/dev/null || true
    fi
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

echo "Opening camera stream in mpv..."
mpv --profile=low-latency --no-cache --untimed "http://localhost:$GO2RTC_PORT/api/stream.m3u8?src=camera"
