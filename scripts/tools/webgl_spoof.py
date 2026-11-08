"""WebGL / media-device / canvas spoof — patchright route injection.

Hardens the GPU-less host (Xvfb + SwiftShader) against fingerprinting:

1. WebGL UNMASKED_VENDOR/RENDERER report a Linux-consistent NVIDIA
   ANGLE/Vulkan pair matching the Linux X11 UA; VERSION /
   SHADING_LANGUAGE_VERSION strings are scrubbed of "SwiftShader".
2. navigator.mediaDevices.enumerateDevices lists a believable
   2x audioinput + 1x videoinput + 2x audiooutput desktop set.
   Like real Chrome, deviceId/label/groupId stay blank until the
   kind is actually permission-revealed (tracked off the real
   native enumeration). getUserMedia "device not found" failures
   are rewritten to NotAllowedError so the story stays
   "webcam exists, user denied" instead of leaking the empty host.
3. Canvas reads (toDataURL/toBlob/getImageData/readPixels) get
   deterministic LSB-parity noise from a fixed persona seed: stable
   across sessions (like a real install), identical across realms,
   and no longer the well-known software-renderer hashes
   (e.g. -419353324).
4. Iframe realms: hooks install lazily into same-origin child
   realms when the page first touches iframe.contentDocument /
   contentWindow (bot.sannysoft-style canvas tests create their
   canvases through exactly that path), keeping canvas hashes
   consistent across frames.

Anti-detection: every hook is masked with native-looking
name/length/toString, replaced at prototype level (no instance
own-property leaks), no Proxy, no new globals; each section fails
open silently.

patchright no-ops add_init_script and CDP script injection by design,
so install() wires everything via context.route() HTML rewriting.

Battery stays charging:true/level:1 (plausible desktop; left alone).
Residuals (accepted): cross-origin iframes are untouched (correct);
data:/srcdoc documents never load via network AND are only covered
if the page reaches them through contentDocument/contentWindow;
Function.prototype.toString.call(hook) in the hook's own realm still
reveals source (only naive fn.toString() probes are defeated);
WebGL extension/capability lists stay native (faking them without
matching behavior is worse).
"""

import json
import re
import sys

# Internally-consistent Linux desktop pair for Chrome 156 on Ubuntu
# with the NVIDIA proprietary driver: ANGLE over the Vulkan backend
# (what real Linux Chrome has reported for years — D3D11 strings are
# a Windows tell). Device 2503 = RTX 3060 12GB, vendor 10DE = NVIDIA.
VENDOR = "Google Inc. (NVIDIA)"
RENDERER = (
    "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002503), Vulkan 1.3.290 "
    "(NVIDIA GeForce RTX 3060 (0x00002503) [10DE-2503]))"
)

