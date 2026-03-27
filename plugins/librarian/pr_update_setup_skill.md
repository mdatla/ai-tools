## Update: Setup skill + configurable library path

### What changed

**New `/librarian-setup` skill** (replaces `/import-library`)

The old import skill only handled importing from an existing memory bank. The new setup skill is the entry point for getting started with the Librarian in any repo:

1. Asks where to store the library (default: `_memory_library/` in repo root, or custom path like `docs/memory_library/`)
2. Saves the path as `LIBRARIAN_PATH` env var in `.claude/settings.local.json` using the built-in `/update-config` skill
3. Optionally imports from an existing memory bank if one is found
4. Creates the directory, `.scratch.md`, and updates `.gitignore`

**Hook scripts now read `LIBRARIAN_PATH`**

Both `librarian-read.sh` and `librarian-write.sh` check the `$LIBRARIAN_PATH` environment variable first. If set and the directory exists, they use it directly. If not set, they fall back to the previous behavior (walk up from the file path for read, use `cwd/_memory_library` for write). This means repos that haven't run setup still work.

**Removed PowerShell scripts**

Confirmed that Claude Code requires Git Bash on Windows, so `bash` is available on all platforms. Dropped `.ps1` scripts and the bash-with-fallback pattern in `hooks.json`. Commands now call `bash` directly.
