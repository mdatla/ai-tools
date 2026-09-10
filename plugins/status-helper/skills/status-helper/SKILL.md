---
name: status-helper
description: De-dupes status reporting by reading Claude Code transcripts, Obsidian notes, and Azure DevOps as sources of truth, matching gathered work against the existing topics in a Confluence project-status doc, and reviewing the proposed changes — updates to existing rows and any new rows to add — with the user before writing anything. Also drafts an update message. Use for "run status helper", "status update", "weekly status", "update the status doc", "draft my update", "what's the project status", or first-time setup of the sources-of-truth config.
---

# Status Helper

You write the same status three or four times: what you actually did lives in your Claude Code sessions, what you decided lives in Obsidian notes, what tickets moved lives in Azure DevOps — and then you write it *again* by hand into the Confluence status doc and *again* as an update message. This skill collapses the redundant part: gather from the first three, match against what the doc already tracks, and show you exactly what would change before anything is written.

**Three sources feed the picture. None of them are the doc:**

- **Claude Code transcripts** — what you actually worked on, in your own words, including asks that never became a ticket or a note.
- **Azure DevOps** — ticket state: what exists, what state it's in, who owns it.
- **Obsidian** — narrative: why something is stuck, what was decided, what isn't ticketed yet.

**The Confluence doc is read first, not written first.** It already has topics — rows in a table, or named sections, depending on how the doc is structured. The job is to match gathered work against those existing topic names, propose an update to each one that has movement, and propose a **new topic** for anything real that has no home yet. Nothing gets written until the user has seen the actual before/after and signed off.

**Direction of writes:** ADO is read-only. Transcripts are read-only. This skill writes to Confluence (after approval) and to the vault (draft message only, never touching existing notes).

## Configuration: the sources-of-truth doc

All configuration lives in `.status-helper/sources.md` in the working directory, or `~/.status-helper/sources.md` as a fallback. Read it at the start of every run.

**If it doesn't exist, run First-Time Setup below.**

The doc has this shape:

```markdown
# Status Helper — Sources of Truth

## Claude Code transcripts
- cwd-prefixes: <comma-separated absolute paths; only sessions under these count as work>
- lookback-days: 14
- notes: <anything about which repos/projects to include or exclude>

## Azure DevOps
- organization: https://dev.azure.com/<org>
- project: <project>

## Boards
<!-- One entry per board/backlog that feeds the status doc -->
- name: <human name, e.g. "Data Platform">
  team: <team name>            # optional, for board-level queries
  area-path: <Area\Path>       # and/or an iteration path
  query: <WIQL or saved query id>   # optional override; if set, use this instead of area/team
  notes: <anything about how to interpret this board>

## Obsidian
- vault: <absolute path to the vault>
- folders: <comma-separated folders to read, e.g. Daily, Notes>
- lookback-days: 14
- draft-output: <path within the vault where drafted messages are saved>
- notes: <naming conventions, e.g. "meeting notes are Notes/Meeting - <who> - <n>.md">

## Status doc (Confluence)
- url: <Confluence page URL>
- space: <space key>
- topic-structure: <how topics are represented, e.g. "one row per topic in the table under 'Projects'" or "one H2 section per topic">
- topic-key: <what identifies a topic, e.g. "first column of the table" or "the H2 heading text">
- cadence: weekly
- notes: <other structure conventions — status columns, macros used, etc.>

## Reporting conventions
<!-- filled in as we learn: what counts as "done" states, what to highlight,
     who reads this doc, tone, what to always/never include -->
```

## First-Time Setup

Walk through this conversationally, one piece at a time:

1. **az CLI**: confirm the `azure-devops` extension (`az extension list --query "[].name" -o tsv`; add via `az extension add --name azure-devops` if missing). Confirm login with `az account show`; if not logged in, ask the user to run `! az login`.
2. **Org and project**: ask, then set defaults: `az devops configure --defaults organization=... project=...`.
3. **Boards**: ask which board(s) are the SOT. Help discover them: `az devops team list -o table`, then for a team `az boards area team list --team "<team>" -o table`. For each board, record name + team/area-path. Verify each with a test query before saving it.
4. **Obsidian vault**: discover vaults from `~/Library/Application Support/obsidian/obsidian.json` (macOS) and offer the list. Ask which folders hold work notes — default to `Daily` and `Notes`. Ask where drafted messages should be saved in the vault. Verify by listing a few recent notes back to the user.
5. **Claude Code transcripts**: ask which repos/working directories count as work for this doc (e.g. everything under `~/Code/repos`) — record as `cwd-prefixes`. Verify with a quick scan and show a couple of matched session snippets back.
6. **Status doc**: ask for the Confluence page URL. Fetch it via the Atlassian MCP to confirm access. Read its actual structure and ask the user to confirm: is a "topic" a table row, or a section heading? Which field is the topic name? Record `topic-structure` and `topic-key` precisely — this is what makes matching possible later. If the Atlassian MCP isn't authenticated, ask the user to run `/mcp` and authenticate `atlassian`. If the doc doesn't exist yet, offer to create it (ask for space + parent page + desired topic structure).
7. **Write the sources doc** with everything gathered, show it to the user, and confirm.

When the user later shares details about doc format or reporting conventions, **update the sources doc** so future runs pick them up.

## The Run

### Step 1: Collect from all three sources

