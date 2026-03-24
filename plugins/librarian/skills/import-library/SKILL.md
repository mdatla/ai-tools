---
name: import-library
description: >
  Create a _memory_library from an existing memory bank or collection of markdown documentation files.
  This skill should be used when the user wants to import, migrate, or convert an existing memory bank
  into the Librarian's hierarchical memory library format. Trigger phrases include
  'import memory bank', 'create library', 'set up memory library', 'migrate memory bank',
  'initialize library', or 'convert memory bank'.
---

# Import Library

Create a `_memory_library/` from an existing memory bank or markdown documentation source. The resulting library must follow the Librarian's hierarchical structure described below.

## Target Library Structure

The `_memory_library/` mirrors the repository's file tree. Each directory can contain any number of `.md` files with context relevant to that level of the tree:

```
_memory_library/
├── *.md                                 # Global docs (repo-wide patterns, tech stack, etc.)
├── <top-level-folder>/
│   ├── *.md                             # Docs for everything under this folder
│   ├── <project>/
│   │   ├── *.md                         # Docs for this specific project
│   │   ├── src/
│   │   │   ├── *.md                     # Docs for src/ generally
│   │   │   ├── <module-a>/*.md          # Docs specific to module-a
│   │   │   └── <module-b>/*.md          # Docs specific to module-b
│   │   └── config/*.md
│   └── ...
├── .scratch.md                          # Pending learnings (gitignored, auto-managed)
└── ...
```

### How the hierarchy works

The Librarian's hooks read context using a **walk-up** pattern. When editing a file at path `a/b/c/d/file.py`, all `.md` files are loaded walking up from the deepest match to the root:

1. `_memory_library/a/b/c/d/*.md` (most specific)
2. `_memory_library/a/b/c/*.md`
3. `_memory_library/a/b/*.md`
4. `_memory_library/a/*.md`
5. `_memory_library/*.md` (most general / global)

This means:
- **Global knowledge** (tech stack, repo-wide patterns, deployment commands) goes in `_memory_library/*.md` at the root
- **Project-specific knowledge** goes in a mirrored path (e.g., docs about `src/api/` go in `_memory_library/src/api/`)
- **File names** are flexible — use descriptive names like `patterns.md`, `tech.md`, `troubleshooting.md` rather than generic names
- **No rigid templates** — let the content drive which files exist at each level
- **Concise content** — the library stores knowledge, not journals. Remove dates, progress tracking, and ephemeral state

### What belongs at each level

| Level | Example path | Content |
|-------|-------------|---------|
| Global | `_memory_library/patterns.md` | Repo-wide conventions, architecture decisions, shared tooling |
| Global | `_memory_library/tech.md` | Tech stack, dependencies, development setup, deployment commands |
| Folder | `_memory_library/services/*.md` | Patterns shared across all services |
| Project | `_memory_library/services/auth/*.md` | Auth service specifics: API contracts, auth flows, gotchas |
| Module | `_memory_library/services/auth/middleware/*.md` | Middleware-specific patterns, known issues |

## Workflow

### Step 0: Check for Existing Library

Check if `_memory_library/` already exists in the project root.

- If it exists and contains `.md` files: warn the user that a library already exists and ask whether to merge or start fresh
- If it exists but is empty: proceed normally
- If it does not exist: proceed normally

### Step 1: Locate the Memory Bank

Search the current repository for an existing memory bank. Check these locations in order:

1. **Common memory bank paths**:
   - `_memory_bank/`
   - `.memory_bank/`
   - `.github/_memory_bank/`
   - `.github/memory_bank/`
   - `docs/memory_bank/`
   - `.claude/memory/`

2. **Directory name search**: Use Glob to find directories containing "memory" in their name:
   - `**/*memory*/**/*.md` (any folder with "memory" in the path containing .md files)

3. **Reference search**: Search `agents.md`, `CLAUDE.md`, and `README.md` files for references to memory bank locations:
   - Grep for patterns like `memory_bank`, `memory-bank`, `memory bank`, `knowledge base`
   - Extract any file paths mentioned alongside these references

4. **Documentation clusters**: Look for directories that contain 3+ `.md` files that appear to be documentation (not code docs like API references):
   - Check for files with names like `context`, `patterns`, `progress`, `brief`, `tech`, `system`, `product`, `active`

For each candidate found, display:
- The path
- Number of `.md` files
- A brief listing of file names

### Step 2: Confirm Source with User

If one or more candidates were found:
- Present the candidates and ask the user to confirm which one to import
- If multiple candidates exist, ask the user to pick one

If no candidates were found:
- Inform the user that no memory bank was detected in the repository
- Ask for an absolute path to the memory bank directory
- Validate the path exists and contains `.md` files

