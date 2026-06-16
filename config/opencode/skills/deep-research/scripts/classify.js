#!/usr/bin/env node
// classify.js — pure function that scores a research query and picks a mode.
// Consumed by both SKILL.md (via `node classify.js "$QUERY"`) and the test
// suite in tests/classifier/. Keep this file dependency-free.

const EXPLICIT_QUICK = [
  /\s--quick\b/i,
  /\bbriefly\b/i,
  /\bjust a quick\b/i,
  /\bquick(ly)? (look|check|peek|answer)\b/i,
  /\btl;?dr\b/i,
  /\bone[- ]liner\b/i,
];

const EXPLICIT_DEEP = [
  /\s--deep\b/i,
  /\bdeep dive\b/i,
  /\bthorough(ly)?\b/i,
  /\bexhaustive(ly)?\b/i,
  /\bcomprehensive\b/i,
  /\bfull (report|survey|landscape)\b/i,
  /\bliterature review\b/i,
];

const EXPLICIT_STANDARD = [
  /\s--standard\b/i,
  /\bstandard (report|analysis|review)\b/i,
  /\bmoderate depth\b/i,
  /\bbalanced (analysis|overview|report)\b/i,
];

// Auto-jump to deep: phrases that by themselves signal deep intent.
const STRONG_DEEP_KEYWORDS = [
  "state of the art",
  "state of the field",
  "historical evolution",
];

// Breadth concepts. Each concept counts at most once so "compare X vs Y" isn't
// double-counted as both "compare" and "vs".
const BREADTH_CONCEPTS = {
  comparison: ["compare", "comparison", " vs ", " versus ", "tradeoffs", "trade-offs", "pros and cons"],
  landscape: ["landscape", "survey", "ecosystem", "state of", "overview of"],
  options: ["options for", "alternatives to"],
};

const DEPTH_KEYWORDS = [
  "history", "evolution", "benchmark", "evaluate", "evaluation",
  "citations", "academic", "paper", "research", "investigate",
  "analyze", "analysis",
];

const FACTOID_KEYWORDS = [
  "what is", "what's", "define", "definition of", "current version",
  "latest version", "release date", "who is", "when did", "when was",
  "how many",
];

function normalize(q) {
  return " " + q.toLowerCase().trim() + " ";
}

function anyMatch(text, patterns) {
  return patterns.some((p) => p.test(text));
}

function containsAny(hay, needles) {
  return needles.some((n) => hay.includes(n));
}

function hasEnumeration(q) {
  // Two or more commas signals a 3+ item list — a multi-dimensional task.
  // Catches both Oxford ("X, Y, and Z") and non-Oxford ("X, Y, Z, W") lists.
  const commas = (q.match(/,/g) || []).length;
  return commas >= 2;
}

function countCapitalNouns(q) {
  const tokens = q.split(/\s+/);
  const stop = new Set([
    "The", "A", "An", "I", "What", "Why", "How", "When", "Where", "Who",
    "Which", "Is", "Are", "Do", "Does", "Can",
  ]);
  const found = new Set();
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i].replace(/[^\w-]/g, "");
    if (!t) continue;
    if (stop.has(t)) continue;
    if (i === 0) continue; // first-word capitalization is noise
    if (/^[A-Z][a-zA-Z0-9-]{1,}$/.test(t)) found.add(t.toLowerCase());
  }
  return found.size;
}

function hasStrongAnchor(q) {
  if (/"[^"]+"/.test(q)) return true;
  if (/'[^']+'/.test(q)) return true;
  if (countCapitalNouns(q) >= 1) return true;
  return false;
}

/**
 * @param {string} query — the user's research request.
 * @returns {{mode: "quick"|"standard"|"deep", score: number, ambiguous: boolean, reason: string, explicit: boolean}}
 */
export function classify(query) {
  const q = query ?? "";
  const nq = normalize(q);
  const wc = q.trim().split(/\s+/).filter(Boolean).length;

  // 1. Explicit overrides win, highest priority.
  if (anyMatch(q, EXPLICIT_QUICK)) {
    return { mode: "quick", score: -99, ambiguous: false, explicit: true, reason: "explicit quick override" };
  }
  if (anyMatch(q, EXPLICIT_DEEP)) {
    return { mode: "deep", score: 99, ambiguous: false, explicit: true, reason: "explicit deep override" };
  }
  if (anyMatch(q, EXPLICIT_STANDARD)) {
    return { mode: "standard", score: 0, ambiguous: false, explicit: true, reason: "explicit standard override" };
  }

  // 2. Strong-deep keywords auto-jump.
  if (containsAny(nq, STRONG_DEEP_KEYWORDS)) {
    return {
      mode: "deep",
      score: 10,
      ambiguous: false,
      explicit: false,
      reason: `strong-deep keyword matched`,
    };
  }

  // 3. Heuristic scoring.
  let score = 0;
  const reasons = [];

  if (wc <= 8) { score -= 2; reasons.push(`short query (${wc}w) -2`); }
  else if (wc > 20) { score += 1; reasons.push(`long query (${wc}w) +1`); }

  // Breadth: each concept at most once.
  for (const [concept, kws] of Object.entries(BREADTH_CONCEPTS)) {
    if (containsAny(nq, kws)) {
      score += 2;
      reasons.push(`breadth-${concept} +2`);
    }
  }

  // Depth: every hit counts.
  const depthHits = DEPTH_KEYWORDS.filter((k) => nq.includes(k));
  if (depthHits.length) {
    score += depthHits.length;
    reasons.push(`depth [${depthHits.join(",")}] +${depthHits.length}`);
  }

  // Factoid: every hit halves the score, doubled weight.
  const factoidHits = FACTOID_KEYWORDS.filter((k) => nq.includes(k));
  if (factoidHits.length) {
    score -= 2 * factoidHits.length;
    reasons.push(`factoid [${factoidHits.join(",")}] -${2 * factoidHits.length}`);
  }

  // Enumeration: "X, Y, and Z" multi-dimensional signal.
  if (hasEnumeration(q)) {
    score += 1;
    reasons.push("enumeration +1");
  }

  // 4. Decide.
  let mode;
  if (score <= -1) mode = "quick";
  else if (score >= 3) mode = "deep";
  else mode = "standard";

  // 5. Ambiguity: soft band 1..2 without a strong anchor → caller should ask.
  const ambiguous = score >= 1 && score <= 2 && !hasStrongAnchor(q);

  return {
    mode,
    score,
    ambiguous,
    explicit: false,
    reason: reasons.join("; ") || "no signals, default standard",
  };
}

// CLI: `node classify.js "your query"` prints JSON.
// Use realpath on both sides so the check fires when the script is invoked
// through a symlink (e.g. ~/.claude/skills/deep-research/scripts/classify.js).
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

function isDirectRun() {
  try {
    return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? "");
  } catch {
    return false;
  }
}

if (isDirectRun()) {
  const query = process.argv.slice(2).join(" ");
  if (!query) {
    console.error("usage: node classify.js <query>");
    process.exit(2);
  }
  console.log(JSON.stringify(classify(query), null, 2));
}
