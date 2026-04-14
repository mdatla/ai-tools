# Librarian Update Checklist

> **Research confirmed** (2026-04-14): Plugin hooks fire automatically once installed
> (merge with user/project hooks on enable). `statusMessage` is a standard field
> that shows a spinner. `UserPromptSubmit` does NOT support matchers (always fires).
> On exit 0, stdout is added to Claude's context. Output capped at 10,000 chars.

## Change 1: UserPromptSubmit — static library reminder

- [x] **Modify `scripts/librarian-read.sh`** — static reminder when no file_path
  - No file_path + `LIBRARIAN_ALWAYS_ON=true` + LIBRARIAN_PATH exists → inject one-liner reminder
  - No file_path + not always-on → exit 0 silently (unchanged)
  - PreToolUse path unchanged (JSON envelope, walk-up)

- [x] **Update `skills/librarian-setup/SKILL.md`** — add always-on option
  - Ask if user wants `LIBRARIAN_ALWAYS_ON=true` in settings.local.json
  - Enables static library reminder on every prompt
  - Renumber subsequent steps

- [x] **Update `hooks/hooks.json`** — add UserPromptSubmit entry calling same `librarian-read.sh`
  - No matcher needed (UserPromptSubmit doesn't support matchers)
  - timeout: 5, command: same `librarian-read.sh`
  - statusMessage: `"Loading library context..."`

- [x] **Update `scripts/setup.sh`** — sync with hooks.json
  - Add UserPromptSubmit block to `HOOK_CONFIG` heredoc (same READ_CMD)
  - Add statusMessage to all entries

## Change 2: Update /librarian Skill Suggestions

- [x] **Update `skills/librarian/SKILL.md`**
  - Change argument-hint: `"[read|update|status]"` → `"[your prompt/task here]"`
  - Add trigger phrases: "check the library", "what does the library know",
    "library context", "show library", "read library", "memory context",
    "read memory", "show memory", "library status", "update library",
    "process scratch", "sync learnings", "what do we know about"

## Change 3: Hook Messages (`statusMessage`)

- [x] **Add `statusMessage` to all hooks in `hooks/hooks.json`**
  - PreToolUse: `"Loading library context..."`
  - Stop: `"Syncing learnings to library..."`
  - UserPromptSubmit: `"Loading library context..."`

## Documentation

- [x] **Update `README.md`**
  - Update mermaid flowchart (add optional prompt awareness path)
  - Document UserPromptSubmit hook behavior (static reminder)
  - Update hooks.json description to mention UserPromptSubmit