Run these independently (order doesn't matter, but do them before touching Confluence):

**Claude Code transcripts:**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/collect-transcripts.sh" <lookback-days> <cwd-prefix-1> [cwd-prefix-2 ...]
```

Read for what was actually worked on: the human asks (real signal) and the assistant's own text summaries (skip thinking/tool-use noise — the script already strips it). This surfaces work that never made it into a ticket or a note at all.

**Azure DevOps**, for each configured board:

```bash
az boards query --wiql "
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State],
       [System.AssignedTo], [System.IterationPath], [System.ChangedDate]
FROM WorkItems
WHERE [System.AreaPath] UNDER '<area-path>'
  AND [System.State] <> 'Removed'
  AND [System.ChangedDate] >= @Today - 14
ORDER BY [System.State], [System.ChangedDate] DESC" -o json
```

Pull items that closed since the last update and items still open. Use `az boards work-item show --id <id>` when detail on a specific item matters.

**Obsidian:**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/collect-notes.sh" "<vault>" <lookback-days> Daily Notes
```

Read for work claims, blockers/decisions (the *why* neither ADO nor a transcript usually carries), ticket references, and untracked work.

### Step 2: Read the Confluence doc's existing topics

Fetch the page via the Atlassian MCP. Using `topic-structure`/`topic-key` from the sources doc, extract the list of **existing topic names** exactly as they appear — table rows, section headings, whatever the doc actually uses. This list is the join key for the next step. Also capture each topic's current content, so a diff is possible.

### Step 3: Map gathered work onto topics

For everything collected in Step 1, match it to an existing topic name by keyword/semantic similarity (project name, repo name, epic name, ticket area path, etc.). Group into three buckets:

- **Matched** — work maps cleanly onto an existing topic. Build its proposed updated content.
- **New topic candidate** — real, substantive work with no reasonable match to any existing topic. Draft a proposed new row/section for it.
- **Unmatched noise** — trivial or ambiguous items not worth surfacing (a one-off aside, a personal note, a transcript exchange with no concrete outcome). Drop these silently.

While mapping, also build the gap list — same as before, now checked across three sources instead of two:

| Gap | Signal |
|---|---|
| **Conflict** | Sources disagree on state (note/transcript says done, ticket is Active, or vice versa) |
| **Silent movement** | Ticket changed state with nothing in notes or transcripts explaining it |
| **Untracked work** | Notes or transcripts describe real work with no matching ticket |
| **Unexplained stall** | Ticket active >14 days, untouched in notes or transcripts |

Do **not** raise cosmetic wording differences, personal content, or anything the reporting conventions say to skip.

### Step 4: Build the proposed changeset

For every matched topic with real movement, produce a **before → after** diff of that row/section's content — not a rewrite of the whole doc, a targeted change. For every new-topic candidate, produce the proposed new row/section in full, clearly labeled as new. Topics with no movement this period are left out of the changeset entirely — don't touch what didn't change.

### Step 5: Review with the human

This is the core checkpoint — nothing from Step 4 is written yet. Present:

1. **The changeset**, topic by topic: current content next to proposed content for existing topics, and the full proposed content for each new-topic candidate, clearly marked `NEW`.
2. **The gap list** from Step 3, batched into a single round via AskUserQuestion where the answer is a choice, plain text where it's open-ended. Give the evidence from each source so the user doesn't have to go look. Offer a concrete best guess as the first option.
3. **An open invitation to add anything**: after the changeset and gaps, explicitly ask if there's anything to add, correct, or reprioritize that none of the three sources caught — context that only lives in the user's head counts too.

Fold anything the user adds directly into the changeset before moving on. If there are no gaps and no changes to propose, say so plainly — a quiet doc means a quiet run.

Do not proceed to Step 6 without explicit approval of the final changeset.

### Step 6: Draft the update message

Separately from the doc, draft a short human-readable update message — the kind you'd post to a channel or send to a lead. Shorter and more narrative than the doc: what moved, what's blocked, what's needed from others, and call out any brand-new topics explicitly. Lead with anything that requires someone else to act.

Do both of these:

1. **Print it in the chat** in a fenced block so it can be copied straight out.
2. **Save it to the vault** at the `draft-output` path from the sources doc, stamped with the date. Create parent folders if needed. Tell the user the path.

### Step 7: Apply the approved changeset to Confluence

Write exactly what was approved in Step 5 — updates to the matched topics' rows/sections, and new rows/sections for approved new-topic candidates — using the same `topic-structure` conventions read in Step 2. Confluence storage format is XHTML — don't inject raw markdown. Never touch a topic that wasn't part of the approved changeset, and never delete or rewrite historical content within a topic unless the user explicitly asked for that edit.

### Step 8: Report

Link the updated page, name the file the draft message was saved to, and summarize what changed — which topics were updated, which were added. List anything still ambiguous (mislabeled states, unassigned items, work with no ticket) as suggestions. Do not modify work items.

## Guardrails

- ADO and transcripts are read-only. Never create, update, or close work items, and never write back into a transcript.
- Never write to Confluence without showing the full before/after changeset and getting explicit approval.
- Never touch a topic that had no proposed change, and never rewrite a topic's history beyond the approved edit.
- Only ever write into the vault at the configured `draft-output` path — never edit the user's existing notes.
- Batch all gap questions into one round; always give the user a final open chance to add detail before publishing.
- If the sources doc and reality disagree (board gone, page moved, vault path stale, topic structure changed), stop and reconcile the sources doc with the user first.
