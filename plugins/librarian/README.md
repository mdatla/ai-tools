# Librarian

A hierarchical memory library plugin for Claude Code. Automatically loads project-specific context when editing files and captures learnings across sessions.

## How It Works

```mermaid
flowchart TD
    Prompt(["User sends a prompt"])
    Prompt --> PromptHook

    PromptHook["librarian-read.sh<br/>── UserPromptSubmit hook ──"]
    PromptHook -->|"LIBRARIAN_ALWAYS_ON=true"| Reminder["Static reminder:<br/>library exists"]
    PromptHook -->|"Not enabled"| Silent["No output"]

    Edit(["Claude edits a file"])
    Edit --> ReadHook

    ReadHook["librarian-read.sh<br/>── PreToolUse hook ──"]
    ReadHook --> EditDone["Claude makes the edit<br/>with library context injected"]

    EditDone --> Learns{"Learned something<br/>worth keeping?"}
    Learns -->|Yes| Scratch[("Append to<br/>.scratch.md")]
    Learns -->|No| Next["Continue working"]
    Scratch --> Next
    Next -->|Session ends| WriteHook

    WriteHook["librarian-write.sh<br/>── Stop hook ──"]
    WriteHook --> Routed[("Learnings saved to<br/>_memory_library/")]

    Routed -.->|"Available next session"| ReadHook

    style PromptHook fill:#2d5a2d,stroke:#5a5a5a,color:#fff
    style ReadHook fill:#2d5a2d,stroke:#5a5a5a,color:#fff
    style WriteHook fill:#2d3a5a,stroke:#5a5a5a,color:#fff
    style Scratch fill:#5a4a2d,stroke:#5a5a5a,color:#fff
    style Routed fill:#5a4a2d,stroke:#5a5a5a,color:#fff
```

### `librarian-read.sh` — loads context before edits + optional prompt reminder

**Before Edit/Write (PreToolUse):** Walks **up** the `_memory_library/` tree from the file being edited, collecting all `.md` files along the way. Injects them into Claude's conversation so it has full project context before making changes.

Example: editing `src/api/auth.py` loads:
1. `_memory_library/src/api/*.md` (most specific)
2. `_memory_library/src/*.md`
3. `_memory_library/*.md` (most general)

**On every prompt (UserPromptSubmit):** If `LIBRARIAN_ALWAYS_ON=true` is set, injects a static one-liner reminder that the library exists. This keeps Claude aware of the library during non-editing tasks. Set it in `.claude/settings.local.json` under `env`, or use `/librarian-setup`.

### `librarian-write.sh` — saves learnings after sessions

Fires automatically when a session ends. Does two things:

1. **Syncs auto-memory**: Scans `~/.claude/projects/.../memory/` for feedback Claude saved during the session and adds it to `.scratch.md` with appropriate tags
2. **Routes scratch entries**: Reads each `## [TAG: path, type: file]` block in `.scratch.md` and appends it to `_memory_library/<path>/<file>.md` (creates the file if it doesn't exist)

## Memory Library Structure

The library mirrors your repo's file tree:

```
_memory_library/
├── patterns.md                    # Repo-wide conventions
├── tech.md                        # Tech stack, commands, setup
├── product.md                     # Business context, domains
├── src/
│   └── api/
│       ├── patterns.md            # API-specific patterns
│       └── edge.md                # API edge cases
└── .scratch.md                    # Pending learnings (gitignored)
```

## Tagging Learnings

During work, Claude writes learnings to `.scratch.md` with routing metadata:

```markdown
## [TAG: src/api, type: edge]
- Auth tokens expire silently — always check response status

## [TAG: global, type: patterns]
- Use `dbt build` not just `compile` for validation
```

| Field | Controls | Examples |
|-------|----------|----------|
| `path` | Target directory | `global` (root), `src/api`, `models/launch/btbi` |
| `type` | Target filename | `patterns`, `tech`, `product`, `troubleshooting`, `edge` |

The stop hook routes `[TAG: src/api, type: edge]` → `_memory_library/src/api/edge.md`.

## Installation

```bash
/plugin install librarian
/reload-plugins
```

Hooks activate automatically. Run the setup skill to configure your library:

```bash
/librarian-setup                   # choose location, optionally import existing memory bank
```

## Skills

| Skill | Purpose |
|-------|---------|
| `/librarian read <path>` | Show all library context for a file path |
| `/librarian update` | Process pending scratch entries now |
| `/librarian status` | Show library stats |
| `/librarian-setup` | Configure library path, optionally import existing memory bank |

## Debug Logging

Hooks log to `~/.claude/librarian.log`. Toggle at the top of each `.sh` script:

```bash
LIBRARIAN_LOG_ENABLED=true   # false to disable
```

```
[03:39:53] [read]  Triggered for: src/api/auth.py
[03:39:53] [read]  Injecting context: 4 files
[03:40:01] [write] Phase 1: Synced auto-memory 'Always run dbt build' (feedback -> patterns)
[03:40:01] [write] Phase 2: Routed 3 entries -> _memory_library/src/api/edge.md
```

## Plugin Structure

```
plugins/librarian/
├── .claude-plugin/plugin.json        # Manifest
├── hooks/hooks.json                  # Hook config (PreToolUse + Stop + UserPromptSubmit)
├── scripts/
│   ├── librarian-read.sh     # Context injection + prompt reminder
│   ├── librarian-write.sh    # Auto-memory sync + routing
│   └── setup.sh              # Standalone setup (without plugin)
├── skills/
│   ├── librarian/SKILL.md           # Core skill
│   └── librarian-setup/SKILL.md      # Setup + import skill
└── README.md
```

## Requirements

No external dependencies. Scripts use only native shell (`bash`/`grep`/`sed`/`awk`). Requires `bash` (available on macOS, Linux, and Windows via Git Bash).
