#!/usr/bin/env python3
"""Captcha solver — pluggable backends over one image in / answer out contract.

Backends:
  openai  POST image to any OpenAI-compatible vision endpoint (default:
          gpu-box llama-swap at http://10.147.17.2:5170/v1).
  manual  Print the image path + prompt, read the answer from stdin
          (lets a human or the agent's own vision close the loop).
  cmd     Run a shell command template; {image} is substituted; stdout
          (last non-empty line) is the answer.

Usage:
  captcha_solver.py solve <image> [--prompt P]
  echo answer | captcha_solver.py manual <image>
  captcha_solver.py cmd --template 'my solver {image}' <image>

Config via env or flags (flags win):
  CAPTCHA_API_BASE   default http://10.147.17.2:5170
  CAPTCHA_MODEL      default qwen38-27b-q4   (vision-capable build needed)
  CAPTCHA_API_KEY    default none

Path modes:
  upstream (default)  gpu-box llama-swap style: POST
                      {api_base}/upstream/{model}/v1/chat/completions,
                      model NOT in body (per box routing, 2026-11)
  standard            generic OpenAI shape: POST {api_base}/chat/completions
                      with "model" in body

Output: single JSON line: {"answer": str, "backend": str, "ok": bool,
"latency_ms": int, "raw": str}  — raw holds backend payload for debugging.
Exit 0 on solve attempt (ok may be false), 2 on usage/config error.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

DEFAULT_BASE = os.environ.get("CAPTCHA_API_BASE",
                              "http://10.147.17.2:5170")
DEFAULT_MODEL = os.environ.get("CAPTCHA_MODEL", "qwen38-27b-q4")

DEFAULT_PROMPT = (
    "This image is a CAPTCHA challenge. Look at it carefully and reply "
    "with ONLY the required answer, nothing else:\n"
    "- If it shows distorted text, reply with the exact characters.\n"
    "- If it shows an arithmetic expression, reply with the computed "
    "number only.\n"
    "- If it asks to count objects, reply with the number only.\n"
    "No explanations, no punctuation, no spaces."
)


def b64_image(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def solve_openai(image_path, prompt, api_base, model, api_key, timeout=60,
                 path_mode="upstream"):
    """Send image+prompt to an OpenAI-compatible chat endpoint."""
    payload = {
        "max_tokens": 64,
        "temperature": 0,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url",
                 "image_url": {"url": "data:image/png;base64,"
                                      + b64_image(image_path)}},
            ],
        }],
    }
    if path_mode == "upstream":
        # llama-swap /upstream/{model}/ routing: model in URL path,
        # not in body
        url = "%s/upstream/%s/v1/chat/completions" % (
            api_base.rstrip("/"), model)
    else:
        payload["model"] = model
        url = api_base.rstrip("/") + "/chat/completions"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 **({"Authorization": "Bearer " + api_key}
                    if api_key else {})})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        return {"answer": "", "backend": "openai", "ok": False,
                "latency_ms": int((time.monotonic() - t0) * 1000),
                "raw": "request failed: %r" % (e,)}
    latency = int((time.monotonic() - t0) * 1000)
    try:
        raw = body["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        return {"answer": "", "backend": "openai", "ok": False,
                "latency_ms": latency, "raw": json.dumps(body)[:500]}
    return {"answer": _clean(raw), "backend": "openai", "ok": True,
            "latency_ms": latency, "raw": raw}


def solve_manual(image_path, prompt):
    """Human/agent-in-the-loop: print instructions, read stdin answer."""
    print("IMAGE: %s" % image_path, file=sys.stderr)
    print("PROMPT: %s" % prompt, file=sys.stderr)
    print("Type the answer and press Enter:", file=sys.stderr)
    answer = sys.stdin.readline().strip()
    return {"answer": _clean(answer), "backend": "manual",
            "ok": bool(answer), "latency_ms": 0, "raw": answer}


def solve_cmd(image_path, prompt, template):
    """Shell out: {image} in the template becomes the image path."""
    cmd = template.replace("{image}", image_path)
    t0 = time.monotonic()
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                       timeout=120)
    out = [l.strip() for l in r.stdout.splitlines() if l.strip()]
    answer = out[-1] if out else ""
    return {"answer": _clean(answer), "backend": "cmd",
            "ok": r.returncode == 0 and bool(answer),
            "latency_ms": int((time.monotonic() - t0) * 1000),
            "raw": r.stdout.strip()[:500] or r.stderr.strip()[:500]}


def _clean(text):
    """Strip markdown fences/quotes/preamble a chatty VLM might add."""
    t = text.strip()
    if t.startswith("```"):
        t = t.strip("`").lstrip("json").strip()
    t = t.strip().strip('"').strip("'").strip()
    # keep only the final short line; captchas are single-token answers
    lines = [l.strip() for l in t.splitlines() if l.strip()]
    return lines[-1][:64] if lines else ""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("backend", choices=["solve", "manual", "cmd"])
    ap.add_argument("image", help="path to captcha image")
    ap.add_argument("--prompt", default=DEFAULT_PROMPT)
    ap.add_argument("--api-base", default=DEFAULT_BASE)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--api-key", default=os.environ.get("CAPTCHA_API_KEY", ""))
    ap.add_argument("--template", help="cmd backend: command containing {image}")
    a = ap.parse_args()

    if not os.path.isfile(a.image):
        print(json.dumps({"ok": False, "error": "no such image: %s" % a.image}))
        sys.exit(2)

    if a.backend == "solve":
        res = solve_openai(a.image, a.prompt, a.api_base, a.model, a.api_key)
        if not res.get("answer"):
            # empty read: retry once with a blunt fallback prompt
            fb = ("Read the distorted text or arithmetic in this image. "
                  "Reply with ONLY the answer characters or number.")
            res2 = solve_openai(a.image, fb, a.api_base, a.model, a.api_key)
            if res2.get("answer"):
                res2["retry"] = True
                res = res2
        res["image"] = a.image
    elif a.backend == "manual":
        res = solve_manual(a.image, a.prompt)
    else:
        if not a.template:
            print(json.dumps({"ok": False,
                              "error": "cmd backend needs --template"}))
            sys.exit(2)
        res = solve_cmd(a.image, a.prompt, a.template)
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
