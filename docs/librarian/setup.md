# Librarian Setup Guide

This guide takes you from zero to a fully working Librarian. Estimated time: 5 minutes.

## Prerequisites

- Claude Code CLI installed
- A git repository you want to add memory to

## Step 1: Add the Plugin Marketplace

If you haven't added the marketplace yet:

```bash
/plugin marketplace add https://github.com/mdatla/ai-tools.git
```

Already have it? Pull the latest version:

```bash
/plugin marketplace update
```

## Step 2: Install the Plugin

```bash
/plugin install librarian
/reload-plugins
```

This registers three hooks that will fire automatically:
- **UserPromptSubmit** — on every prompt
- **PreToolUse** — before every Edit/Write
- **Stop** — when a session ends

## Step 3: Run Setup

```bash
/librarian-setup
```

The setup skill walks you through:

1. **Choose library location** — where to create `_memory_library/` (default: repo root). If you have an existing library, point to it.
2. **Save the path** — writes `LIBRARIAN_PATH` to `.claude/settings.local.json` so hooks know where the library lives.
3. **Import existing memory bank** (optional) — if you have a `_memory_bank/` or similar, the setup skill can migrate it into the hierarchical library format.
4. **Add `.scratch.md` to `.gitignore`** — the scratch file is a staging area, not meant to be committed.

## Step 4: Verify It's Working

After setup, start a new session. You should see these status messages:

| When | Message |
|------|---------|
| Every prompt you send | **"Librarian active"** |
| Every file edit | **"Librarian injected context"** |
| Session end | **"Librarian updated the library"** |

**"Librarian active"** is the most important one. It means the tagging reminder is reaching the model, which is what causes Claude to automatically capture learnings during regular work. You don't need to invoke `/librarian` explicitly.

### Not seeing the messages?

1. Exit your session and restart with a fresh plugin load:

```bash
claude -r
```

2. If messages still don't appear, check these in order:

| Check | How |
|-------|-----|
| Plugin installed | `/plugins` should list `librarian` |
| Path configured | `.claude/settings.local.json` should have `env.LIBRARIAN_PATH` |
| Directory exists | The path in `LIBRARIAN_PATH` should be a real directory |
| Hooks registered | `.claude/settings.local.json` should have `hooks` entries |

3. Check the debug log — all hook activity is recorded here regardless of whether status messages appear:

```bash
cat ~/.claude/librarian.log
```

## Step 5: Use It

Once verified, there's nothing else to do. The Librarian works in the background:

- **Every prompt** — Claude is reminded to tag learnings
- **Every edit** — Claude gets scoped library context automatically
- **Every session end** — learnings are synced and routed to permanent files

### Tagging learnings (how Claude captures knowledge)

During work, Claude appends learnings to `_memory_library/.scratch.md`:

```markdown
## [TAG: src/api, type: edge]
- Auth tokens expire silently — always check response status

## [TAG: global, type: patterns]
- Use `dbt build` not just `compile` for validation
```

The tag format controls where the learning ends up:
- `path` — target directory in the library (`global` = root, or a relative path like `src/api`)
- `type` — target filename without `.md` (e.g. `patterns`, `tech`, `edge`, `troubleshooting`, `product`)

At session end, the Stop hook routes each tagged entry to `_memory_library/<path>/<type>.md`.

### Available skills

| Skill | What it does |
|-------|-------------|
| `/librarian [prompt]` | Read context for a path, process scratch, check status |
| `/librarian-setup` | Re-run setup (change path, import memory bank) |
| `/librarian-help` | How it all works, troubleshooting, tips for effective use |

### Checking the logs

All hook activity is logged to `~/.claude/librarian.log`:

```
[2026-04-15 09:14:02] [read]  Hook fired
[2026-04-15 09:14:02] [read]  No file_path (prompt hook), injecting tagging reminder
[2026-04-15 09:14:15] [read]  Hook fired
[2026-04-15 09:14:15] [read]  File: src/api/auth.py
[2026-04-15 09:14:15] [read]  Injecting 3 files for src/api/auth.py: src/api/edge.md, src/api/patterns.md, global/tech.md
[2026-04-15 09:20:44] [write] Phase 1: Synced 'always run dbt build' (feedback -> patterns)
[2026-04-15 09:20:44] [write] Phase 2: Routed 2 entries -> _memory_library/src/api/edge.md
[2026-04-15 09:20:44] [write] Done (synced: 1, routed: 2)
```

To toggle logging, edit the top of each script in `plugins/librarian/scripts/`:
```bash
LIBRARIAN_LOG_ENABLED=true   # set to false to disable
```

## What to Expect

After a few sessions, your library will start to grow:

```
_memory_library/
├── patterns.md                  # Repo-wide conventions Claude discovered
├── tech.md                      # Tech stack notes, commands
├── src/
│   └── api/
│       ├── patterns.md          # API-specific patterns
│       └── edge.md              # Edge cases Claude hit
└── .scratch.md                  # Staging area (gitignored)
```

Each time Claude edits a file in `src/api/`, it automatically loads `src/api/*.md` plus all parent levels — so it remembers the edge cases and patterns from previous sessions without you having to remind it.

The library is plain markdown in your repo. You can commit it, share it with your team, or edit it by hand.
