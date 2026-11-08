#!/usr/bin/env python3
"""Camoufox stealth test: load bot.sannysoft.com headless, screenshot it.

Usage:
  uv run --with camoufox --with pillow python camoufox_stealth_test.py
  (first run downloads the Camoufox Firefox build: python -m camoufox fetch)
"""

import json

from camoufox.sync_api import Camoufox

OUT = "/tmp/camoufox_botdetect.png"

with Camoufox(headless=True, humanize=True) as browser:
    page = browser.new_page()
    page.goto("https://bot.sannysoft.com/", wait_until="load",
              timeout=60000)
    page.wait_for_timeout(6000)
    page.screenshot(path=OUT, full_page=True)
    print(json.dumps({"shot": OUT,
                      "ua": page.evaluate("navigator.userAgent"),
                      "webdriver": page.evaluate("navigator.webdriver")}))
