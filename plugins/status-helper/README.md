# Status Helper

You write the same status four times: notes in Obsidian, updates in Azure DevOps, a section in the Confluence status doc, and a message to your team. Status Helper collapses the last two into the first two.

It reads Obsidian and ADO as **parallel sources of truth**, reconciles them, asks you about only the things that genuinely don't line up, then writes the Confluence update and drafts the message.

## What each source is for

| Source | Authoritative for | Read/write |
|---|---|---|
| **Azure DevOps** | Ticket state — what exists, what state, who owns it | Read-only |
| **Obsidian** | Narrative — why something is stuck, what was decided, what isn't ticketed | Read + draft output |
| **Confluence** | The published rollup | Write (after approval) |

Neither ADO nor Obsidian wins outright. Where they disagree, that's a gap, and gaps come back to you as questions.

## Usage

```
/status-helper
```

Or just ask: "run status helper", "weekly status update", "draft my update".

First run walks you through setup and writes `.status-helper/sources.md` (or `~/.status-helper/sources.md`). Every later run reads that config.

## The run

1. **Read ADO** — WIQL query per configured board, over the lookback window
2. **Read Obsidian** — notes modified in the same window, from the configured folders
3. **Reconcile** — build a gap list: conflicts, silent ticket movement, untracked work, unexplained stalls
4. **Quiz** — one batched round, real gaps only. A clean week asks nothing.
5. **Draft the doc update** — as a delta against the most recent section
6. **Draft the message** — printed in chat *and* saved to your vault
7. **Publish to Confluence** — only after you approve
8. **Report** — links, paths, and anything left ambiguous

## What counts as a gap

- **Conflict** — note says done, ticket says Active
- **Silent movement** — ticket changed state, no note explains why
- **Untracked work** — notes describe real work with no ticket
- **Unexplained stall** — ticket active >14 days, untouched in notes
- **Blank** — in scope for the update, but neither source says anything current

Cosmetic differences, personal notes, and already-correct tickets are not gaps and won't be raised.

## Configuration

`.status-helper/sources.md` holds ADO org/project/boards, the Obsidian vault path and folders, the Confluence page, and your reporting conventions. Conventions accumulate — tell the skill "always mention X" or "never include Y" and it records it there for future runs.

## Requirements

- `az` CLI with the `azure-devops` extension, logged in
- Atlassian MCP authenticated (`/mcp`) — bundled in this plugin's `.mcp.json`
- An Obsidian vault

## Guardrails

- ADO is never written to
- Confluence is never edited without showing you the draft first
- Past sections of the status doc are never rewritten
- The vault is only ever written at the configured draft-output path — your existing notes are never edited

## Relationship to pm-assistant

This is a fork of [pm-assistant](../../../pm-assistant), which does ADO → Confluence without the Obsidian layer or the gap quiz. The Obsidian pieces here are kept additive so they can be contributed back upstream as an optional source.
