# Output schemas

Every run produces files under `research/<slug>-<YYYY-MM-DD>/`. Validator:
`scripts/validate_outputs.js`.

## Directory

```
research/<slug>-<date>/
├── plan.md                    # always
├── report.md                  # always
├── sources.json               # always
├── evidence.jsonl             # deep mode only
└── agents/                    # standard + deep modes
    ├── agent-1.md
    ├── agent-1.heartbeat
    ├── agent-2.md
    └── agent-2.heartbeat
```

## `plan.md`

```markdown
# Research plan: <query>

- **Date:** 2026-04-21
- **Mode:** standard
- **Backend:** tavily
- **Classifier score:** 2 (reason: breadth-comparison +2)
- **Ambiguous:** false

## Scope

<one-paragraph statement of what the report will and won't cover>

## Sub-questions

1. …
2. …
3. …

## Subagent assignments

- **Agent 1 — <scope>:** sub-questions 1, 2
- **Agent 2 — <scope>:** sub-questions 3
- **Agent 3 — <scope>:** sub-question 4
```

## `report.md`

Freeform markdown. Required:

- Exactly one `#` H1 (the report title).
- Every factual claim ends with an inline URL citation: `… claim ([source](https://url)).`
- Minimum 3 inline citations overall, and at least 1 per 500 words.
- A final `## Sources` section is **optional**; inline citations are the source of truth.
- **No bibliographies.** No "see references below". No "recent reports show…" without a URL.

## `sources.json`

```json
{
  "version": 1,
  "sources": [
    {
      "url": "https://bun.sh/docs",
      "title": "Bun — Docs",
      "fetched_at": "2026-04-21T10:15:00Z",
      "status": 200,
      "agent": 1,
      "notes": "primary source"
    }
  ]
}
```

URLs are normalized on write (`dedup_sources.js`): tracking params stripped,
trailing slashes dropped, fragment removed. Duplicates by normalized URL are
rejected.

## `evidence.jsonl` (deep mode only)

One JSON object per line. Schema:

```json
{"agent": 2, "claim": "Bun ships its own bundler.", "url": "https://bun.sh/docs/bundler", "quote": "Bun's bundler is built on...", "accessed": "2026-04-21T10:20:00Z", "primary": true}
```

Fields:

| Field | Required | Notes |
|---|---|---|
| agent | yes | integer, 1-indexed |
| claim | yes | the assertion being evidenced |
| url | yes | source URL (will be normalized) |
| quote | no | short verbatim excerpt; omit if `--no-quotes` |
| accessed | yes | ISO-8601 timestamp |
| primary | no | boolean; true = paper/spec/vendor doc, false = secondary |

Required fields enforced by `validate_outputs.js`.

## `agents/agent-<N>.md`

Per-subagent workstream file. Must be created **before** the subagent's first
search call (skeleton-first). Skeleton:

```markdown
# Agent <N>: <scope>

## <sub-question 1>

## <sub-question 2>

## Sources
```

Subagents append findings under the H2 sections with inline citations, and
append discovered URLs to `sources.json` via `dedup_sources.js`.

## `agents/agent-<N>.heartbeat`

Append-only file. Each line:

```
<ISO-8601 timestamp> round=<n> lines=<wc-l of agent-N.md> sources=<count of agent's sources>
```

Parent polls this file for stuck-agent detection. See `stop-conditions.md`.
