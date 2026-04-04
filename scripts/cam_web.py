#!/usr/bin/env python3

import json
import os
import sys
import time
import argparse
import tempfile
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
try:
    import cam_ctrl
except ImportError:
    print("Error: cam_ctrl.py not found in the same directory", file=sys.stderr)
    sys.exit(1)

DEFAULT_PORT = 9090
GO2RTC_HOST = "localhost:19084"
GO2RTC_HLS = f"http://{GO2RTC_HOST}/api/stream.m3u8?src=camera"
GO2RTC_MJPEG = f"http://{GO2RTC_HOST}/api/stream.mjpeg?src=camera"
GO2RTC_MSE = f"http://{GO2RTC_HOST}/api/stream.mse?src=camera"
GO2RTC_WEBRTC = f"http://{GO2RTC_HOST}/api/webrtc?src=camera"
SNAPSHOT_CACHE_DIR = os.path.join(tempfile.gettempdir(), "cam_snapshots")


class CamAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send_body(self, data):
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def _json_response(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self._send_body(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if length:
            return json.loads(self.rfile.read(length))
        return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def _handle_get(self, path):
        if path == "/" or path == "/index.html":
            html_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "cam_web.html"
            )
            if os.path.exists(html_path):
                with open(html_path, "rb") as f:
                    return ("html", f.read(), 200)
            return ("json", {"error": "cam_web.html not found"}, 404)

        try:
            cam = cam_ctrl.get_camera()
        except Exception as e:
            return ("json", {"error": str(e)}, 503)

        try:
            if path == "/api/status":
                return ("json", cam_ctrl.cmd_status(cam), 200)
            elif path == "/api/imaging":
                return ("json", cam_ctrl.cmd_imaging_status(cam), 200)
            elif path == "/api/presets":
                ptz = cam_ctrl.get_ptz(cam)
                req = ptz.create_type("GetPresets")
                req.ProfileToken = "000"
                presets = ptz.GetPresets(req)
                return (
                    "json",
                    [{"token": p.token, "name": p.Name} for p in (presets or [])],
                    200,
                )
            elif path == "/api/stream-url":
                return (
                    "json",
                    {
                        "hls": GO2RTC_HLS,
                        "mjpeg": GO2RTC_MJPEG,
                        "mse": GO2RTC_MSE,
                        "webrtc": GO2RTC_WEBRTC,
                    },
                    200,
                )
            elif path == "/api/snapshot":
                ts = int(time.time() * 1000)
                filepath = os.path.join(SNAPSHOT_CACHE_DIR, f"snap_{ts}.jpg")
                os.makedirs(SNAPSHOT_CACHE_DIR, exist_ok=True)
                cam_ctrl.cmd_snapshot(cam, filepath)
                if os.path.exists(filepath):
                    with open(filepath, "rb") as f:
                        img_data = f.read()
                    return ("image", img_data, 200)
                return ("json", {"error": "snapshot failed"}, 500)
            else:
                return ("json", {"error": "Not found"}, 404)
        except Exception as e:
            return ("json", {"error": str(e)}, 500)

    def _handle_post(self, path, body):
        try:
            cam = cam_ctrl.get_camera()
        except Exception as e:
            return ("json", {"error": str(e)}, 503)

        try:
            if path == "/api/move":
                cam_ctrl.cmd_continuous_move(
                    cam,
                    body.get("direction", "pan-right"),
                    float(body.get("speed", 0.5)),
                    float(body.get("duration", 1)),
                )
                return ("json", {"ok": True}, 200)
            elif path == "/api/stop":
                cam_ctrl.cmd_stop(cam)
                return ("json", {"ok": True}, 200)
            elif path == "/api/home":
                cam_ctrl.cmd_home(cam)
                return ("json", {"ok": True}, 200)
            elif path == "/api/relative":
                cam_ctrl.cmd_relative_move(
                    cam,
                    float(body.get("pan", 0)),
                    float(body.get("tilt", 0)),
                    float(body.get("zoom", 0)),
                    float(body.get("speed", 0.5)),
                )
                return ("json", {"ok": True}, 200)
            elif path == "/api/preset/goto":
                cam_ctrl.cmd_preset_goto(cam, body.get("token", ""))
                return ("json", {"ok": True}, 200)
            elif path == "/api/preset/set":
                result = cam_ctrl.cmd_preset_set(
                    cam, body.get("token", ""), body.get("name")
                )
                return ("json", {"ok": True, "token": result}, 200)
            elif path == "/api/preset/remove":
                cam_ctrl.cmd_preset_remove(cam, body.get("token", ""))
                return ("json", {"ok": True}, 200)
            elif path in (
                "/api/brightness",
                "/api/contrast",
                "/api/saturation",
                "/api/sharpness",
            ):
                key = path.replace("/api/", "")
                getattr(cam_ctrl, f"cmd_{key}")(cam, body["value"])
                return ("json", {"ok": True}, 200)
            else:
                return ("json", {"error": "Not found"}, 404)
        except Exception as e:
            return ("json", {"error": str(e)}, 500)

    def do_GET(self):
        parsed = urlparse(self.path)
        kind, data, status = self._handle_get(parsed.path)
        if kind == "html":
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self._send_body(data)
        elif kind == "image":
            self.send_response(status)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self._send_body(data)
        else:
            self._json_response(data, status)

    def do_POST(self):
        parsed = urlparse(self.path)
        body = self._read_json()
        kind, data, status = self._handle_post(parsed.path, body)
        self._json_response(data, status)


def main():
    parser = argparse.ArgumentParser(description="Camera web control panel")
    parser.add_argument("-p", "--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--open", action="store_true", help="Open browser automatically"
    )
    args = parser.parse_args()
    server = HTTPServer(("0.0.0.0", args.port), CamAPIHandler)
    print(f"Camera web UI: http://localhost:{args.port}")
    if args.open:
        webbrowser.open(f"http://localhost:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()


if __name__ == "__main__":
    main()
