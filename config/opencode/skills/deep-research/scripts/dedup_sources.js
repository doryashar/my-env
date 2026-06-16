#!/usr/bin/env node
// dedup_sources.js — merge new source entries into sources.json, dedup by
// normalized URL. Usage:
//
//   node dedup_sources.js <sources.json> <new-entries.json>
//
// new-entries.json is an array of {url, title?, fetched_at?, status?, notes?}.

import { readFileSync, writeFileSync, existsSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

function normalizeUrl(u) {
  try {
    const url = new URL(u);
    url.hash = "";
    // strip common tracking params
    for (const p of ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "fbclid", "gclid", "ref", "ref_src"]) {
      url.searchParams.delete(p);
    }
    // normalize trailing slash for path-only URLs
    if (url.pathname === "/") url.pathname = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return u.trim();
  }
}

function load(path) {
  if (!existsSync(path)) return { version: 1, sources: [] };
  const raw = readFileSync(path, "utf8").trim();
  if (!raw) return { version: 1, sources: [] };
  return JSON.parse(raw);
}

function merge(existing, incoming) {
  const byKey = new Map();
  for (const s of existing.sources) byKey.set(normalizeUrl(s.url), s);
  for (const s of incoming) {
    if (!s || !s.url) continue;
    const key = normalizeUrl(s.url);
    const prev = byKey.get(key);
    if (!prev) {
      byKey.set(key, { ...s, url: key });
    } else {
      // merge: incoming (s) provides defaults, first-seen (prev) wins for
      // existing fields. Missing fields in first-seen are filled from incoming.
      byKey.set(key, { ...s, ...prev, url: key });
    }
  }
  return { version: 1, sources: [...byKey.values()] };
}

function main() {
  const [out, incomingPath] = process.argv.slice(2);
  if (!out || !incomingPath) {
    console.error("usage: dedup_sources.js <sources.json> <new-entries.json>");
    process.exit(2);
  }
  const existing = load(out);
  const incoming = JSON.parse(readFileSync(incomingPath, "utf8"));
  const merged = merge(existing, incoming);
  writeFileSync(out, JSON.stringify(merged, null, 2) + "\n");
  console.log(`wrote ${merged.sources.length} sources to ${out}`);
}

function isDirectRun() {
  try { return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? ""); }
  catch { return false; }
}
if (isDirectRun()) main();

export { normalizeUrl, merge };
