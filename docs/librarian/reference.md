# Librarian Technical Reference

Deep reference for how every component works. Read the [Overview](overview.md) first for the "what and why," and the [Setup Guide](setup.md) to get started.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code Session                                     │
│                                                         │
│  User prompt ──► UserPromptSubmit hook                  │
│                  │                                      │
│                  └─► librarian-read.sh                  │
│                      (injects tagging reminder          │
│                       via additionalContext)             │
│                                                         │
│  Edit/Write ──► PreToolUse hook                         │
│                 │                                       │
│                 └─► librarian-read.sh                   │
│                     (walks up _memory_library/,         │
│                      injects scoped .md files           │
│                      via additionalContext)              │
│                                                         │
│  Session end ──► Stop hook                              │
│                  │                                      │
│                  └─► librarian-write.sh                 │
│                      Phase 1: auto-memory → .scratch.md │
│                      Phase 2: .scratch.md → library     │
└─────────────────────────────────────────────────────────┘
```

## Hook Configuration

Source: `plugins/librarian/hooks/hooks.json`

| Hook | Script | Matcher | Timeout | Status message |
|------|--------|---------|---------|----------------|
| UserPromptSubmit | `librarian-read.sh` | *(none — always fires)* | 5s | "Loading library context..." |
| PreToolUse | `librarian-read.sh` | `Edit\|Write` | 5s | "Loading library context..." |
| Stop | `librarian-write.sh` | *(none — always fires)* | 10s | "Syncing learnings to library..." |

### Hook Output Format

Hooks communicate with Claude Code via JSON on stdout:

**UserPromptSubmit** — injects the tagging reminder into model context + shows status to user:
```json
{
  "systemMessage": "Librarian active",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Tag learnings to /path/.scratch.md as: ## [TAG: path, type: file] + bullets."
  }
}
```

**PreToolUse** — injects library files into model context + shows status to user:
```json
{
  "systemMessage": "Librarian injected context",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "[Librarian] Context for src/api/auth.py (files: src/api/edge.md, global/patterns.md):\n--- [src/api/edge.md] ---\n..."
  }
}
```

**Stop** — shows status to user (details go to log file):
```json
{
  "systemMessage": "Librarian updated the library"
}
```

The distinction matters:
- `systemMessage` — shown to the user in the session UI. Does **not** enter model context.
- `additionalContext` — injected into the model's context window. This is how library content and the tagging reminder reach Claude.

## Scripts

### `librarian-read.sh`

Handles two completely different code paths depending on whether `file_path` is present in the input JSON.

#### Path 1: UserPromptSubmit (no file_path)

```
stdin (JSON from hook system)
  │
  └─ extract file_path → empty
       │
       └─ LIBRARIAN_PATH set and directory exists?
            ├─ yes → output JSON with tagging reminder in additionalContext
            └─ no  → exit 0 silently
