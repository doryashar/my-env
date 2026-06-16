# Stop conditions

## Per-mode quality bars

| | quick | standard | deep |
|---|---|---|---|
| Total sources (across all agents) | 3–6 | 10–20 | 20–40 |
| Subagents | 1 (inline) | 2–3 | 4–5 |
| Min sources per subagent | 3 | 5 | 6 |
| Max search rounds per subagent | 3 | 5 | 8 |
| Time budget per subagent | 180s | 480s | 900s |
| Total wall time target | 3 min | 10 min | 25 min+ |
| Critique passes | 0 | 1 | up to 3 |

## Hard per-run caps

| Cap | Value | Rationale |
|---|---|---|
| `--max-spawns` | 30 (deep) / 10 (standard) / 1 (quick) | Protects token budget. Deep = 5 researchers × (3 critique loops × 3 personas + 1 re-dispatch). |
| total wall time | 2× the mode target | Anything longer is a sign of runaway loop. |

## Stuck-agent detection (parent-side)

For each dispatched subagent, the parent polls `agents/agent-<N>.heartbeat`.

**Stuck** = last two heartbeat lines have **both**:

- `lines` field unchanged (the agent hasn't written anything new)
- `sources` field unchanged (no new URLs either)

Poll cadence: every 60s. **Two consecutive stuck checks** → kill subagent and
relaunch with partial data pre-loaded as context.

Pseudocode:

```
for each subagent:
  last_lines = -1; last_sources = -1; stuck_count = 0
  while running:
    sleep 60
    hb = tail -n1 agents/agent-N.heartbeat
    if hb.lines == last_lines and hb.sources == last_sources:
      stuck_count += 1
      if stuck_count >= 2:
        kill subagent
        relaunch with partial_data={agent-N.md, sources.json}
        stuck_count = 0
    else:
      stuck_count = 0
      last_lines = hb.lines; last_sources = hb.sources
```

In **degraded mode** (no subagent dispatch), skip stuck detection — the parent
is the agent, and there is nothing to poll. Rely on per-mode time budget.

## Coverage checklist (before synthesis)

Before writing `report.md`, the orchestrator must confirm:

- [ ] Every sub-question in `plan.md` has ≥1 citation across all `agents/*.md`.
- [ ] `sources.json` count ≥ the mode's minimum total.
- [ ] Source normalization has no duplicates (validator will check).
- [ ] (deep) `evidence.jsonl` has ≥1 entry per H2 section of the draft report.

If any check fails, **dispatch a targeted retrieval subagent** with a scope
equal to the missing coverage. Do **not** fill in from memory.

## Critique loop-back (deep only)

Loop back to retrieve one more time iff **any** of:

1. Skeptical Practitioner flags ≥1 `MISSING` on a load-bearing claim.
2. Adversarial Reviewer returns `report_suppresses=true` on any counter-position.
3. Implementation Engineer returns ≥3 `partial`/`no` on a report billed as actionable.
4. `evidence.jsonl` has <2 primary sources per H2 section.

**Hard cap: 3 iterations.** After the third:

- If the **same gap** is flagged across two iterations → move to
  "Known Limitations" and ship.
- If **new gaps** keep appearing → ship with a prominent
  "Research incomplete" note and the unresolved questions listed.
