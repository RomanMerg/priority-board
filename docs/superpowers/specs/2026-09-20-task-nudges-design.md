# Task accountability nudges — design

## Problem

Roman (ADHD, currently unemployed, primary caregiver during the day) plans a daily
task list in the board's "today" column but drops off tracking it as the day goes on
— attention pulled elsewhere, no external prompt to re-check in. A browser
notification only fires while the board tab is open and visible, which isn't a
reliable channel for someone who isn't at the screen most of the day.

## Goal

Push a small status digest of today's task list to Telegram at fixed check-in times,
reusing the Telegram bot and n8n/Postgres stack already built for the finance
pipeline (`finance/02_n8n_sync.json`, `finance/HANDOFF.md`). No new infra category —
same bot, same docker n8n instance, one more Postgres table.

## Non-goals

- No idle/no-progress detection (would require the board to report every state
  change, not just current state — deferred; fixed check-in times cover the need).
- No two-way sync (n8n never writes back to the board's task list).
- No mobile push beyond Telegram (no native app, no web push).

## Data flow

```
priority_board.html                         n8n (docker, local)
  today list changes                              │
  (checkbox, add, remove) ──debounced 2s──▶ POST /tasks-sync ──▶ Postgres
                                                    │              pb.daily_snapshot
                                                    │              (single row, upserted)
                                          Schedule: 09:00 / 13:00 / 17:00
                                                    │
                                            read latest snapshot
                                                    │
                                            Telegram digest ──▶ phone
```

## Data model

New schema `pb`, one table, one row (always upserted, not appended — history isn't
needed for this feature):

```sql
CREATE SCHEMA IF NOT EXISTS pb;

CREATE TABLE pb.daily_snapshot (
  id          int PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- singleton row
  tasks       jsonb NOT NULL,   -- [{num, label, severity, due, dailyDone}]
  synced_at   timestamptz NOT NULL
);
```

`tasks` mirrors the fields already on the task object (`num`, `label`, `severity`,
`due`, `dailyDone`) filtered to `inDaily === true`. No new fields added to the board's
task model.

## Board-side change (`priority_board.html`)

- New small IIFE block, same pattern as the Pomodoro block — self-contained, exposes
  nothing extra on `window` beyond what's needed.
- Hooks into the existing `renderDaily()` / `save()` cycle: after any change that
  affects the daily list (add to daily, remove, toggle done), debounce 2s, then
  `POST` the current daily list (mapped to the shape above) to the URL stored under
  localStorage key `pb_tasks_webhook`.
- Fails silently on network error — no `alert()`, no visible error state (this sync
  is fire-and-forget; the board's own state is always the source of truth and is
  never blocked on it).
- Webhook URL is configured via a small field in the col-right area, reusing the
  `.btn`/input styling already used for the calendar URL field pattern. Exact
  placement: grouped with the Finance tab's webhook field under a shared small
  "integrations" sub-panel (see Finance Tab 2 spec) rather than a second separate
  input floating elsewhere on the board.
- Does not touch pomodoro, kanban, venn, or sticky-notes code.

## n8n additions

Two new workflows, following the existing node conventions in
`finance/02_n8n_sync.json` / `finance/03_n8n_dashboard_api.json`:

1. **`tasks-sync`** — webhook `POST /tasks-sync` → upsert into
   `pb.daily_snapshot` (id=1) → 200 response. No auth beyond what the finance
   webhooks already have (local-network only, per existing setup).
2. **`tasks-nudge`** — three Cron triggers (09:00, 13:00, 17:00) → read
   `pb.daily_snapshot` → branch on staleness → format Telegram message → send via
   the existing `Telegram bot` credential (`TG_CHAT_ID` variable, same as finance
   digest).

## Message format

- **Fresh snapshot** (synced today): `"<time> · <done>/<total> done. Still open:
  #<num> <label>[ (urgent)][ , due today]"`, joining all open items. Example:
  `"14:00 · 2 of 4 done. Still open: #7 Apply to Company X (urgent, due today), #9
  Pick up meds."`
- **All done**: skip the message entirely (no "great job, nothing to do" noise —
  matches the finance pipeline's "silence by default" philosophy).
- **Stale snapshot** (`synced_at` not today):
  - 09:00 run → `"You haven't planned today yet — open the board."`
  - 13:00/17:00 runs → send nothing (avoid nagging with information that's already
    been said once).

## Error handling

- Board → webhook: silent failure, no retry (next debounced save will retry
  naturally on the next edit).
- n8n webhook → Postgres: standard upsert, no special handling needed (single row).
- n8n schedule → Telegram: if the bot send fails, rely on n8n's own execution log
  (same as the finance digest — no additional alerting layer for a notifier about
  notifications).

## Testing / verification

- Manually trigger `tasks-sync` via curl with a sample payload, confirm the row
  lands in `pb.daily_snapshot`.
- Manually execute `tasks-nudge` in n8n for each of the three branches (fresh w/
  open items, fresh all-done, stale) and confirm the Telegram message (or absence of
  one) matches the spec above.
- In the board, add a daily item, confirm a debounced POST fires (network tab), edit
  again within 2s and confirm only one POST fires (debounce working).
