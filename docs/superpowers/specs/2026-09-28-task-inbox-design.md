# Task Inbox (voice-created tasks) — design

## Problem

Roman wants to eventually create board tasks by voice (e.g. via a phone assistant
calling into the existing n8n stack) and have them show up on the priority board
without opening it. Today the board only reads from `localStorage`; nothing outside
the browser tab can add a task to it. This spec covers the one missing piece that
makes that possible: a write path from n8n into the board's task list.

The voice/agent layer itself (MCP wrapper, phone assistant, hosting) is a separate,
later piece of work — see the effort estimate discussed in chat. This spec is scoped
to just the inbox: an endpoint a voice agent (or a manual `curl`, for now) can call to
create a task, and the board-side mechanism that picks it up.

## Non-goals

- No voice agent, MCP server, or phone-side integration — out of scope, future work.
- No API-based auto-push of the resulting n8n workflow into a specific project/folder
  — this ships as a JSON file imported manually, same as every workflow so far
  (`02`–`06`). `n8n-mcp`, the connector that could do this, is present but currently
  broken in this session (output-schema dialect mismatch); worth revisiting once
  that's fixed, not blocking this feature.
- No general composable "flag" system (arbitrary emoji badges per task) — deferred to
  its own future brainstorm. This spec only adds one new, single-purpose marker: a
  microphone icon for voice-origin tasks.
- No new field in the integrations panel — the inbox endpoints share the same webhook
  base already configured under "Tasks sync URL" (`pb_tasks_webhook`), the same way
  `/finance-write` shares a base with `/finance-data`.
- No marker on the Venn chip — see "Visual marker" below for why.
- No polling beyond once per page load — consistent with the rest of the board.

## Data model

New table in the existing `pb` schema (same file series as `pb.daily_snapshot`):

```sql
CREATE TABLE IF NOT EXISTS task_inbox (
  id          SERIAL PRIMARY KEY,
  label       TEXT NOT NULL,
  due         DATE,
  severity    SMALLINT,               -- 0-3, matches the board's scale; NULL = unset
  source      TEXT NOT NULL DEFAULT 'voice',
  claimed     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Not a queue with delivery guarantees — a simple claim-on-read table, matching the
project's existing tolerance for eventual-consistency-style sync (see `finRecategorize`'s
fire-and-forget POST, or `pbTasksSyncPing`'s silent-failure debounce).

## n8n workflow

One new file, `finance/07_n8n_task_inbox.json`, bundling two webhooks (mirroring how
`03_n8n_dashboard_api.json` bundles the finance read/write pair):

- **`POST /add-task`** — validates `label` is present, inserts a row (`due`/`severity`
  optional, `source` defaults to `'voice'`). This is what a future voice agent, or a
  manual `curl`, calls to create a task.
- **`GET /task-inbox`** — a single atomic query,
  `UPDATE pb.task_inbox SET claimed = true WHERE claimed = false RETURNING *`,
  responding with the claimed rows as JSON. Whatever this returns is considered
  delivered — no second confirmation round trip (see "Claim strategy" below).

Both reuse the `Postgres local` (`PG_LOCAL`) credential already configured for every
other workflow in this project. No new credentials.

### Claim strategy (chosen over two-phase claim)

Two approaches were considered:

- **Chosen: single atomic claim-on-read.** One query does both the read and the
  claim. Simple, one n8n node, one HTTP round trip. Risk: if the board's HTTP
  response is lost after n8n has already responded (rare network failure), that
  batch of tasks is lost — never delivered, but also never retried. For a personal
  task list (not financial data), an occasional lost task is an acceptable failure
  mode, and the alternative below isn't worth its added complexity for this.
- **Rejected: two-phase claim.** `GET /task-inbox` returns unclaimed rows without
  marking them; the board POSTs the ids back to confirm receipt only after
  successfully merging and saving locally. More robust against the above edge case,
  but doubles the API surface (a third endpoint) and code for a low-stakes,
  low-probability risk.

## Board-side changes (`priority_board.html`)

- **New URL derivation.** Two small helper functions, matching the existing
  `finWriteUrl` pattern, derive `/task-inbox` and `/add-task` from the existing
  `pb_tasks_webhook` value (e.g. `http://localhost:5678/webhook/tasks-sync` →
  `http://localhost:5678/webhook/task-inbox`). No new localStorage key, no new
  integrations-panel field.
- **New function**, called once from `load()` (after `tasks`/`nid` are restored from
  localStorage, alongside the existing `render()` call): fetch `/task-inbox` (GET, no
  body). On success, for each row returned, construct a task object with the same
  shape `addTask()` produces, plus one new field:
  - `label`: from the row.
  - `due`: row's `due` if present, else `''`.
  - `inDaily`: `true` when the row has no `due`; `false` when it does (the due date
    governs visibility instead — this was the explicitly confirmed rule: *no due
    date means "today"; a due date means "due then," not forced into today's list*).
  - `severity`: row's `severity`, or `0` if unset.
  - `source`: `'voice'` (carried through from the row; currently always `'voice'`
    since that's the table's default, but read from the row rather than
    hardcoded, so a future non-voice source doesn't need a board-side code change).
  - All other fields default exactly as `addTask()` already sets them (`isEpic:
    false`, `parentId: null`, `status: 'open'`, `placed: false`, etc.).
  After processing all rows, call `save()` and `render()` once (not per row). On any
  fetch error (network failure, non-2xx, empty `pb_tasks_webhook`), fail silently —
  no `alert()`, no visible error state, consistent with `pbTasksSyncPing`.

## Visual marker

A small `ti-microphone` icon marks a task as voice-created, added in two places:

- **Kanban row** (`renderTaskRow`) — next to the label, alongside the existing
  zone-tag/due-date/severity badges already rendered there.
- **Daily planner chip** (`renderDaily`) — next to the label, inside the chip.

**Not added to the Venn chip.** In its default "num" display mode the Venn chip is a
21×21px circular badge showing just `#7` — there's no room for another icon without
visually cluttering an already extremely compact element, and voice-created tasks
land in the open Kanban list (per the confirmed landing-spot decision), not placed on
the Venn, until dragged there manually — at which point they're indistinguishable
from any other placed task by design (the Venn is about priority-zone placement, not
task metadata).

Severity is **not** given a new visual treatment here — S1 tasks already render in
the existing red-tinted chip/row style everywhere on the board. A voice-created,
severity-1 task is therefore already visually urgent (existing color) *and* marked as
voice-origin (new mic icon) — the "two flags together" effect, achieved by reusing
what exists rather than adding a redundant glyph.

## Testing / verification

- `psql`: run the new schema file, confirm `pb.task_inbox` exists.
- `curl -X POST .../add-task` with a label-only payload, then with a full payload
  (label + due + severity); confirm both insert correctly.
- `curl .../task-inbox` twice in a row: first call returns the inserted row(s), second
  call returns an empty array — proves the atomic claim works and there's no
  duplicate delivery.
- Open the board with `pb_tasks_webhook` configured: confirm a no-due-date task lands
  in the open Kanban list AND in "today" with `inDaily:true`; confirm a task with a
  due date lands in the open Kanban list with that due date set, NOT in "today".
- Confirm the microphone icon appears on both the kanban row and the daily chip (for
  the no-due-date case) for these tasks, and does not appear on manually-typed tasks.
- Reload the board again with no new inbox rows: confirm no duplicate tasks appear
  (idempotency holds across reloads, not just consecutive curl calls).
