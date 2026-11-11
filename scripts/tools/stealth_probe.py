#!/usr/bin/env python3
"""Stealth fingerprint probe — main-world verification for patchright.

patchright runs page.evaluate() in an ISOLATED world, so main-world
hooks (our WebGL spoof) are invisible to it. This probe verifies the
spoof the honest way: add_script_tag runs JS in the MAIN world and
writes results into the DOM, which IS shared across worlds.

Usage:
  xvfb-run -a uv run --with patchright python stealth_probe.py
"""

import json

from patchright.sync_api import sync_playwright

from webgl_spoof import install as install_spoof

STEALTH_ARGS = ["--enable-unsafe-swiftshader"]

# Runs in MAIN world via add_script_tag; writes results into the DOM.
MAIN_WORLD_WRITER = """
(() => {
  const out = {};
  out.userAgent = navigator.userAgent;
  out.webdriver = navigator.webdriver;
  out.pluginsLength = navigator.plugins.length;
  out.deviceMemory = navigator.deviceMemory;
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl');
    const dbg = gl.getExtension('WEBGL_debug_renderer_info');
    out.webglVendor = gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL);
    out.webglRenderer = gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL);
    out.getParameterToStringNative =
        String(gl.getParameter).includes('[native code]');
  } catch (e) { out.webglErr = String(e); }
  navigator.mediaDevices.enumerateDevices().then(devs => {
    out.mediaDevices = devs.map(d => d.kind);
    const pre = document.createElement('pre');
    pre.id = '__probeResult';
    pre.textContent = JSON.stringify(out);
    document.documentElement.appendChild(pre);
  }).catch(e => {
    out.mediaErr = String(e);
    const pre = document.createElement('pre');
    pre.id = '__probeResult';
    pre.textContent = JSON.stringify(out);
    document.documentElement.appendChild(pre);
  });
})();
"""

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False, args=STEALTH_ARGS)
    ctx = browser.new_context(viewport={"width": 1280, "height": 900},
                              locale="en-US")
    install_spoof(ctx)
    page = ctx.new_page()
    page.goto("https://example.com/", timeout=30000)
    page.wait_for_timeout(300)
    page.add_script_tag(content=MAIN_WORLD_WRITER)
    page.wait_for_selector("#__probeResult", timeout=10000)
    result = json.loads(
        page.locator("#__probeResult").text_content())
    browser.close()
print(json.dumps(result, indent=1))
