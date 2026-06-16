# Backend detection

The skill works with whatever search tooling is available, preferring more
capable MCP backends when present.

## Precedence

```
exa → tavily → perplexity → firecrawl → brave → WebSearch
```

`WebFetch` is always used for page retrieval, regardless of which search
provider is chosen.

## Probing

Run `scripts/probe_backends.sh`. It emits a JSON template listing the
precedence order and "match hints" — naming patterns the agent uses to
recognize MCP tools in its manifest.

For each entry in `precedence`, check the agent's tool list for any tool name
that contains one of the corresponding `match_hints` substrings. The first
available tool wins. If no MCP matches, fall back to `WebSearch`.

## Examples of matching tool names

| Backend | Tool name examples |
|---|---|
| exa | `mcp__exa__search`, `mcp__plugin_exa__exa_search` |
| tavily | `mcp__tavily__search`, `tavily_search` |
| perplexity | `mcp__perplexity__perplexity_ask` |
| firecrawl | `mcp__firecrawl__scrape`, `firecrawl_search` |
| brave | `mcp__brave__brave_web_search` |
| websearch | `WebSearch` |

## Rules

1. **Never instruct the user to install an MCP.** `WebSearch` alone is a
   sufficient baseline. Silent fallback is required.
2. **Record the chosen backend** in `plan.md` under a `backend:` key so the
   smoke tests can assert which path was exercised.
3. **Prefer MCP only when it adds value.** If an MCP search tool is rate-limited
   or slow in the current session, fall through to the next entry.
4. **Fetch always uses `WebFetch`.** Firecrawl's scrape capability is a
   last-resort retrieval path, not a primary one, to keep behavior uniform
   across backends.
