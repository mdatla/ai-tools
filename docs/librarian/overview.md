# Librarian: Persistent Memory for Claude Code

## The Problem

Claude Code sessions are ephemeral. Every time you start a new session, Claude has no memory of what it learned last time — patterns it discovered, gotchas it hit, design decisions you made together. You end up re-explaining the same context, and Claude re-discovers the same edge cases.

Existing approaches like memory banks (flat markdown files with project context) help, but they have two fundamental issues:

1. **They depend on the model following instructions.** If the prompt doesn't remind Claude to read or update the memory bank, it doesn't happen. This is unreliable.
2. **They don't scale.** A flat file with everything about your project wastes tokens on irrelevant context. When editing an API endpoint, you don't need the CI/CD pipeline docs.

## The Solution

The Librarian is a **hook-driven, hierarchical memory system** for Claude Code. It solves both problems:

**Hooks make it deterministic.** Three hooks fire automatically — no instructions needed, no prompts to remember. The system works whether you think about it or not.

**Hierarchy makes it efficient.** The memory library mirrors your repo's file tree. When Claude edits a file, it only loads context relevant to that area of the codebase — not the entire project.

## How It Works

```
You send a prompt
    |
    v
[UserPromptSubmit hook] -- reminds Claude to tag learnings
    |
    v
Claude works on your task
    |
    v
Claude edits a file
    |
    v
[PreToolUse hook] -- injects library context scoped to that file
    |
    v
Claude makes the edit with full project context
    |
    v
Session ends
    |
    v
[Stop hook] -- syncs auto-memory, routes tagged learnings to library files
    |
    v
Next session -- learnings are available automatically
```

### The Three Hooks

| Hook | Fires when | What it does |
|------|-----------|-------------|
| **UserPromptSubmit** | Every prompt | Injects a reminder into Claude's context to tag learnings to `.scratch.md` during work |
| **PreToolUse** | Every Edit/Write | Walks up `_memory_library/` from the file being edited, loads all relevant `.md` files into context |
| **Stop** | Session ends | Syncs Claude's auto-memory into `.scratch.md`, then routes tagged entries to their permanent library files |

The hooks fire every time. You never need to invoke `/librarian` for the system to work — it runs in the background.

### Hierarchical Context Loading

The library mirrors your repo structure:

```
_memory_library/
├── patterns.md              # Repo-wide conventions
├── tech.md                  # Tech stack, setup
├── src/
│   └── api/
│       ├── patterns.md      # API-specific patterns
│       └── edge.md          # API edge cases
└── models/
    └── launch/
        └── tech.md          # Launch model specifics
```

When Claude edits `src/api/auth.py`, it loads:
1. `_memory_library/src/api/*.md` (most specific)
2. `_memory_library/src/*.md`
3. `_memory_library/*.md` (most general)

This walk-up means Claude gets layered context — global conventions plus area-specific knowledge — without loading irrelevant files from other parts of the repo.

### Learning Capture

During work, Claude tags learnings to `.scratch.md`:

```markdown
## [TAG: src/api, type: edge]
- Auth tokens expire silently — always check response status before parsing

## [TAG: global, type: patterns]
- Use `dbt build` not just `compile` for model validation
```

At session end, the Stop hook routes each entry to its permanent home:
- `[TAG: src/api, type: edge]` goes to `_memory_library/src/api/edge.md`
- `[TAG: global, type: patterns]` goes to `_memory_library/patterns.md`

The AI decides *what* to remember and *where* it belongs. The shell script handles the file mechanics deterministically.

## Compatibility with Claude's Built-in Memory

The Librarian complements Claude's auto-memory — they serve different purposes:

| | Claude's Auto-Memory | Librarian |
|---|---|---|
| **Stores** | User preferences, feedback, project notes | Technical knowledge scoped to files/directories |
| **Location** | `~/.claude/projects/.../memory/` | `_memory_library/` in your repo |
| **Scope** | Per-user, per-machine | Per-repo, shareable, committable |
| **Loaded** | Always in context | Only when editing relevant files |

The Stop hook bridges them: it automatically syncs relevant auto-memory entries (feedback, project, reference types) into `.scratch.md` so they get routed to the library. User-type memories stay in auto-memory where they belong.

## Why Use It

- **Zero effort after setup.** Hooks fire automatically. No commands to remember.
- **Scoped context.** Only loads what's relevant to the file you're editing.
- **Persistent across sessions.** Learnings survive session boundaries.
- **Committable.** `_memory_library/` lives in your repo. Share knowledge across the team.
- **No external dependencies.** Pure bash — works on macOS and Linux out of the box.

## Getting Started

See [Setup Guide](setup.md) to go from zero to a fully working Librarian.
