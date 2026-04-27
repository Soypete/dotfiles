---
name: mempalace
description: Semantic memory system with Wing/Room/Drawer hierarchy and SPO hashing
trigger: /mempalace
---

# /mempalace

A semantic memory system using the Palace technique (like ancient Greek orators). Stores verbatim conversations in ChromaDB with semantic routing via SPO (Subject-Predicate-Object) hashing.

## Hierarchy

- **Wing** - Person or project (e.g., "soypete", "experiments")
- **Room** - Topic within a wing (e.g., "auth", "database")
- **Drawer** - Specific memory items

## Usage

```
/mempalace init <path>              # Initialize a palace
/mempalace mine <path>              # Mine project files
/mempalace mine <path> --mode convos  # Mine conversations
/mempalace query "<question>"       # Semantic search
/mempalace stats                    # Show palace statistics
/mempalace wing <name>              # Create/switch to wing
/mempalace room <name>              # Create/switch to room
/mempalace watch <path>             # Watch directory, auto-mine on file changes
```

## Operations

### Watch - Auto-mine on file changes

Start a watcher that monitors a directory for new/modified files and automatically mines them to the palace.

```
/mempalace watch ~/code             # Watch your code directory
/mempalace watch ./projects         # Watch projects directory
```

The watcher runs in the background during the session. On file changes, it automatically runs `mine_project` on the parent directory. Use Ctrl+C to stop.

### Mine - Ingest content

```
mempalace mine ~/projects/myapp     # Project files
mempalace mine ~/chats/ --mode convos  # Conversations
mempalace mine ~/chats/ --mode general  # General content with extraction
```

The miner extracts:
- Code: functions, classes, patterns
- Conversations: decisions, milestones, problems
- General: classifies into categories

### Query - Semantic search

Uses:
- ChromaDB for vector similarity
- SPO hashing for exact matches
- Wing/Room metadata for filtering

### Semantic Routing

MemPalace routes queries based on:
1. Vector similarity (ChromaDB)
2. SPO hashing (exact subject/predicate/object match)
3. Wing/room metadata filtering

## What You Must Do

1. Ensure mempalace is installed: `pip install mempalace`
2. If no path given, prompt user or use current directory
3. Create palace structure if needed:
   - `<path>/.mempalace/` - ChromaDB storage
4. Use mempalace CLI for mining:
   ```
   mempalace mine <path> --mode project
   ```
5. Query uses ChromaDB collection "mempalace_drawers"

## Integration with Experiment

The palace is also used for automated experiments via `systems/mempalace/adapter.py`:
- `search_memory(query, scope, top_k)` - returns MemoryResult[]
- `write_memory(content, metadata)` - stores in ChromaDB
- `link_memory(source, target, relation)` - creates KG edge
- `get_stats()` - returns SystemStats (wings, rooms, drawers)

This allows fair comparison with Graphify and LLMWiki using the same interface.

## Storage

- ChromaDB at `<palace_path>/.mempalace/`
- Knowledge graph in `knowledge_graph.json` (SPO triples)
- Metadata stored in ChromaDB collections

## MCP Server (Optional)

For remote access:
```
mempalace mcp start
```