# Librarian Setup Guide

## Install

```bash
/plugin install librarian
/reload-plugins
```

## Configure

Run the setup skill:

```bash
/librarian-setup
```

This walks you through:
1. Choosing where to create `_memory_library/` (or pointing to an existing one)
2. Saving the path to `.claude/settings.local.json` as `LIBRARIAN_PATH`
3. Optionally enabling always-on mode
4. Optionally importing an existing memory bank
5. Adding `.scratch.md` to `.gitignore`

## Confirm It's Working

After setup, you should see these messages in your session:

| When | Message you'll see |
|------|-------------------|
| Every prompt you send | **"Librarian active"** |
| Every file edit | **"Librarian injected context"** |
| Session end | **"Librarian updated the library"** |

**"Librarian active"** confirms the tagging reminder is reaching the model. This is what causes Claude to automatically capture learnings to `.scratch.md` during regular work — no need to invoke `/librarian` explicitly.

**"Librarian injected context"** confirms library files are being loaded before edits. The full list of injected files is logged to `~/.claude/librarian.log`.

**"Librarian updated the library"** confirms the stop hook ran. Sync and route counts are logged to `~/.claude/librarian.log`.

### Not seeing the messages?

Exit your session and restart with:

```bash
claude -r
```

The `-r` flag resumes with a fresh plugin load. If messages still don't appear, check:

1. Plugin is installed: `/plugins` should list `librarian`
2. `LIBRARIAN_PATH` is set: check `.claude/settings.local.json` for `env.LIBRARIAN_PATH`
3. The library directory exists at the configured path
4. Hooks are registered: check `.claude/settings.local.json` or `.claude/settings.json` for `hooks` entries

Debug log: `~/.claude/librarian.log` — all hook activity is recorded here regardless of whether messages appear in the session.

## Get Help

```bash
/librarian-help
```

Covers how the system works end-to-end, compatibility with Claude's built-in memory, tagging format, troubleshooting, and tips for effective use.

## How It Works (Quick Version)

Three hooks fire automatically every session:

1. **Every prompt** — reminds the model to tag learnings to `.scratch.md`
2. **Every edit** — loads relevant library context from `_memory_library/` (walks up the tree from the file being edited)
3. **Session end** — syncs Claude's auto-memory into `.scratch.md`, then routes tagged entries to their target library files

You write code. The Librarian captures what you learn and feeds it back next time.

## Next Steps

- Edit some files and check `~/.claude/librarian.log` to see context injection in action
- After a session, look at `_memory_library/` to see routed learnings
- Run `/librarian status` to see library stats
- Run `/librarian-help` for the full usage guide
