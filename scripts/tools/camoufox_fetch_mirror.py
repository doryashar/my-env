#!/usr/bin/env python3
"""Install Camoufox browser via GitHub mirror fallback.

The OCI box's IP range gets 504s from GitHub's release-asset edge
(objects.githubusercontent.com) while api.github.com works fine, so we
keep the official fetcher logic (version resolution, sha256 verify,
version.json) and only reroute the download transport through mirrors.

Usage:
  uv run --with camoufox python camoufox_fetch_mirror.py [VERSION]
"""

import sys

import requests

import camoufox.pkgman as pkgman

MIRRORS = [
    "https://ghproxy.net/",
    "https://gh-proxy.com/",
    "https://ghfast.top/",
    "https://github.moeyy.xyz/",
    "https://hub.gitmirror.com/",
]

_orig_get = requests.get


def _mirrored_get(url, **kw):
    """requests.get that reroutes github.com asset URLs via mirrors."""
    if url.startswith("https://github.com/"):
        for m in MIRRORS:
            try:
                r = _orig_get(m + url, timeout=60, **kw)
                if r.status_code == 200:
                    print("[mirror ok] %s%s" % (m, url.split("/")[-1]))
                    return r
                print("[mirror %d] %s" % (r.status_code, m))
            except Exception as e:
                print("[mirror err] %s: %r" % (m, e))
        # last resort: direct (in case the edge recovered)
        print("[direct fallback] %s" % url)
        return _orig_get(url, **kw)
    return _orig_get(url, **kw)


requests.get = _mirrored_get
pkgman.requests.get = _mirrored_get

ver = sys.argv[1] if len(sys.argv) > 1 else None
f = pkgman.CamoufoxFetcher()
if ver:
    f.set_version(ver)
f.install()
print("INSTALL OK")
