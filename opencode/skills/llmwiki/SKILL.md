---
name: llmwiki
description: Persistent wiki with LLM maintenance - three layers: raw sources, wiki pages, schema
trigger: /llmwiki
---

# /llmwiki

A personal knowledge base built on [Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). The LLM incrementally builds and maintains a structured markdown wiki that sits between you and raw sources.

## Three Layers

1. **raw/** - Immutable source documents (read-only)
2. **wiki/** - LLM-generated markdown pages (LLM writes, you read)
3. **AGENTS.md** - Schema/instructions for the LLM

Two index files:
- **index.md** - Content catalog by category
- **log.md** - Chronological operation log

## Usage

```
/llmwiki <path>                      # Build wiki from sources
/llmwiki <path> --category <name>    # Specify category for ingested files
/llmwiki query "<question>"          # Search wiki and synthesize answer
/llmwiki lint                        # Health-check wiki
/llmwiki stats                       # Show wiki statistics
/llmwiki open                        # Open in Obsidian
/llmwiki watch <path>                # Watch directory, auto-ingest on file changes
```

## Operations

### Ingest - Add new sources

When you add a source, the LLM:
1. Reads the source from raw/
2. Creates summary pages in wiki/
3. Updates index.md with links
4. Updates relevant entity/concept pages
5. Logs the operation to log.md

Example workflow:
```
/llmwiki ./docs/architecture.md
```
This will:
- Copy the file to raw/
- Create a wiki page summarizing it
- Update index.md
- Log to log.md

### Query - Ask questions

The LLM searches the wiki and synthesizes answers. Good answers can be filed back into the wiki as new pages.

### Watch - Auto-ingest on file changes

Start a watcher that monitors a directory for new/modified files and automatically:
1. Copy new files to raw/
2. Create wiki pages in wiki/
3. Update index.md
4. Log to log.md

```
/llmwiki watch ~/code                # Watch your code directory
/llmwiki watch ./notes               # Watch notes directory
```

The watcher runs in the background during the session. Use Ctrl+C to stop.

### Lint - Health check

Checks for:
- Contradictions between pages
- Stale claims superseded by newer sources
- Orphan pages with no inbound links
- Missing cross-references
- Concepts mentioned but lacking pages

## Viewing

Open the wiki folder in Obsidian for:
- Graph view (Cmd+G) - see connections
- Dataview queries over frontmatter
- Rich markdown editing

## What You Must Do

1. If no path given, use `.` (current directory)
2. Create directory structure if missing:
   - `<path>/raw/` - immutable sources
   - `<path>/wiki/` - LLM-maintained pages
   - `<path>/index.md` - content catalog
   - `<path>/log.md` - operation log
   - `<path>/AGENTS.md` - schema
3. On ingest: copy sources to raw/, create wiki pages in wiki/
4. On query: search wiki (index.md + grep), synthesize answer
5. On lint: check for orphans, contradictions, gaps
6. Log every operation to log.md with timestamp

## Integration with Experiment

The wiki is also used for automated experiments via `systems/llmwiki/adapter.py`:
- `search_memory(query)` - returns MemoryResult[]
- `write_memory(content, metadata)` - creates page
- `get_stats()` - returns SystemStats

This allows fair comparison with Graphify and MemPalace using the same interface.