### Step 3: Analyze the Source

Read all `.md` files in the source memory bank. For each file, determine where it belongs in the hierarchical library:

1. **Scope classification** — map each file to a library level:
   - **Global** (`_memory_library/*.md`): Files about repo-wide patterns, tech stack, product overview, deployment, general conventions
   - **Folder-level** (`_memory_library/<folder>/*.md`): Files that reference a specific top-level directory or group of projects
   - **Project-level** (`_memory_library/<folder>/<project>/*.md`): Files targeting a specific project, service, or package
   - **Module-level** (`_memory_library/<folder>/<project>/<module>/*.md`): Files about a specific module, component, or subdirectory within a project

   To determine scope, look for:
   - References to specific directories, projects, or modules in the content
   - File names that target a specific area (e.g., `e_customer360_context.md` → project-level)
   - Sections that mix global and project-specific info → split them into separate files at the appropriate levels

2. **Content type** — choose a descriptive target file name:
   - Patterns/conventions → `patterns.md`
   - Technical setup/dependencies → `tech.md`
   - Product/business context → `product.md` or `context.md`
   - Troubleshooting → `troubleshooting.md`
   - Learnings/insights → `<topic>_context.md`

3. **Staleness check** — flag files tracking ephemeral state:
   - Active context, progress, current focus, "next steps" → likely stale, recommend skipping
   - Project briefs → may contain useful requirements, but strip temporal language

4. **Content splitting** — if a source file contains knowledge at multiple levels, split it:
   - A file with both "repo-wide deployment commands" and "auth service API patterns" becomes two files: `_memory_library/deployment.md` and `_memory_library/services/auth/patterns.md`

Present a mapping table to the user:

```
| Source File              | Scope            | Target Path                              | Action         |
|--------------------------|------------------|------------------------------------------|----------------|
| techContext.md           | Global           | _memory_library/tech.md                  | Import         |
| systemPatterns.md        | Global           | _memory_library/patterns.md              | Import         |
| activeContext.md         | —                | (skip)                                   | Stale state    |
| progress.md             | —                | (skip)                                   | Stale state    |
| e360_insights.md         | Project          | _memory_library/apps/e360/src/insights/  | Import         |
| troubleshooting.md       | Global           | _memory_library/troubleshooting.md       | Import         |
```

Ask the user to confirm or adjust the mapping before proceeding.

### Step 4: Create the Library

For each confirmed mapping:

1. **Create the mirrored directory structure** under `_memory_library/` — directories must match the actual repo paths they document. Verify the target repo paths actually exist before creating mirrored directories.

2. **Write content** to the target path. When writing, follow these rules:
   - **Condense**: Remove stale dates, timestamps, session-specific references, and progress tracking
   - **Deduplicate**: If the same knowledge appears in multiple source files, write it once at the most appropriate level
   - **Scope correctly**: Each file should only contain knowledge relevant to its level in the hierarchy. If a file at `_memory_library/patterns.md` would contain project-specific info, move that info to the project-level path instead.
   - **Name descriptively**: Use names that reflect the content (`patterns.md`, `tech.md`, `troubleshooting.md`) not the source (`long-term-memory.md`, `systemPatterns.md`)
   - **Keep concise**: The library stores durable knowledge — patterns, decisions, constraints, gotchas — not activity logs or session history

3. **Create** an empty `_memory_library/.scratch.md` file (used by the Librarian's stop hook to accumulate learnings during sessions)

### Step 5: Verify Hooks

The Librarian's pre-tool and stop hooks auto-activate when the plugin is installed — no manual configuration needed. Confirm the plugin is active by checking that the reload output shows hooks are registered.

If the user is running the Librarian standalone (without the plugin system), run the setup script instead:
- macOS/Linux: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"`
- Windows: `powershell "${CLAUDE_PLUGIN_ROOT}/scripts/setup.ps1"`

### Step 6: Update .gitignore

Add `_memory_library/.scratch.md` to `.gitignore` if not already present.

### Step 7: Confirm

Display a summary:
- Number of files created in `_memory_library/`
- Directory tree of the new library
- Hooks status (configured or not)
- Remind the user that the Librarian will now automatically load context before edits and capture learnings on session end

## Error Handling

- **Source path doesn't exist**: Ask the user to verify the path
- **Source contains no .md files**: Inform the user and ask if they meant a different location
- **Permission errors on target**: Suggest checking file permissions
- **Setup script fails**: Check that `jq` is installed and `$CLAUDE_PLUGIN_ROOT` is set
- **Merge conflict with existing library**: Ask user whether to overwrite, merge, or abort for each conflicting file
