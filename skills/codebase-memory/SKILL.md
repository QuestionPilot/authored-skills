---
name: codebase-memory
description: >-
  Query a persistent code knowledge graph via the codebase-memory-mcp CLI (deterministic, local, token-light — no MCP server). Use for code architecture, call graphs, "what calls/uses X", tracing data/impact through a codebase, finding functions/classes/routes by pattern, dead-code, or Cypher queries over code structure — prefer over grep/glob for code discovery on indexed repos (the QuestionPilot monorepo at projects/questionpilot is pre-indexed). Triggers: "what calls X", "trace/impact of X", "where is X defined", "architecture of this repo", "find handlers/routes", "map the call graph", "run a Cypher query on the code". NOT for docs/markdown/mixed-corpus graphs (use graphify) or plain string/error-message search (use grep).
allowed-tools: Bash
---

# codebase-memory — code knowledge graph via CLI

Deterministic, local code-intelligence over a persistent SQLite knowledge graph, driven **entirely from the CLI** — no MCP server registered (saves ~3k always-on tokens per harness; the CLI exposes 14 tools vs 8 over MCP). Binary: `codebase-memory-mcp` (v0.9.0, `~/.local/bin`). Indexes persist at `~/.cache/codebase-memory-mcp/`.

## When to use
Prefer these graph tools over grep/glob for **code** discovery on an indexed repo. For string literals, error messages, or non-code files → grep. For docs/papers/mixed-corpus knowledge graphs → `graphify`.

## Scope / pre-indexed
- `CBM_ALLOWED_ROOT` bounds indexing to the projects workspace, `$AI_CONFIG_DIR/projects` (least-privilege — export it when indexing).
- Pre-indexed: **QuestionPilot monorepo** (root `projects/questionpilot`) — project names are machine-derived from the absolute path; run `list_projects` to confirm the exact name before querying.

## Core commands
`codebase-memory-mcp cli <tool> '<json>'`. Pipe through `jq`/`python3` to trim output → fewer tokens.

```bash
codebase-memory-mcp cli list_projects | jq '.projects[].name'

# (re)index after big changes (.cbmignore excludes minified/vendored bundles)
CBM_ALLOWED_ROOT="$AI_CONFIG_DIR/projects" \
  codebase-memory-mcp cli index_repository '{"repo_path":"/abs/repo"}'

# structural search — label + name pattern
codebase-memory-mcp cli search_graph '{"project":"P","label":"Function","name_pattern":".*Handler.*","limit":10}'

# trace callers/callees (direction: inbound|outbound|both, depth 1-5)
codebase-memory-mcp cli trace_path '{"project":"P","function_name":"Foo","direction":"both"}'

# Cypher (openCypher read subset) — the power tool
codebase-memory-mcp cli query_graph '{"project":"P","query":"MATCH (f:Function) WHERE f.is_exported RETURN f.name,f.complexity ORDER BY f.complexity DESC LIMIT 20"}'

# architecture overview
codebase-memory-mcp cli get_architecture '{"project":"P"}' | jq '{languages,packages,hotspots}'

# read a symbol's source (get qualified_name from search_graph first)
codebase-memory-mcp cli get_code_snippet '{"project":"P","qualified_name":"P.pkg.Foo"}'

# git-diff blast radius
codebase-memory-mcp cli detect_changes '{"project":"P"}'
```

## Graph model (for Cypher)
- **Node labels:** Function, Method, Class, Variable, Module, File, Folder, Route, Section, Project.
- **Function props:** name, qualified_name, file_path, signature, return_type, param_types, complexity, cognitive, is_exported, is_entry_point, is_test, recursive, loop_depth, docstring.
- **Edge types:** CALLS, USAGE, DEFINES, DEFINES_METHOD, IMPORTS, WRITES, THROWS/RAISES, CONTAINS_FILE/FOLDER, FILE_CHANGES_WITH (git co-change), SIMILAR_TO (MinHash), SEMANTICALLY_RELATED (embedding), HTTP_CALLS.
- **Cypher:** MATCH/OPTIONAL MATCH/WHERE/WITH/RETURN/ORDER BY/SKIP/LIMIT/UNWIND/UNION, `[*1..3]` var-length, `count/sum/avg/min/max/collect`, `EXISTS { }`. Read-only. Dead code: `MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() } AND NOT f.is_entry_point RETURN f.name`.

## Gotchas
- **No `semantic_query` tool** in v0.9.0 — embeddings only feed precomputed `SEMANTICALLY_RELATED` edges (reach them via Cypher).
- Each CLI call cold-starts the 273 MB binary (~0.3s + `mem.init`) — fine for occasional queries; batch when you can.
- Raw-JSON args print a deprecation warning (still work); `--args-file <path>` or piped stdin are the forward path.
- Pinned v0.9.0; **re-vet (Deep-tier intake) on any version bump.** Replaced codegraph 2026-07-11 (QUE-428).