SPOOF_JS = """
(() => {
'use strict';
const SEED = __SEED__;
// NOTE: SEED is a fixed compile-time constant, not per-session random:
// (a) same noise in every realm (top doc AND srcdoc/data: iframes get
//     no route injection, so per-session randomness = cross-frame hash
//     mismatch, itself a bot tell); (b) real browsers keep canvas hash
//     stable per install, so cross-session stability is the realistic
//     behavior. Bump via build_spoof_js(seed=...) to rotate personas.
const VENDOR = __VENDOR__;
const RENDERER = __RENDERER__;
const LIMIT = 1 << 20; // skip noise on canvases over ~1M pixels

// --- plumbing: make hooks look native under introspection ---------
const NATIVE_TS = 'function toString() { [native code] }';
const tsMask = function toString() { return NATIVE_TS; };
Object.defineProperty(tsMask, 'toString', { value: tsMask });
function mask(fn, label, arity) {
  try {
    const nativeLabel = 'function ' + label + '() { [native code] }';
    Object.defineProperty(fn, 'name', { value: label });
    Object.defineProperty(fn, 'length', { value: arity });
    const ts = function toString() { return nativeLabel; };
    Object.defineProperty(ts, 'name', { value: 'toString' });
    Object.defineProperty(ts, 'length', { value: 0 });
    Object.defineProperty(ts, 'toString', { value: tsMask });
    Object.defineProperty(fn, 'toString', { value: ts });
  } catch (e) {}
  return fn;
}

// mulberry32: tiny deterministic PRNG
function prng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Deterministic, idempotent LSB-parity noise on a sampled subset of
// pixels (R/G/B only, alpha untouched). Same (SEED,w,h) => same
// output on every call, so all read paths agree within the session.
function parity(buf, w, h) {
  const px = w * h;
  // Tiny canvases (e.g. 1x1 transparency probes): skipping avoids
  // producing impossible artifacts in all-zero transparent data.
  if (px < 256) return;
  const rand = prng(SEED ^ (w * 65599 + h));
  const n = Math.max(4, px >> 6);
  for (let k = 0; k < n; k++) {
    const i = ((rand() * px) | 0) * 4 + ((rand() * 3) | 0);
    buf[i] = (buf[i] & 0xFE) | (rand() < 0.5 ? 0 : 1);
  }
}

// Chrome-style base64 device identifier (32 random bytes)
function fakeId(rand) {
  let s = '';
  for (let i = 0; i < 32; i++) s += String.fromCharCode((rand() * 256) | 0);
  return btoa(s);
}

// --- installInto: apply all hooks against one realm ---------------
// Realms already patched are tracked here in the PARENT realm (a
// WeakSet, not a window global — nothing new for page scripts to see).
const installedRealms = new WeakSet();

function installInto(w) {
  try { if (installedRealms.has(w)) return; } catch (e) { return; }
  try { installedRealms.add(w); } catch (e) {}
  const doc = w.document;
  const nav = w.navigator;

  // --- 1. WebGL: Linux-consistent ANGLE strings -------------------
  try {
    const V = 37445, R = 37446, VER = 0x1F02, SLV = 0x8B8C;
    for (const proto of [w.WebGLRenderingContext,
                         w.WebGL2RenderingContext]) {
      if (!proto) continue;
      const native = proto.prototype.getParameter;
      const fn = function getParameter(param) {
        if (param === V) return VENDOR;
        if (param === R) return RENDERER;
        const v = native.call(this, param);
        if ((param === VER || param === SLV) && typeof v === 'string' &&
            v.indexOf('SwiftShader') !== -1)
          return v.split('SwiftShader').join('Chromium');
        return v;
      };
      proto.prototype.getParameter = mask(fn, 'getParameter', 1);
      if (typeof proto.prototype.readPixels === 'function') {
        const rp = proto.prototype.readPixels;
        const rfn = function readPixels(x, y, ww, h, format, type, dst) {
          const r = rp.apply(this, arguments);
          try {
            if (dst && (dst instanceof w.Uint8Array ||
                        dst instanceof w.Uint8ClampedArray) &&
                ww > 0 && h > 0 && ww * h <= LIMIT) parity(dst, ww, h);
          } catch (e2) {}
          return r;
        };
        proto.prototype.readPixels = mask(rfn, 'readPixels', 7);
      }
    }
  } catch (e) {}

  // --- 2. mediaDevices: believable mic + webcam + speakers --------
  try {
    const md = nav.mediaDevices;
    const MDP = w.MediaDevices && w.MediaDevices.prototype;
    if (md && MDP && typeof MDP.enumerateDevices === 'function') {
      const rand = prng((SEED ^ 0x6D656469) >>> 0);
      const gA = fakeId(rand), gB = fakeId(rand), gC = fakeId(rand);
      const DEVS = [
        ['audioinput', 'Default (Built-in Audio Analog Stereo)',
          'default', gA],
        ['audioinput', 'Built-in Audio Analog Stereo', fakeId(rand), gA],
        ['videoinput', 'HD WebCam: HD WebCam (usb-0000:00:14.0-08)',
          fakeId(rand), gB],
        ['audiooutput', 'Default (Built-in Audio Analog Stereo)',
          'default', gC],
        ['audiooutput', 'Built-in Audio Analog Stereo', fakeId(rand), gC],
      ];
      function mk(d, full) {
        const dev = { deviceId: full ? d[2] : '', kind: d[0],
                      label: full ? d[1] : '', groupId: full ? d[3] : '' };
        const proto = w.MediaDeviceInfo
          ? w.MediaDeviceInfo.prototype : Object.prototype;
        const o = Object.create(proto);
        Object.defineProperties(o, {
          deviceId: { value: dev.deviceId, enumerable: true },
          kind: { value: dev.kind, enumerable: true },
          label: { value: dev.label, enumerable: true },
          groupId: { value: dev.groupId, enumerable: true },
          toJSON: { value: function toJSON() { return dev; } },
        });
        if (w.Symbol && w.Symbol.toStringTag)
          Object.defineProperty(o, w.Symbol.toStringTag,
            { value: 'MediaDeviceInfo' });
        return o;
      }
      // Real Chrome hides deviceId/label/groupId until the kind has
      // been granted; mirror what the real enumeration reveals.
      const nativeEnum = MDP.enumerateDevices;
      const enumFn = function enumerateDevices() {
        return nativeEnum.call(md).then(function (real) {
          const revealed = {};
          for (let i = 0; i < real.length; i++)
            if (real[i] && real[i].deviceId) revealed[real[i].kind] = 1;
          return DEVS.map(function (d) { return mk(d, !!revealed[d[0]]); });
        }).catch(function () {
          return DEVS.map(function (d) { return mk(d, false); });
        });
      };
      Object.defineProperty(MDP, 'enumerateDevices',
        { value: mask(enumFn, 'enumerateDevices', 0), writable: true,
          enumerable: true, configurable: true });
      if (typeof MDP.getUserMedia === 'function') {
        const nativeGUM = MDP.getUserMedia;
        const gum = function getUserMedia(c) {
          return nativeGUM.call(md, c).catch(function (err) {
            const n = err && err.name;
            if (n === 'NotFoundError' || n === 'NotReadableError' ||
                n === 'OverconstrainedError' || n === 'AbortError')
              throw new w.DOMException('Permission denied',
                                       'NotAllowedError');
            throw err;
          });
        };
        Object.defineProperty(MDP, 'getUserMedia',
          { value: mask(gum, 'getUserMedia', 1), writable: true,
            enumerable: true, configurable: true });
      }
    }
  } catch (e) {}

  // --- 3. canvas: fixed-persona LSB noise -------------------------
  try {
    const HC = w.HTMLCanvasElement;
    const C2D = w.CanvasRenderingContext2D;
    if (HC && C2D) {
      const nGetCtx = HC.prototype.getContext;
      const nToURL = HC.prototype.toDataURL;
      const nToBlob = HC.prototype.toBlob;
      const nGID = C2D.prototype.getImageData;
      const kinds = new WeakMap(); // canvas -> context type string
      const getCtx = function getContext(type) {
        const c = nGetCtx.apply(this, arguments);
        if (c) { try { kinds.set(this, String(type)); } catch (e2) {} }
        return c;
      };
      HC.prototype.getContext = mask(getCtx, 'getContext', 1);
      const gid = function getImageData(sx, sy, sw, sh) {
        const img = nGID.apply(this, arguments);
        try {
          if (sw > 0 && sh > 0 && sw * sh <= LIMIT) parity(img.data, sw, sh);
        } catch (e2) {}
        return img;
      };
      C2D.prototype.getImageData = mask(gid, 'getImageData', 4);
      // 2D canvases: perturb the canvas itself (idempotent), then let
      // the native encoder run — toDataURL/toBlob/getImageData agree
      // because parity() is keyed on (SEED, w, h).
      function noisy2d(canvas, ww, h) {
        const c = nGetCtx.call(canvas, '2d');
        const img = nGID.call(c, 0, 0, ww, h);
        parity(img.data, ww, h);
        c.putImageData(img, 0, 0);
      }
      // WebGL canvases: re-encode through a noisy temp 2D canvas (the
      // original context cannot take putImageData).
      function reencode(src, ww, h) {
        const t = doc.createElement('canvas');
        t.width = ww; t.height = h;
        const c = nGetCtx.call(t, '2d');
        c.drawImage(src, 0, 0);
        noisy2d(t, ww, h);
        return t;
      }
      const toURL = function toDataURL() {
        try {
          const k = kinds.get(this);
          const ww = this.width, h = this.height;
          if (k && ww > 0 && h > 0 && ww * h <= LIMIT) {
            if (k === '2d') noisy2d(this, ww, h);
            else return nToURL.apply(reencode(this, ww, h), arguments);
          }
        } catch (e2) {}
        return nToURL.apply(this, arguments);
      };
      HC.prototype.toDataURL = mask(toURL, 'toDataURL', 0);
      const toBlob = function toBlob(callback) {
        try {
          const k = kinds.get(this);
          const ww = this.width, h = this.height;
          const small = k && ww > 0 && h > 0 && ww * h <= LIMIT;
          if (small && k === '2d') noisy2d(this, ww, h);
          else if (small) {
            nToBlob.call(reencode(this, ww, h), callback,
                         arguments[1], arguments[2]);
            return;
          }
        } catch (e2) {}
        return nToBlob.apply(this, arguments);
      };
      HC.prototype.toBlob = mask(toBlob, 'toBlob', 1);
    }
  } catch (e) {}
}

installInto(window);

// --- 4. iframe realms: lazy install on first reach ----------------
// Pages build canvases inside same-origin iframes via
// iframe.contentDocument / contentWindow; patch that realm the
// moment it is touched (before any canvas is drawn).
try {
  const patched = new WeakSet();
  const fproto = window.HTMLIFrameElement.prototype;
  for (const prop of ['contentDocument', 'contentWindow']) {
    const desc = Object.getOwnPropertyDescriptor(fproto, prop);
    if (!desc || !desc.get) continue;
    const nativeGet = desc.get;
    const hooked = function () {
      const v = nativeGet.call(this);
      try {
        const win = v && v.defaultView ? v.defaultView : v;
        if (win && win.document) installInto(win);
      } catch (e) {} // cross-origin: correctly unreachable
      return v;
    };
    Object.defineProperty(fproto, prop,
      { get: mask(hooked, prop, 0), configurable: true });
  }
} catch (e) {}
})();
"""


