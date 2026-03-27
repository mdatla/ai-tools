---
name: librarian-setup
description: >
  Set up the Librarian memory library for a repository. Configures the library path,
  optionally imports from an existing memory bank, and saves settings. This skill should
  be used when the user wants to set up the librarian, initialize a memory library,
  import a memory bank, configure the library path, or get started with the librarian.
  Trigger phrases include 'set up librarian', 'setup library', 'initialize library',
  'import memory bank', 'create library', 'configure librarian'.
---

# Librarian Setup

Set up the Librarian memory library for this repository. Configures where the library lives, optionally imports from an existing memory bank, and saves the path so hooks can find it.

## Workflow

### Step 1: Choose Library Location

Ask the user where they want the memory library to live. Offer these options:

- **`_memory_library/`** in the repo root (default, recommended)
- A custom path the user specifies

The path should be an absolute path to a directory that will contain the library's `.md` files. If the user gives a relative path, resolve it relative to the repo root.

### Step 2: Create the Library Directory

Create the chosen directory if it doesn't exist. Create an empty `.scratch.md` file inside it.

### Step 3: Save the Path

Save the `LIBRARIAN_PATH` environment variable to `.claude/settings.local.json` (the LOCAL settings file, NOT `.claude/settings.json`).

**IMPORTANT**: The path MUST go in `settings.local.json`, not `settings.json`. The `settings.json` file is committed to the repo and shared across the team. Since `LIBRARIAN_PATH` is an absolute path specific to each developer's machine, putting it in the committed file would break other developers' setups.

Use the built-in `/update-config` skill:

```
Add env var LIBRARIAN_PATH=<chosen_path> to .claude/settings.local.json (project local settings, NOT the committed settings.json)
```

Verify the variable was written to the correct file by reading `.claude/settings.local.json` and confirming the `env` field contains `LIBRARIAN_PATH`.

This makes the path available to the hook scripts as `$LIBRARIAN_PATH`. The hooks will use this path instead of walking up the directory tree to find the library.

### Step 4: Search for Existing Memory Bank (Optional)

Search the repository for an existing memory bank that could be imported. Check these locations:

1. **Common paths**: `_memory_bank/`, `.memory_bank/`, `.github/_memory_bank/`, `.github/memory_bank/`, `docs/memory_bank/`, `.claude/memory/`
2. **Directory name search**: `**/*memory*/**/*.md`
3. **Reference search**: Grep `agents.md`, `CLAUDE.md`, and `README.md` for `memory_bank`, `memory-bank`, `memory bank`, `knowledge base`

If a memory bank is found, ask the user if they want to import it. If yes, proceed to Step 5. If no (or none found), skip to Step 6.

### Step 5: Import Memory Bank

Read all `.md` files in the source memory bank. For each file:

1. **Classify scope**: Is it global (repo-wide) or specific to a project/folder?
   - Look for references to specific directories, projects, or modules
   - Files about general patterns, tech stack, or product overview are global
   - Files targeting a specific area go in a mirrored path

2. **Choose target filename**: Use descriptive names based on content type:
   - Patterns/conventions -> `patterns.md`
   - Technical setup -> `tech.md`
   - Product/business context -> `product.md`
   - Troubleshooting -> `troubleshooting.md`

3. **Skip stale files**: Active context, progress, current focus files are usually stale. Recommend skipping them.

4. **Split mixed content**: If a file has both global and project-specific knowledge, split it into separate files at the right levels.

Present a mapping table and ask the user to confirm before writing.

When writing imported content:
- Remove stale dates, timestamps, session-specific references
- Deduplicate across files
- Keep concise: the library stores durable knowledge, not journals
- Use descriptive filenames, not source filenames

### Step 6: Update .gitignore

Add the scratch file path to `.gitignore` if not already present. The scratch file path is `<library_path>/.scratch.md` (relative to repo root).

### Step 7: Confirm

Display a summary:
- Library path (and that it's saved in settings)
- Number of files created
- Directory tree of the new library
- Remind the user that hooks will now automatically load context before edits and capture learnings at session end

## Target Library Structure

The library mirrors the repo's file tree:

```
<library_path>/
├── *.md                                 # Global docs (repo-wide)
├── <folder>/
│   ├── *.md                             # Docs for this folder
│   ├── <project>/
│   │   ├── *.md                         # Docs for this project
│   │   └── <module>/*.md                # Docs for this module
├── .scratch.md                          # Pending learnings (gitignored)
└── ...
```

### What belongs at each level

| Level | Example path | Content |
|-------|-------------|---------|
| Global | `patterns.md` | Repo-wide conventions, architecture, shared tooling |
| Global | `tech.md` | Tech stack, dependencies, setup, deployment |
| Folder | `services/*.md` | Patterns shared across all services |
| Project | `services/auth/*.md` | Auth service specifics, API contracts, gotchas |
| Module | `services/auth/middleware/*.md` | Middleware-specific patterns, known issues |

## Error Handling

- **Path doesn't exist and can't be created**: Check permissions
- **Source memory bank not found**: Ask user for an absolute path or skip import
- **Source contains no .md files**: Ask if they meant a different location
- **Merge conflict with existing library**: Ask whether to overwrite, merge, or skip each conflicting file
- **Settings update fails**: Fall back to manually editing `.claude/settings.local.json`
