# Status Helper

You write the same status three or four times: what you did lives in your Claude Code sessions, what you decided lives in Obsidian, what tickets moved lives in Azure DevOps — and then you write it *again* into the Confluence status doc and *again* as a message to your team. Status Helper collapses the redundant half: gather from the first three, match against the doc's existing topics, and show you the exact before/after before writing anything.

## What each source is for

| Source | Authoritative for | Read/write |
|---|---|---|
| **Claude Code transcripts** | What you actually worked on, in your own words | Read-only |
| **Azure DevOps** | Ticket state — what exists, what state, who owns it | Read-only |
| **Obsidian** | Narrative — why something is stuck, what was decided, what isn't ticketed | Read + draft output |
| **Confluence** | The published rollup — existing topics are the match target | Write (after approval) |

None of the three inputs wins outright, and none of them *is* the doc. Where they disagree, that's a gap, and gaps come back to you as questions. Where they describe real work with no home in the doc yet, that becomes a proposed new topic — never added silently.

## Usage

```
/status-helper
```

Or just ask: "run status helper", "weekly status update", "draft my update".

First run walks you through setup and writes `.status-helper/sources.md` (or `~/.status-helper/sources.md`). Every later run reads that config.

## The run

1. **Collect** — transcripts (scoped to configured repos), ADO (WIQL per board), and Obsidian (configured folders), all over the lookback window
2. **Read the doc's existing topics** — table rows or sections, per your configured structure
3. **Map** gathered work onto those topics — matched, new-topic candidate, or noise (dropped)
4. **Build the changeset** — a before/after diff per matched topic, full content for each proposed new topic
5. **Review with you** — the changeset, the gap list (one batched round), and an open question: anything to add that none of the sources caught?
6. **Draft the update message** — printed in chat *and* saved to your vault
7. **Apply only the approved changeset to Confluence** — nothing else on the page is touched
8. **Report** — links, paths, and anything left ambiguous

## What counts as a gap

- **Conflict** — a note or transcript says done, the ticket says Active (or vice versa)
- **Silent movement** — ticket changed state, nothing in notes or transcripts explains why
- **Untracked work** — notes or transcripts describe real work with no ticket
- **Unexplained stall** — ticket active >14 days, untouched everywhere else

Cosmetic differences, personal content, and already-correct tickets are not gaps and won't be raised.

## Configuration

`.status-helper/sources.md` holds transcript scope (`cwd-prefixes`, lookback), ADO org/project/boards, the Obsidian vault path and folders, the Confluence page plus how its topics are structured (`topic-structure`/`topic-key`), and your reporting conventions. Conventions accumulate — tell the skill "always mention X" or "never include Y" and it records it there for future runs.

## Requirements

- `az` CLI with the `azure-devops` extension, logged in
- Atlassian MCP authenticated (`/mcp`) — bundled in this plugin's `.mcp.json`
- An Obsidian vault
- `jq`, for reading Claude Code transcripts

## Guardrails

- ADO and transcripts are never written to
- Confluence is never edited without showing the full before/after changeset and getting explicit approval
- Topics with no proposed change are left untouched; approved edits never rewrite a topic's untouched history
- The vault is only ever written at the configured draft-output path — your existing notes are never edited

## Relationship to pm-assistant

This started as a fork of [pm-assistant](../../../pm-assistant), which does ADO → Confluence without the Obsidian/transcript layers or the topic-matching review. The additive pieces here are kept separable so they can be contributed back upstream as optional sources.
