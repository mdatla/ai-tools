---
name: status-helper
description: De-dupes status reporting by reading Obsidian notes and Azure DevOps boards as parallel sources of truth, quizzing the user on gaps between them, then updating the Confluence project-status doc and drafting an update message. Use for "run status helper", "status update", "weekly status", "update the status doc", "draft my update", "what's the project status", or first-time setup of the sources-of-truth config.
---

# Status Helper

You write the same status twice — once as notes in Obsidian, once as ticket updates in Azure DevOps — and then have to write it a third time for the Confluence doc and a fourth time as an update message. This skill collapses that: read both sources, reconcile them, ask only about what genuinely doesn't line up, then produce the doc update and the message.

**Two sources, different roles:**

- **Azure DevOps** is the source of truth for *ticket state* — what exists, what state it's in, who owns it.
- **Obsidian** is the source of truth for *narrative* — why something is stuck, what was decided, what isn't ticketed yet.

Neither wins outright. Where they disagree, that's a gap, and gaps go to the user.

**Direction of writes:** boards are read-only. This skill writes to Confluence and to the vault (draft message only), never to ADO.

## Configuration: the sources-of-truth doc

All configuration lives in `.status-helper/sources.md` in the working directory, or `~/.status-helper/sources.md` as a fallback. Read it at the start of every run.

**If it doesn't exist, run First-Time Setup below.**

The doc has this shape:

```markdown
# Status Helper — Sources of Truth

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
- cadence: weekly
- notes: <structure conventions for the doc — section per week, tables used, etc.>

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
5. **Status doc**: ask for the Confluence page URL. Fetch it via the Atlassian MCP to confirm access and learn its structure; record the URL and structure notes. If the Atlassian MCP isn't authenticated, ask the user to run `/mcp` and authenticate `atlassian`. If the doc doesn't exist yet, offer to create it (ask for space + parent page).
6. **Write the sources doc** with everything gathered, show it to the user, and confirm.

When the user later shares details about doc format or reporting conventions, **update the sources doc** so future runs pick them up.

## The Run

### Step 1: Read Azure DevOps

For each board in the sources doc, pull current state. Default query (adjust per board's `query`/`notes`, and set the lookback to match `lookback-days`):

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

Pull items that closed since the last update and items still open, so the rollup can say what shipped, what's in flight, and what's stuck (no changes in >14 days but still active). Use `az boards work-item show --id <id>` when detail on a specific item matters.

### Step 2: Read Obsidian

Collect notes modified within the lookback window:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/collect-notes.sh" "<vault>" <lookback-days> Daily Notes
```

Read for signal, not completeness. What matters:

- **Work claims** — "finished X", "shipped Y", "started Z"
- **Blockers and decisions** — the *why* behind a state, which ADO rarely carries
- **Ticket references** — IDs like `AB#12345`, `#12345`, or bare 4–6 digit numbers near work language
- **Untracked work** — real effort described with no ticket anywhere

Ignore personal/non-work content. Daily notes are scratch; treat unchecked boxes as intent, not status.

### Step 3: Reconcile — build the gap list

Cross-reference the two sources. A gap is one of:

| Gap | Signal |
|---|---|
| **Conflict** | Note says done, ticket is Active (or vice versa) |
| **Silent movement** | Ticket changed state with nothing in notes explaining it |
| **Untracked work** | Notes describe real work with no matching ticket |
| **Unexplained stall** | Ticket active >14 days, no note touching it |
| **Blank** | Ticket is in scope for the update but neither source says anything current |

Do **not** raise: cosmetic wording differences, personal notes, tickets already correct in both places, or anything the reporting conventions say to skip.

### Step 4: Quiz — one round, only real gaps

Ask about the gap list in a **single batched round** using AskUserQuestion where the answer is a choice, plain text where it's open-ended. Never drip questions one at a time across turns.

For each gap, give the user the evidence — what the note says, what the ticket says — so they can answer without going to look. Offer a concrete best guess as the first option; you have both sources in front of you and usually can tell which is right.

If there are no real gaps, say so and skip straight to the draft. A clean run should be quiet.

### Step 5: Draft the Confluence update

Build the update from the reconciled picture, following the doc's existing structure and the Reporting conventions section. Until conventions are defined, default to:

- **Week of \<Monday's date\>** as the section heading
- **Shipped** — items that moved to done/closed since the last section
- **In progress** — active items, grouped by epic/feature where the hierarchy exists
- **Risks / stuck** — active items unchanged >14 days, or anything the user flagged
- **Up next** — new/committed items for the coming week

Fetch the Confluence page first and read the most recent section, so this update is a delta rather than a restatement. Show the draft to the user before publishing.

### Step 6: Draft the update message

Separately from the doc, draft a short human-readable update message — the kind you'd post to a channel or send to a lead. Shorter and more narrative than the doc: what moved, what's blocked, what's needed from others. Lead with anything that requires someone else to act.

Do both of these:

1. **Print it in the chat** in a fenced block so it can be copied straight out.
2. **Save it to the vault** at the `draft-output` path from the sources doc, stamped with the date. Create parent folders if needed. Tell the user the path.

### Step 7: Update Confluence

After the user approves the draft: add the new section (newest at top, unless the doc's convention differs), preserving all prior sections and the page's macros and formatting. Confluence storage format is XHTML — don't inject raw markdown. Never delete or rewrite past sections.

### Step 8: Report

Link the updated page, name the file the draft was saved to, and summarize what the update says. List anything still ambiguous — mislabeled states, unassigned items, work with no ticket — as suggestions. Do not modify work items.

## Guardrails

- Boards are read-only. Never create, update, or close work items in this flow.
- Never edit the Confluence page without showing the draft and getting a yes.
- Never touch past sections on the status doc.
- Only ever write into the vault at the configured `draft-output` path — never edit the user's existing notes.
- Ask only about real conflicts and blanks. Batch the questions into one round.
- If the sources doc and reality disagree (board gone, page moved, vault path stale), stop and reconcile the sources doc with the user first.