def build_spoof_js(seed=None):
    """Return injector JS; seed pins the canvas-noise persona."""
    if seed is None:
        seed = 0x5EEDCA70  # fixed persona; rotate explicitly if ever needed
    return (SPOOF_JS
            .replace("__SEED__", str(seed))
            .replace("__VENDOR__", json.dumps(VENDOR))
            .replace("__RENDERER__", json.dumps(RENDERER)))


def install(context):
    """Route HTML responses through a head-injector applying the spoof."""
    snippet = "<script>" + build_spoof_js() + "</script>"

    def _inject(route):
        try:
            resp = route.fetch()
            ctype = (resp.headers.get("content-type") or "").lower()
            if "text/html" not in ctype:
                route.fulfill(response=resp)
                return
            body = resp.text()
            if re.search(r"<head[^>]*>", body, re.I):
                body = re.sub(r"<head[^>]*>",
                              lambda m: m.group(0) + snippet, body, count=1,
                              flags=re.I)
            else:
                body = snippet + body
            route.fulfill(response=resp, body=body,
                          content_type=resp.headers.get("content-type")
                          or "text/html")
        except Exception as e:
            print("[spoof-inject fallback] %r" % (e,), file=sys.stderr)
            try:
                route.continue_()
            except Exception:
                pass

    context.route("http*://*", _inject)
