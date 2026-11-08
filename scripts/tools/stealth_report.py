#!/usr/bin/env python3
"""Full stealth report from bot.sannysoft.com — all sections as text.

Loads the page in the current stealth stack, waits for all sections to
render, then extracts every results table + the fp-collect block from
the DOM (DOM is shared across worlds, so evaluate can read it even
though patchright evaluates in an isolated world).

Usage:
  xvfb-run -a uv run --with patchright python stealth_report.py
"""

import json

from patchright.sync_api import sync_playwright

from webgl_spoof import install as install_spoof

STEALTH_ARGS = ["--enable-unsafe-swiftshader"]

EXTRACT = """
() => {
  const rows = [];
  document.querySelectorAll('tr').forEach(tr => {
    const cells = [...tr.querySelectorAll('td, th')]
      .map(td => td.innerText.trim().replace(/\\s+/g, ' ').slice(0, 220));
    if (cells.length >= 2 && cells.some(c => c.length)) rows.push(cells);
  });
  const pre = [];
  document.querySelectorAll('pre').forEach(p => {
    const t = p.innerText.trim();
    if (t.length > 40) pre.push(t.slice(0, 3000));
  });
  return {rows, pres: pre, title: document.title};
}
"""

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False, args=STEALTH_ARGS)
    ctx = browser.new_context(viewport={"width": 1280, "height": 900},
                              locale="en-US")
    install_spoof(ctx)
    page = ctx.new_page()
    page.goto("https://bot.sannysoft.com/", wait_until="load",
              timeout=60000)
    page.wait_for_timeout(8000)
    data = page.evaluate(EXTRACT)
    browser.close()
print(json.dumps(data, ensure_ascii=False, indent=1))
