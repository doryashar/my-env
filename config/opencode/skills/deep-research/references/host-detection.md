# Host detection

The skill runs on two hosts with slightly different dispatch primitives.
Detect before dispatch.

## Signatures

| Host | Signal (tool name present) | Dispatch primitive |
|---|---|---|
| Claude Code | `Task` | `Task(subagent_type=..., prompt=..., description=...)` |
| opencode | `agent` or `subtask` | `agent(...)` (check the host's docs for the exact name) |
| Degraded | neither of the above | Run the subagent contract in the current loop, sequentially, one "subagent" at a time |

## Decision

1. At the start of every run, inspect available tools.
2. Pick the dispatch primitive from the table above.
3. If degraded: standard and deep still produce the same output layout, but
   subagents run **sequentially** inside the main loop and `agent-<n>.md`
   files are created one after another instead of in parallel.
4. Never fail because subagent dispatch is missing — always fall back to
   degraded mode.

## Degraded-mode note

In degraded mode, the stuck-agent detection (heartbeat polling) is not
meaningful because there is only one loop. Skip the detection code path;
rely on the per-mode time budget instead.

## Do not

- Hard-code `Task` expecting Claude Code.
- Tell the user "this skill requires Claude Code" — the skill must degrade.
- Ask the user which host they're on — detect it.