```

The tagging reminder is compact (~15 tokens): just the `.scratch.md` path and the tag format. This fires on every prompt so the model always knows to capture learnings.

#### Path 2: PreToolUse (file_path present)

```
stdin (JSON with file_path from Edit/Write tool)
  │
  └─ extract file_path
       │
       └─ find _memory_library/
            ├─ LIBRARIAN_PATH env var (checked first)
            └─ walk up from file directory (fallback)
                 │
                 └─ compute relative path from project root
                      │
                      └─ walk UP the tree, collecting .md files:
                           _memory_library/src/api/*.md
                           _memory_library/src/*.md
                           _memory_library/*.md
                           │
                           └─ output JSON with all content in additionalContext
```

**Walk-up details:**
- Starts at the file's directory level in the library mirror
- At each level, collects all `.md` files (except `.scratch.md`)
- Moves to parent directory and repeats
- Stops at library root
- If the walk-up doesn't reach root (file is deeply nested), root-level files are loaded separately

**Files list tracking:** As files are collected, their display names are accumulated (e.g. `src/api/edge.md, global/patterns.md`). This list appears in both the `additionalContext` header and the debug log.

### `librarian-write.sh`

Two-phase process at session end.

#### Phase 1: Auto-Memory Sync

```
~/.claude/projects/<encoded-path>/memory/*.md
  │
  └─ for each .md file modified in last 120 minutes (excluding MEMORY.md):
       │
       ├─ parse YAML frontmatter (name, type)
       ├─ skip user-type memories (stay in auto-memory)
       ├─ skip if name already exists in .scratch.md or any library file
       │
       └─ map type and append to .scratch.md:
            feedback  → patterns
            project   → product
            reference → tech
```

This bridges Claude's built-in memory with the Librarian. Feedback and project learnings from auto-memory get routed into the library where they're scoped and reusable.

#### Phase 2: Scratch Routing

```
_memory_library/.scratch.md
  │
  └─ parse line by line:
       │
       ├─ ## [TAG: src/api, type: edge]     → has path + type → route it
       │   - Learning 1                        target: _memory_library/src/api/edge.md
       │   - Learning 2                        appended under "## Session Learnings (YYYY-MM-DD)"
       │
       └─ ## [TAG: src/api]                 → no type → left in .scratch.md
           - Unprocessable without type
```

**Routing mechanics:**
- Creates target directory if it doesn't exist (`mkdir -p`)
- Creates target `.md` file if it doesn't exist (with `# <type>` heading)
- Appends content under a `## Session Learnings (YYYY-MM-DD)` section header
- Entries without a `type:` field are written back to `.scratch.md` for manual processing
- If all entries are routed, `.scratch.md` is emptied

### `setup.sh`

Standalone setup script for use without the plugin framework. Handles:
- OS detection (Darwin/Linux/MINGW)
- Plugin root detection (`CLAUDE_PLUGIN_ROOT` or script location)
- Deep merge of hook config into existing `settings.local.json` using `jq`
- Library directory creation with empty `.scratch.md`

The hook configuration it writes mirrors `hooks/hooks.json` exactly.

## Configuration

### Environment Variables

Set in `.claude/settings.local.json` under `env` (project-local, not committed):

| Variable | Required | Description |
|----------|----------|-------------|
| `LIBRARIAN_PATH` | Yes | Absolute path to `_memory_library/`. Hooks check this first; if not set, they walk up from the file path to find it. |

### Script-Level Settings

At the top of each `.sh` script:

| Variable | Default | Description |
|----------|---------|-------------|
| `LIBRARIAN_LOG_ENABLED` | `true` | Whether to write to `~/.claude/librarian.log` |
| `LIBRARIAN_LOG_FILE` | `~/.claude/librarian.log` | Log file path |

## Memory Library Structure

```
_memory_library/
├── patterns.md                    # Repo-wide conventions
├── tech.md                        # Tech stack, commands, setup
├── product.md                     # Business context, domains
├── src/
│   └── api/
│       ├── patterns.md            # API-specific patterns
│       └── edge.md                # API edge cases
├── models/
│   └── launch/
│       └── tech.md                # Launch model specifics
└── .scratch.md                    # Staging area (gitignored)
```

Files at each level are loaded when Claude edits files in the corresponding repo directory. Global files (root level) are always loaded.

### Standard Tag Types

| Type | Use for |
|------|---------|
| `patterns` | Coding conventions, architecture, naming, testing, workflow |
| `tech` | Setup, commands, dependencies, environment, tool usage |
| `product` | Business context, data sources, domains, users, decisions |
| `troubleshooting` | Error patterns, fixes, workarounds, gotchas |
| `edge` | Edge cases, surprising behavior, non-obvious constraints |
| *custom* | Any name works — the type becomes the filename |

### Tag Format

```markdown
## [TAG: <path>, type: <filename>]
- Learning or pattern
- Another insight
```

- `path` — target directory. `global` maps to library root. `src/api` maps to `_memory_library/src/api/`.
- `type` — target filename without `.md`. `edge` creates/appends to `edge.md`.

## Skills

| Skill | User-invocable | Purpose |
|-------|---------------|---------|
| `/librarian [prompt]` | Yes | Read context for a path, process scratch, check status |
| `/librarian-setup` | Yes | Configure library path, import memory bank |
| `/librarian-help` | Yes | Usage guide, troubleshooting, tips |

## Debug Log

Location: `~/.claude/librarian.log`

Log entries are prefixed with `[read]` or `[write]` to identify which script produced them.

```
[2026-04-15 09:14:02] [read]  Hook fired
[2026-04-15 09:14:02] [read]  No file_path (prompt hook), injecting tagging reminder
[2026-04-15 09:14:15] [read]  Hook fired
[2026-04-15 09:14:15] [read]  File: src/api/auth.py
[2026-04-15 09:14:15] [read]  Using configured LIBRARIAN_PATH: /repo/_memory_library
[2026-04-15 09:14:15] [read]  Injecting 3 files for src/api/auth.py: src/api/edge.md, src/api/patterns.md, global/tech.md
[2026-04-15 09:20:44] [write] Hook fired
[2026-04-15 09:20:44] [write] Using configured LIBRARIAN_PATH: /repo/_memory_library
[2026-04-15 09:20:44] [write] Phase 1: Scanning /home/user/.claude/projects/-repo/memory
[2026-04-15 09:20:44] [write] Phase 1: Synced 'always run dbt build' (feedback -> patterns)
[2026-04-15 09:20:44] [write] Phase 2: Processing scratch
[2026-04-15 09:20:44] [write] Phase 2: Routed 2 entries -> _memory_library/src/api/edge.md
[2026-04-15 09:20:44] [write] Done (synced: 1, routed: 2)
```

## Edge Cases

**File outside project scope:** If the edited file's path can't be made relative to the project root, the hook exits silently. No context is injected, no error.

**No library found:** If `LIBRARIAN_PATH` isn't set and no `_memory_library/` is found walking up from the file, the hook exits silently.

**Large context:** The hook system caps injected output at 10,000 characters. If context exceeds this, it's saved to a file and replaced with a preview + file path.

**Duplicate learnings:** Phase 1 of the write hook checks if a learning name already exists in `.scratch.md` or any library `.md` file before syncing. This prevents the same auto-memory entry from being synced repeatedly across sessions.

**Legacy scratch entries:** Entries tagged without a `type:` field (e.g. `## [TAG: src/api]`) cannot be routed and are left in `.scratch.md`. Add a `type:` to process them.

**Empty scratch:** If `.scratch.md` is empty or missing, Phase 2 exits immediately. The "Librarian updated the library" status message still appears.

## Plugin Structure

```
plugins/librarian/
├── .claude-plugin/plugin.json        # Manifest (v2.2.1)
├── hooks/hooks.json                  # Hook config
├── scripts/
│   ├── librarian-read.sh             # Context injection + tagging reminder
│   ├── librarian-write.sh            # Auto-memory sync + scratch routing
│   └── setup.sh                      # Standalone setup (without plugin)
├── skills/
│   ├── librarian/SKILL.md            # Core skill
│   ├── librarian-setup/SKILL.md      # Setup + import skill
│   └── librarian-help/SKILL.md       # Help + troubleshooting skill
└── README.md
```
