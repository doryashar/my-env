#!/usr/bin/env python3

import sys
import os
import time
import json

try:
    from onvif import ONVIFCamera
    from onvif.exceptions import ONVIFError
except ImportError:
    print(
        "Error: onvif-zeep not installed. Run: pip install onvif-zeep", file=sys.stderr
    )
    sys.exit(1)

try:
    import requests
    from requests.auth import HTTPDigestAuth
except ImportError:
    print("Error: requests not installed. Run: pip install requests", file=sys.stderr)
    sys.exit(1)


CAM_IP = "192.168.1.140"
CAM_PORT = 8899
CAM_USER = "admin"
CAM_PASS = "1111"
PROFILE_TOKEN = "000"
VIDEO_SOURCE_TOKEN = "000"


def get_camera():
    cam = ONVIFCamera(CAM_IP, CAM_PORT, CAM_USER, CAM_PASS)
    cam.update_xaddrs()
    return cam


def get_ptz(cam):
    return cam.create_ptz_service()


def get_imaging(cam):
    return cam.create_imaging_service()


def get_status(cam):
    ptz = get_ptz(cam)
    try:
        status = ptz.GetStatus({"ProfileToken": PROFILE_TOKEN})
        pt = status.Position.PanTilt
        zm = status.Position.Zoom
        return {
            "pan_tilt": {"x": float(pt.x), "y": float(pt.y)},
            "zoom": float(zm.x),
            "move_status": {
                "pan_tilt": str(status.MoveStatus.PanTilt),
                "zoom": str(status.MoveStatus.Zoom),
            },
        }
    except ONVIFError as e:
        print(f"Error getting status: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_status(cam):
    return get_status(cam)


def cmd_continuous_move(cam, direction, speed, duration):
    ptz = get_ptz(cam)
    try:
        status = ptz.GetStatus({"ProfileToken": PROFILE_TOKEN})
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    vec2d = type(status.Position.PanTilt)
    vec1d = type(status.Position.Zoom)
    pos_type = type(status.Position)

    directions = {
        "pan-left": (-1, 0, 0),
        "pan-right": (1, 0, 0),
        "tilt-up": (0, 1, 0),
        "tilt-down": (0, -1, 0),
        "zoom-in": (0, 0, 1),
        "zoom-out": (0, 0, -1),
    }
    if direction not in directions:
        print(
            f"Unknown direction: {direction}. Use: {', '.join(directions.keys())}",
            file=sys.stderr,
        )
        sys.exit(1)

    px, py, zx = directions[direction]
    velocity = pos_type(
        PanTilt=vec2d(x=float(px * speed), y=float(py * speed)),
        Zoom=vec1d(x=float(zx * speed)),
    )

    try:
        request = ptz.create_type("ContinuousMove")
        request.ProfileToken = PROFILE_TOKEN
        request.Velocity = velocity
        ptz.ContinuousMove(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if duration and duration > 0:
        time.sleep(duration)
        cmd_stop(cam)


def cmd_stop(cam):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("Stop")
        request.ProfileToken = PROFILE_TOKEN
        request.PanTilt = True
        request.Zoom = True
        ptz.Stop(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_relative_move(cam, pan_x, pan_y, zoom_x, speed):
    ptz = get_ptz(cam)
    try:
        status = ptz.GetStatus({"ProfileToken": PROFILE_TOKEN})
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    vec2d = type(status.Position.PanTilt)
    vec1d = type(status.Position.Zoom)
    pos_type = type(status.Position)

    translation = pos_type(
        PanTilt=vec2d(x=float(pan_x), y=float(pan_y)),
        Zoom=vec1d(x=float(zoom_x)),
    )
    spd = pos_type(
        PanTilt=vec2d(x=float(speed), y=float(speed)),
        Zoom=vec1d(x=float(speed)),
    )

    try:
        request = ptz.create_type("RelativeMove")
        request.ProfileToken = PROFILE_TOKEN
        request.Translation = translation
        request.Speed = spd
        ptz.RelativeMove(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_home(cam):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("GotoHomePosition")
        request.ProfileToken = PROFILE_TOKEN
        ptz.GotoHomePosition(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_preset_list(cam):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("GetPresets")
        request.ProfileToken = PROFILE_TOKEN
        presets = ptz.GetPresets(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if not presets:
        print("No presets found.")
        return

    for p in presets:
        print(f"  {p.token}: {p.Name}")


def cmd_preset_goto(cam, token):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("GotoPreset")
        request.ProfileToken = PROFILE_TOKEN
        request.PresetToken = str(token)
        ptz.GotoPreset(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_preset_set(cam, token, name=None):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("SetPreset")
        request.ProfileToken = PROFILE_TOKEN
        request.PresetToken = str(token)
        request.PresetName = name or f"Preset_{token}"
        result = ptz.SetPreset(request)
        print(f"Preset saved: token={result}")
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_preset_remove(cam, token):
    ptz = get_ptz(cam)
    try:
        request = ptz.create_type("RemovePreset")
        request.ProfileToken = PROFILE_TOKEN
        request.PresetToken = str(token)
        ptz.RemovePreset(request)
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_brightness(cam, value):
    imaging = get_imaging(cam)
    try:
        settings = imaging.GetImagingSettings({"VideoSourceToken": VIDEO_SOURCE_TOKEN})
        settings.Brightness = float(value)
        imaging.SetImagingSettings(
            {"VideoSourceToken": VIDEO_SOURCE_TOKEN, "ImagingSettings": settings}
        )
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_contrast(cam, value):
    imaging = get_imaging(cam)
    try:
        settings = imaging.GetImagingSettings({"VideoSourceToken": VIDEO_SOURCE_TOKEN})
        settings.Contrast = float(value)
        imaging.SetImagingSettings(
            {"VideoSourceToken": VIDEO_SOURCE_TOKEN, "ImagingSettings": settings}
        )
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_saturation(cam, value):
    imaging = get_imaging(cam)
    try:
        settings = imaging.GetImagingSettings({"VideoSourceToken": VIDEO_SOURCE_TOKEN})
        settings.ColorSaturation = float(value)
        imaging.SetImagingSettings(
            {"VideoSourceToken": VIDEO_SOURCE_TOKEN, "ImagingSettings": settings}
        )
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_sharpness(cam, value):
    imaging = get_imaging(cam)
    try:
        settings = imaging.GetImagingSettings({"VideoSourceToken": VIDEO_SOURCE_TOKEN})
        settings.Sharpness = float(value)
        imaging.SetImagingSettings(
            {"VideoSourceToken": VIDEO_SOURCE_TOKEN, "ImagingSettings": settings}
        )
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_snapshot(cam, output=None):
    media = cam.create_media_service()
    try:
        request = media.create_type("GetSnapshotUri")
        request.ProfileToken = PROFILE_TOKEN
        result = media.GetSnapshotUri(request)
        url = result.Uri
    except ONVIFError as e:
        print(f"Error getting snapshot URI: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        resp = requests.get(
            url, auth=HTTPDigestAuth(CAM_USER, CAM_PASS), timeout=10, stream=True
        )
        resp.raise_for_status()
    except Exception as e:
        print(f"Error downloading snapshot: {e}", file=sys.stderr)
        sys.exit(1)

    if output is None:
        output = f"/tmp/cam_snapshot_{int(time.time())}.jpg"

    with open(output, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)

    print(f"Snapshot saved: {output}")


def cmd_imaging_status(cam):
    imaging = get_imaging(cam)
    try:
        settings = imaging.GetImagingSettings({"VideoSourceToken": VIDEO_SOURCE_TOKEN})
        return {
            "brightness": float(settings.Brightness),
            "contrast": float(settings.Contrast),
            "saturation": float(settings.ColorSaturation),
            "sharpness": float(settings.Sharpness),
        }
    except ONVIFError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def print_usage():
    usage = """\
Usage: cam_ctrl.py <command> [args...]

PTZ Movement:
  move <direction> [speed] [duration_sec]
      direction: pan-left, pan-right, tilt-up, tilt-down, zoom-in, zoom-out
      speed: 0.0-1.0 (default: 0.5)
      duration: seconds to move (default: 1, omit for no auto-stop)
  relative <pan_x> <tilt_y> [zoom] [speed]
      Move by relative amount (-1 to 1 range)
  stop                   Stop all movement
  home                   Go to home position

Presets:
  preset-list            List all presets
  preset-goto <token>    Go to preset
  preset-set <token> [name]  Save current position as preset
  preset-remove <token>  Delete a preset

Imaging:
  brightness <0-100>     Set brightness
  contrast <0-100>       Set contrast
  saturation <0-100>     Set color saturation
  sharpness <0-15>       Set sharpness
  imaging                Show current imaging settings

Other:
  status                 Show PTZ position and status
  snapshot [output.jpg]  Capture still image (default: /tmp/cam_snapshot_<ts>.jpg)
"""
    print(usage)


def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    command = sys.argv[1]
    args = sys.argv[2:]

    try:
        cam = get_camera()
    except Exception as e:
        print(f"Error connecting to camera: {e}", file=sys.stderr)
        sys.exit(1)

    if command == "status":
        print(json.dumps(cmd_status(cam), indent=2))
    elif command == "move":
        direction = args[0] if args else None
        if not direction:
            print("Error: direction required", file=sys.stderr)
            sys.exit(1)
        speed = float(args[1]) if len(args) > 1 else 0.5
        duration = float(args[2]) if len(args) > 2 else 1.0
        cmd_continuous_move(cam, direction, speed, duration)
    elif command == "stop":
        cmd_stop(cam)
    elif command == "home":
        cmd_home(cam)
    elif command == "relative":
        pan_x = float(args[0]) if len(args) > 0 else 0
        pan_y = float(args[1]) if len(args) > 1 else 0
        zoom = float(args[2]) if len(args) > 2 else 0
        speed = float(args[3]) if len(args) > 3 else 0.5
        cmd_relative_move(cam, pan_x, pan_y, zoom, speed)
    elif command == "preset-list":
        cmd_preset_list(cam)
    elif command == "preset-goto":
        if not args:
            print("Error: preset token required", file=sys.stderr)
            sys.exit(1)
        cmd_preset_goto(cam, args[0])
    elif command == "preset-set":
        if not args:
            print("Error: preset token required", file=sys.stderr)
            sys.exit(1)
        name = args[1] if len(args) > 1 else None
        cmd_preset_set(cam, args[0], name)
    elif command == "preset-remove":
        if not args:
            print("Error: preset token required", file=sys.stderr)
            sys.exit(1)
        cmd_preset_remove(cam, args[0])
    elif command == "brightness":
        if not args:
            print("Error: value required (0-100)", file=sys.stderr)
            sys.exit(1)
        cmd_brightness(cam, args[0])
    elif command == "contrast":
        if not args:
            print("Error: value required (0-100)", file=sys.stderr)
            sys.exit(1)
        cmd_contrast(cam, args[0])
    elif command == "saturation":
        if not args:
            print("Error: value required (0-100)", file=sys.stderr)
            sys.exit(1)
        cmd_saturation(cam, args[0])
    elif command == "sharpness":
        if not args:
            print("Error: value required (0-15)", file=sys.stderr)
            sys.exit(1)
        cmd_sharpness(cam, args[0])
    elif command == "imaging":
        print(json.dumps(cmd_imaging_status(cam), indent=2))
    elif command == "snapshot":
        output = args[0] if args else None
        cmd_snapshot(cam, output)
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        print_usage()
        sys.exit(1)


if __name__ == "__main__":
    main()
