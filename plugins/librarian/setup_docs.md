# Librarian Plugin for Claude Code

## What is it

The Librarian is a Claude Code plugin that gives Claude persistent, project-specific memory. It maintains a `_memory_library/` folder in your repo that mirrors your file tree. When Claude edits a file, it automatically receives relevant context from the library. When a session ends, learnings from that session are saved back to the library for next time.

This means Claude remembers patterns, gotchas, and decisions across sessions without you having to repeat yourself.

## Install

### 1. Add the marketplace (one time)

If you haven't already added the Buildertrend AI Tools marketplace:

```
/plugin marketplace add https://github.com/buildertrend/bt-ai-tools.git
```

### 2. Install the plugin

```
/plugin install librarian
/reload-plugins
```

You should see `2 hooks` in the reload output. That confirms the plugin is active.

### 3. Create a memory library in your repo

**Option A: Import from an existing memory bank**

If your repo already has a `_memory_bank/` or similar documentation folder:

```
/import-library
```

This walks you through finding existing docs and converting them to the library format.

**Option B: Start from scratch**

```bash
mkdir _memory_library
```

The library will grow naturally as Claude tags learnings during your sessions.

### 4. Update .gitignore

Add this line to your repo's `.gitignore`:

```
_memory_library/.scratch.md
```

The scratch file is a temporary staging area and should not be committed.

## How it works

The plugin runs two hooks automatically. You do not need to do anything after installation.

**Before every edit:** Claude receives all relevant `.md` files from the library, walking up from the file being edited to the repo root. For example, editing `src/api/auth.py` loads context from `_memory_library/src/api/`, then `_memory_library/src/`, then `_memory_library/`.

**After every session:** The plugin syncs any feedback you gave Claude (saved in Claude's built-in memory) into the library, and routes any tagged learnings from `.scratch.md` to the correct library files.

## Library structure

The library mirrors your repo's folder structure. Each folder can contain any number of `.md` files:

```
_memory_library/
    patterns.md              -- repo-wide conventions
    tech.md                  -- tech stack, commands, setup
    product.md               -- business context
    src/
        api/
            patterns.md      -- API-specific patterns
            edge.md          -- API edge cases
    models/
        launch/
            btbi/
                migration.md -- BTBI migration guide
    .scratch.md              -- temporary staging (gitignored)
```

You can create files manually or let Claude create them through the tagging system.

## Tagging learnings

During a session, Claude will tag things it discovers by appending to `.scratch.md`:

```markdown
## [TAG: src/api, type: edge]
- Auth tokens expire silently, always check response status

## [TAG: global, type: patterns]
- Always run dbt build after creating models
```

The `path` controls which folder in the library. The `type` controls which `.md` file. At session end, these are routed automatically. If the file doesn't exist, it gets created.

Standard types:

| Type | Use for |
|------|---------|
| patterns | Conventions, naming, architecture |
| tech | Commands, setup, dependencies |
| product | Business context, domains |
| troubleshooting | Errors, fixes, workarounds |
| edge | Edge cases, surprising behavior |

## Manual commands

You can interact with the library directly:

| Command | What it does |
|---------|-------------|
| `/librarian read src/api` | Show all library context for a path |
| `/librarian update` | Process scratch entries now |
| `/librarian status` | Show library stats |

## Debug logging

The plugin logs to `~/.claude/librarian.log` with timestamps. This is useful for verifying hooks are firing. To disable logging, edit the `LIBRARIAN_LOG_ENABLED` variable at the top of the `.sh` scripts in the plugin's `scripts/` folder (set to `false`).

Example log:

```
[2026-03-24 03:39:53] [read]  Hook fired
[2026-03-24 03:39:53] [read]  File: models/launch/btbi/contacts_launch.sql
[2026-03-24 03:39:53] [read]  Injecting 6 files for models/launch/btbi/contacts_launch.sql
[2026-03-24 03:40:01] [write] Hook fired
[2026-03-24 03:40:01] [write] Phase 1: Synced 'Always run dbt build' (feedback -> patterns)
[2026-03-24 03:40:01] [write] Phase 2: Routed 3 entries -> _memory_library/models/launch/btbi/patterns.md
```

## Troubleshooting

**Hooks not showing after reload:** Make sure you ran `/reload-plugins` after `/plugin install librarian`. The reload output should show `2 hooks`.

**Context not being injected:** The hook only fires on Edit and Write tools, not Read. It also only works when there is a `_memory_library/` directory somewhere in the path above the file being edited.

**Scratch entries not routing:** Entries need the `type:` field in the tag. Legacy entries like `## [TAG: global]` (without `type:`) will stay in scratch until a type is added.

**Cross-repo edits:** The plugin walks up from the file's actual path to find `_memory_library/`, not from the session's working directory. This means it works correctly when editing files in a different repo.
