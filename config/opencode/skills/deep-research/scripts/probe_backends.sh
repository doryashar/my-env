#!/usr/bin/env bash
# probe_backends.sh — emit the backend precedence list for the agent to fill in.
#
# The agent itself is the only thing that can see its own MCP tool manifest;
# this script just hands it a structured template. The agent inspects its
# tools, marks which MCPs are available, and uses the first available (by
# precedence) for search, always falling back to WebSearch if none.
#
# WebFetch is always used for page retrieval regardless of search provider.
set -euo pipefail

cat <<'EOF'
{
  "precedence": ["exa", "tavily", "perplexity", "firecrawl", "brave", "websearch"],
  "always_use_for_fetch": "webfetch",
  "match_hints": {
    "exa":         ["mcp__exa__", "exa_search", "exa.search"],
    "tavily":      ["mcp__tavily__", "tavily_search", "tavily.search"],
    "perplexity":  ["mcp__perplexity__", "perplexity_ask", "perplexity.search"],
    "firecrawl":   ["mcp__firecrawl__", "firecrawl_search", "firecrawl.search"],
    "brave":       ["mcp__brave__", "brave_search", "brave_web_search"],
    "websearch":   ["WebSearch"],
    "webfetch":    ["WebFetch"]
  },
  "instruction": "For each key in 'precedence', check your tool manifest for any name matching the corresponding 'match_hints' entry. Use the first available. NEVER tell the user to install an MCP — WebSearch alone is sufficient."
}
EOF
