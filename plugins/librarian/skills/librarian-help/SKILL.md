---
name: librarian-help
description: >
  Answers questions about how the Librarian plugin works, how to use it effectively,
  and how it integrates with Claude's built-in memory. Covers hooks, logs, tagging,
  and troubleshooting.
  Triggered by phrases like "how does librarian work", "librarian help",
  "help with librarian", "how to use librarian", "librarian docs",
  "librarian documentation", "librarian faq", "librarian troubleshooting".
user-invocable: true
argument-hint: "[question]"
---

# Librarian Help

You are answering questions about the Librarian plugin. Use the reference below to give clear, accurate answers. Keep responses concise — point to logs or files when the user needs to dig deeper.

## What is the Librarian?

The Librarian is a **hook-driven memory system** that gives Claude persistent, hierarchical context about your codebase. It stores learnings in `_memory_library/` which mirrors your repo's file tree, so context is scoped to the area you're working in.

## How It Works — The Three Hooks

The Librarian runs via three hooks that fire **automatically every time** — no manual invocation needed:

| Hook | When it fires | What it does |
|------|--------------|-------------|
| **UserPromptSubmit** | Every prompt you send | Injects a reminder to tag learnings to `.scratch.md` so the model captures knowledge during regular work |
| **PreToolUse** (Edit/Write) | Every time Claude edits a file | Walks up `_memory_library/` from the file being edited, injecting all relevant `.md` context so Claude has full project knowledge before making changes |
| **Stop** | Every session end | Phase 1: Syncs Claude's auto-memory entries into `.scratch.md`. Phase 2: Routes tagged scratch entries to their target library files |

### The hooks fire every time. You do not need to invoke `/librarian` for them to work.

The `/librarian` skill is for manual operations (reading context, processing scratch, checking status). The hooks handle the automatic read/write cycle.

## Compatibility with Claude's Built-in Memory

The Librarian **complements** Claude's built-in auto-memory system — they are not in conflict:

- **Claude's auto-memory** (`~/.claude/projects/.../memory/`): Stores user preferences, feedback, project context. Scoped to the Claude session.
- **Librarian's library** (`_memory_library/`): Stores technical knowledge scoped to your repo's file tree. Persists in your repo (committable, shareable).

**How they connect:** The Stop hook automatically syncs relevant auto-memory entries (feedback, project, reference types) into `.scratch.md`, which then gets routed into the library. User-type memories are left in auto-memory where they belong.

## Creating Breadcrumbs (Tagging)

During work, append learnings to `_memory_library/.scratch.md`:

```markdown
## [TAG: src/api, type: edge]
- Auth tokens expire silently — always check response status

## [TAG: global, type: patterns]
- Use `dbt build` not just `compile` for validation
```

**Tag format:** `## [TAG: <path>, type: <filename>]`
- `path`: Where in the library (`global` for root, or a relative path like `src/api`)
- `type`: Target filename without `.md` — e.g. `patterns`, `tech`, `edge`, `troubleshooting`, `product`

The Stop hook routes these entries to `_memory_library/<path>/<type>.md` automatically.

### What to tag
- Non-obvious patterns, gotchas, design decisions
- Dependencies between components
- Configuration quirks, validation rules
- Anything you'd want to know next time you touch this area

### What NOT to tag
- Things already in the library (check first)
- Trivial facts derivable from the code
- Exact code snippets (the code is the source of truth)

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/librarian [prompt]` | Read context, process scratch, check status, or ask about the library |
| `/librarian-setup` | Configure library path, import existing memory bank, enable always-on mode |
| `/librarian-help [question]` | This help — how to use the Librarian effectively |

## Where to Find Logs

All hook activity is logged to:

```
~/.claude/librarian.log
```

Example log output:
```
[2026-04-14 03:39:53] [read]  Hook fired
[2026-04-14 03:39:53] [read]  File: src/api/auth.py
[2026-04-14 03:39:53] [read]  Injecting 4 files for src/api/auth.py: global/patterns.md, global/tech.md, src/api/patterns.md, src/api/edge.md
[2026-04-14 03:40:01] [write] Phase 1: Synced 'Always run dbt build' (feedback -> patterns)
[2026-04-14 03:40:01] [write] Phase 2: Routed 3 entries -> _memory_library/src/api/edge.md
[2026-04-14 03:40:01] [write] Done (synced: 1, routed: 3)
```

To toggle logging, edit the top of each script:
- `plugins/librarian/scripts/librarian-read.sh` — set `LIBRARIAN_LOG_ENABLED=false`
- `plugins/librarian/scripts/librarian-write.sh` — set `LIBRARIAN_LOG_ENABLED=false`

## Troubleshooting

**"No memory updates are happening"**
- The hooks fire every time, but the model needs to know to write to `.scratch.md`. The UserPromptSubmit hook injects this reminder automatically. If you're not seeing updates, check `~/.claude/librarian.log` to confirm hooks are firing.
- Ensure `LIBRARIAN_PATH` is set in `.claude/settings.local.json` under `env`.

**"I don't see hook output in the session"**
- Hook output uses JSON `systemMessage` format. If you're seeing output in the log but not the session, check that the scripts are outputting valid JSON.
- For live debug output: `tail -f ~/.claude/librarian.log`

**"Context isn't loading before edits"**
- The PreToolUse hook only fires on Edit/Write operations. Check the log for `[read] Hook fired` entries.
- Verify `_memory_library/` exists and has `.md` files at the relevant path level.

## Tips for Effective Use

1. **Tag early and often** — small, specific learnings are more valuable than large dumps
2. **Use the right `type`** — `patterns` for conventions, `edge` for gotchas, `tech` for setup, `product` for business context
3. **Scope paths precisely** — `src/api` is better than `global` when the learning is specific to the API
4. **Review the library periodically** — use `/librarian status` to see what's there, prune stale entries
5. **Commit `_memory_library/`** — it's designed to be version-controlled and shared with your team
