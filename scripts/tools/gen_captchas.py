#!/usr/bin/env python3
"""Generate a test set of captchas: distorted text + arithmetic images.

Each captcha is written as <name>.png plus a manifest.json mapping the
image to the expected answer, so a solver can be scored mechanically.

Usage:
  gen_captchas.py OUT_DIR [COUNT]

Needs: uv run --with pillow python gen_captchas.py ...
"""

import json
import os
import random
import string
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def _font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def gen_text(path, rng):
    chars = "".join(rng.choice(string.ascii_uppercase + string.digits)
                    for _ in range(rng.randint(4, 5)))
    w, h = 220, 80
    img = Image.new("RGB", (w, h), (245, 245, 245))
    d = ImageDraw.Draw(img)
    # noise lines
    for _ in range(rng.randint(3, 6)):
        x1, y1 = rng.randint(0, w), rng.randint(0, h)
        x2, y2 = rng.randint(0, w), rng.randint(0, h)
        d.line([(x1, y1), (x2, y2)],
               fill=(rng.randint(60, 180),) * 3, width=rng.randint(1, 2))
    # per-char jitter
    x = 18
    for ch in chars:
        y = rng.randint(8, 22)
        ang = rng.randint(-25, 25)
        glyph = Image.new("RGBA", (60, 70), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glyph)
        gd.text((6, 6), ch, font=_font(44), fill=(30, 30, 90, 255))
        glyph = glyph.rotate(ang, expand=True,
                             resample=Image.Resampling.BICUBIC)
        img.paste(glyph, (x, y), glyph)
        x += 34
    # noise dots
    for _ in range(rng.randint(40, 90)):
        d.point((rng.randint(0, w - 1), rng.randint(0, h - 1)),
                fill=(rng.randint(0, 200),) * 3)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(path)
    return chars


def gen_math(path, rng):
    a, b = rng.randint(2, 19), rng.randint(2, 19)
    op = rng.choice(["+", "-", "x"])
    expr = "%d %s %d" % (a, op, b)
    ans = a + b if op == "+" else a - b if op == "-" else a * b
    img = Image.new("RGB", (220, 80), (250, 250, 245))
    d = ImageDraw.Draw(img)
    d.text((40, 22), "%s = ?" % expr, font=_font(34), fill=(20, 20, 60))
    for _ in range(rng.randint(30, 70)):
        d.point((rng.randint(0, 219), rng.randint(0, 79)),
                fill=(rng.randint(0, 180),) * 3)
    img.save(path)
    return str(ans)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/captcha_test"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    os.makedirs(out, exist_ok=True)
    rng = random.Random()
    manifest = {}
    for i in range(count):
        name = "cap%02d" % i
        path = os.path.join(out, name + ".png")
        if i % 2 == 0:
            expected = gen_text(path, rng)
            kind = "text"
        else:
            expected = gen_math(path, rng)
            kind = "math"
        manifest[name + ".png"] = {"answer": expected, "kind": kind}
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(json.dumps({"dir": out, "count": count}))


if __name__ == "__main__":
    main()
