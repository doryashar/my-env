#!/usr/bin/env node
// validate_outputs.js — schema-check a research run directory.
// Usage: node validate_outputs.js research/<slug>-<date>/
//
// Checks:
//   1. report.md exists and has ≥1 H1
//   2. report.md has ≥1 inline URL citation per 500 words (min 3 total)
//   3. sources.json parses; all entries have url; no duplicate normalized URLs
//   4. If evidence.jsonl exists, every line parses and has {agent, claim, url, accessed}
//   5. plan.md exists
//   6. If agents/ exists, each agent-N.md has at least one H2 and one inline citation

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { normalizeUrl } from "./dedup_sources.js";

function countInlineCitations(md) {
  return (md.match(/\[[^\]]+?\]\(https?:\/\/[^)]+\)/g) || []).length;
}

function countWords(s) {
  return s.split(/\s+/).filter(Boolean).length;
}

function validateReport(dir, errors) {
  const path = join(dir, "report.md");
  if (!existsSync(path)) { errors.push("missing report.md"); return; }
  const md = readFileSync(path, "utf8");
  if (!/^#\s+\S/m.test(md)) errors.push("report.md has no H1");
  const citations = countInlineCitations(md);
  const words = countWords(md);
  const required = Math.max(3, Math.ceil(words / 500));
  if (citations < required) {
    errors.push(`report.md has ${citations} inline URL citations; need ≥ ${required} (1 per 500 words, min 3)`);
  }
  if (/\brecent reports?\b/i.test(md) && citations === 0) {
    errors.push('report.md uses "recent reports" without any inline URL citation — citation drift');
  }
}

function validateSources(dir, errors) {
  const path = join(dir, "sources.json");
  if (!existsSync(path)) { errors.push("missing sources.json"); return; }
  let data;
  try { data = JSON.parse(readFileSync(path, "utf8")); }
  catch (e) { errors.push(`sources.json parse error: ${e.message}`); return; }
  if (!data || !Array.isArray(data.sources)) { errors.push("sources.json missing 'sources' array"); return; }
  const seen = new Set();
  for (const s of data.sources) {
    if (!s.url) { errors.push(`sources entry missing url: ${JSON.stringify(s)}`); continue; }
    const key = normalizeUrl(s.url);
    if (seen.has(key)) errors.push(`duplicate source after normalization: ${key}`);
    seen.add(key);
  }
}

function validateEvidence(dir, errors) {
  const path = join(dir, "evidence.jsonl");
  if (!existsSync(path)) return;
  const lines = readFileSync(path, "utf8").split(/\n/).filter(Boolean);
  for (let i = 0; i < lines.length; i++) {
    let obj;
    try { obj = JSON.parse(lines[i]); }
    catch (e) { errors.push(`evidence.jsonl line ${i + 1} invalid JSON: ${e.message}`); continue; }
    for (const key of ["agent", "claim", "url", "accessed"]) {
      if (!(key in obj)) errors.push(`evidence.jsonl line ${i + 1} missing "${key}"`);
    }
  }
}

function validatePlan(dir, errors) {
  const path = join(dir, "plan.md");
  if (!existsSync(path)) errors.push("missing plan.md");
}

function validateAgents(dir, errors, warns) {
  const agents = join(dir, "agents");
  if (!existsSync(agents)) return;
  for (const name of readdirSync(agents)) {
    if (!name.endsWith(".md") || name.endsWith(".heartbeat")) continue;
    const md = readFileSync(join(agents, name), "utf8");
    if (!/^##\s+\S/m.test(md)) errors.push(`agents/${name} has no H2 sections (skeleton-first violation?)`);
    if (countInlineCitations(md) === 0) errors.push(`agents/${name} has no inline citations — subagent contract requires write-after-search with citations`);
  }
}

function validate(dir) {
  const errors = [];
  const warns = [];

  validatePlan(dir, errors);
  validateReport(dir, errors);
  validateSources(dir, errors);
  validateEvidence(dir, errors);
  validateAgents(dir, errors, warns);

  return { errors, warns };
}

function main() {
  const dir = process.argv[2];
  if (!dir) { console.error("usage: validate_outputs.js <run-dir>"); process.exit(2); }
  if (!existsSync(dir) || !statSync(dir).isDirectory()) { console.error(`not a directory: ${dir}`); process.exit(2); }

  const { errors, warns } = validate(dir);

  for (const w of warns) console.warn(`WARN: ${w}`);
  if (errors.length) {
    for (const e of errors) console.error(`ERROR: ${e}`);
    process.exit(1);
  }
  console.log(`ok: ${dir}`);
}

import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

function isDirectRun() {
  try { return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? ""); }
  catch { return false; }
}

if (isDirectRun()) main();

export { validate, countInlineCitations, countWords };
