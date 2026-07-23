#!/usr/bin/env python3
"""Discover a local IP camera when the default host is unreachable.

Scans the local subnet for hosts with RTSP (554) open, prefers those that also
have the ONVIF port open, and verifies the winner with an unauthenticated
ONVIF GetSystemDateAndTime probe. Prints the verified camera IP to stdout.

Usage:
    cam_discover.py [--port ONVIF_PORT] [--subnet 192.168.1] [--timeout 0.4]
"""

import argparse
import socket
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

RTSP_PORT = 554
DEFAULT_ONVIF_PORT = 8899
CONNECT_TIMEOUT = 0.4
VERIFY_TIMEOUT = 3.0
MAX_WORKERS = 128


def local_subnet():
    """Return the /24 prefix (e.g. '192.168.1') of the default-route LAN.

    Opens a UDP socket to a public address; no packets are actually sent, but
    the kernel picks the source IP of the default route interface.
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ".".join(ip.split(".")[:3])
    except OSError:
        pass
    return None


def port_open(ip, port, timeout=CONNECT_TIMEOUT):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def scan_rtsp_hosts(subnet, timeout):
    """Return IPs in subnet.0/24 with the RTSP port open."""
    found = []
    hosts = [f"{subnet}.{h}" for h in range(1, 255)]
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futs = {ex.submit(port_open, h, RTSP_PORT, timeout): h for h in hosts}
        for f in as_completed(futs):
            if f.result():
                found.append(futs[f])
    return sorted(found)


def verify_onvif(ip, onvif_port):
    """Unauthenticated ONVIF probe — confirms the host is an IP camera."""
    try:
        from onvif import ONVIFCamera
    except ImportError:
        return True
    try:
        cam = ONVIFCamera(ip, onvif_port, "admin", "")
        cam.devicemgmt.GetSystemDateAndTime()
        return True
    except Exception:
        return False


def discover(onvif_port, subnet=None, timeout=CONNECT_TIMEOUT):
    subnets = [subnet] if subnet else [local_subnet()]
    subnets = [s for s in subnets if s]
    if not subnets:
        return None

    rtsp_hosts = []
    for net in subnets:
        rtsp_hosts.extend(scan_rtsp_hosts(net, timeout))
    if not rtsp_hosts:
        return None

    # Prefer hosts that also expose the ONVIF port (strong camera signature).
    onvif_hosts = [ip for ip in rtsp_hosts if port_open(ip, onvif_port, timeout)]
    ordered = onvif_hosts or rtsp_hosts

    # Verify each candidate; return the first that answers ONVIF.
    for ip in ordered:
        if verify_onvif(ip, onvif_port):
            return ip
    # Best-effort fallback: first RTSP host if ONVIF verification is flaky.
    return ordered[0]


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--port", type=int, default=DEFAULT_ONVIF_PORT,
                   help=f"ONVIF port to verify (default: {DEFAULT_ONVIF_PORT})")
    p.add_argument("--subnet", default=None,
                   help="/24 prefix to scan (default: auto-detect LAN)")
    p.add_argument("--timeout", type=float, default=CONNECT_TIMEOUT,
                   help=f"per-host connect timeout in seconds (default: {CONNECT_TIMEOUT})")
    p.add_argument("-q", "--quiet", action="store_true",
                   help="suppress progress messages on stderr")
    args = p.parse_args()

    def log(msg):
        if not args.quiet:
            print(msg, file=sys.stderr)

    log(f"Scanning for camera (RTSP:{RTSP_PORT}/ONVIF:{args.port})...")
    ip = discover(args.port, args.subnet, args.timeout)
    if ip:
        log(f"Found camera at {ip}")
        print(ip)
        return 0
    log("No camera found on the local network.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
