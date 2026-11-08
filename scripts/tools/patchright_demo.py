#!/usr/bin/env python3
"""Patchright (stealth Playwright) captcha-solving demo.

Renders a fresh captcha into a local HTML page, drives it with Patchright,
screenshots the captcha element, and optionally submits an answer and
reads the verdict. Deterministic per --seed so a solve can happen in a
second run against the identical challenge:

  # phase 1 — capture the challenge
  patchright_demo.py --seed 7 --shot /tmp/shot.png
  # (solve /tmp/shot.png via captcha_solver.py / human / agent vision)
  # phase 2 — submit the answer
  patchright_demo.py --seed 7 --answer AB3X --shot /tmp/shot2.png

Also: --bot-detect loads bot.sannysoft.com and screenshots what leaks.

Needs: uv run --with patchright --with pillow python patchright_demo.py ...
"""

import argparse
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gen_captchas import gen_math, gen_text  # noqa: E402
from webgl_spoof import install as install_spoof  # noqa: E402

PAGE_DIR = "/tmp/captcha_demo"

HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>captcha demo</title>
<style>
  body { font-family: sans-serif; background: #fafafa; padding: 40px; }
  .card { background: #fff; border: 1px solid #ddd; padding: 24px;
          width: 320px; border-radius: 8px; }
  #captcha { border: 1px solid #ccc; border-radius: 4px; }
  input { font-size: 20px; padding: 6px 10px; width: 200px; }
  button { font-size: 16px; padding: 8px 18px; }
  #verdict { margin-top: 14px; font-weight: bold; }
  .pass { color: #0a7d32; } .fail { color: #b3261e; }
</style></head>
<body><div class="card">
  <h3>Verify: type the captcha</h3>
  <img id="captcha" src="captcha.png" alt="captcha">
  <p><input id="answer" placeholder="answer">
     <button id="submit" onclick="check()">Check</button></p>
  <div id="verdict"></div>
</div>
<script>window.EXPECTED = "__EXPECTED__";</script>
<script>
function check() {
  const v = document.getElementById('answer').value.trim();
  const ok = v.toUpperCase() === window.EXPECTED.toUpperCase();
  const el = document.getElementById('verdict');
  el.textContent = ok ? 'PASS' : 'FAIL: got "' + v + '"';
  el.className = ok ? 'pass' : 'fail';
}
</script></body></html>"""


def build_page(seed, page_dir):
    """Render captcha for this seed into page_dir; return expected answer."""
    os.makedirs(page_dir, exist_ok=True)
    rng = random.Random(seed)
    if seed % 2 == 0:
        expected = gen_text(os.path.join(page_dir, "captcha.png"), rng)
    else:
        expected = gen_math(os.path.join(page_dir, "captcha.png"), rng)
    with open(os.path.join(page_dir, "index.html"), "w") as f:
        f.write(HTML.replace("__EXPECTED__", expected))
    return expected


STEALTH_ARGS = ["--enable-unsafe-swiftshader"]  # software WebGL on GPU-less hosts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--answer", help="submit this answer after screenshot")
    ap.add_argument("--shot", default="/tmp/captcha_shot.png")
    ap.add_argument("--bot-detect", action="store_true",
                    help="also load bot.sannysoft.com and screenshot it")
    ap.add_argument("--headed", action="store_true",
                    help="headed chromium (run under xvfb-run on servers)")
    a = ap.parse_args()

    expected = build_page(a.seed, PAGE_DIR)
    url = "file://" + PAGE_DIR + "/index.html"

    from patchright.sync_api import sync_playwright
    result = {"seed": a.seed, "expected": None, "answer": None,
              "success": None, "shot": a.shot}
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(headless=a.headed is False,
                                        args=STEALTH_ARGS, channel="chrome")
        except Exception:
            # real Chrome not installed — fall back to patchright chromium
            browser = p.chromium.launch(headless=a.headed is False,
                                        args=STEALTH_ARGS)
        ctx = browser.new_context(
            viewport={"width": 900, "height": 700}, locale="en-US")
        install_spoof(ctx)
        page = ctx.new_page()
        page.goto(url)
        page.wait_for_selector("#captcha")
        page.wait_for_timeout(400)
        page.locator("#captcha").screenshot(path=a.shot)
        result["challenge"] = ("math" if a.seed % 2 else "text")

        if a.answer:
            result["answer"] = a.answer
            page.fill("#answer", a.answer)
            page.click("#submit")
            page.wait_for_timeout(200)
            verdict = page.locator("#verdict").inner_text()
            result["verdict"] = verdict
            result["success"] = verdict.startswith("PASS")
            # keep the expected answer secret-ish: reveal only on fail
            result["expected"] = expected if not result["success"] else None
        if a.bot_detect:
            bd = "/tmp/botdetect.png"
            page2 = ctx.new_page()
            page2.goto("https://bot.sannysoft.com/",
                       wait_until="load", timeout=45000)
            page2.wait_for_timeout(6000)
            page2.screenshot(path=bd, full_page=True)
            result["botdetect_shot"] = bd
        browser.close()
    if not a.answer:
        result["expected"] = None  # phase 1: don't leak the answer
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
