# Task nudges — setup

Companion to `HANDOFF.md`, covering the Telegram check-in nudges for the board's
daily task list. Design: `docs/superpowers/specs/2026-09-20-task-nudges-design.md`.

## Setup order

1. `psql -U postgres -d automation -f 04_pb_schema.sql`
2. Import `05_n8n_tasks_sync.json` and `06_n8n_tasks_nudge.json` into n8n. Both
   reference the same `Postgres local` (`PG_LOCAL`) credential as the finance
   workflows; `06_n8n_tasks_nudge.json` also reuses the `Telegram bot` (`TG_BOT`)
   credential and `TG_CHAT_ID` variable already set up for the finance digest — no
   new credentials or variables needed.
3. Activate both workflows.
4. Open `priority_board.html` → Finance tab → integrations panel → paste
   `http://localhost:5678/webhook/tasks-sync` into "Tasks sync URL".
5. Add a task to today's list on the board; confirm a row appears in
   `pb.daily_snapshot` within a couple of seconds
   (`psql -U postgres -d automation -c "SELECT * FROM pb.daily_snapshot;"`).
6. Wait for (or manually trigger, from the n8n editor) the next 09:00 / 13:00 /
   17:00 run and confirm the Telegram message matches what's on the board.

## Known risks — verify on import

These are unverified against a live n8n/Postgres instance (same caveat `HANDOFF.md`
already carries for the finance workflows) — check them during setup, not after
something silently doesn't fire:

- **`tasks-sync`'s `queryReplacement`** passes a single JSON-stringified array as one
  `{{ }}` expression. n8n's Postgres node splits `queryReplacement` on commas in the
  *template text* (outside `{{ }}` blocks) before evaluating each piece — since this
  query has only one `{{ }}` block, it should resolve to one parameter regardless of
  the commas inside the JSON string it evaluates to, but this hasn't been tested
  against a live import. If `$1::jsonb` fails after import, this is the first place
  to check.
- **CORS preflight on `POST /tasks-sync` and `POST /finance-write`.** Both requests
  send `Content-Type: application/json` from the board, which triggers a browser
  preflight `OPTIONS` request. If the installed n8n webhook node doesn't answer
  `OPTIONS` automatically, both writes will fail silently in the browser before
  reaching n8n at all — indistinguishable from the backend being down (offline note,
  reverted chip). If recategorizing or task-sync silently never works even though
  `GET /finance-data` works fine, this is almost certainly why.
- **Recommended smoke test before relying on this:** run `04_pb_schema.sql`, import
  and activate both new workflows, then `curl -X POST` `/tasks-sync` with a
  **multi-task** payload (not just one field) and confirm `pb.daily_snapshot`
  updates; separately, open the board in an actual browser (not curl) and confirm a
  recategorize or a daily-list edit actually reaches n8n via the Network tab, since
  curl has no CORS and can't surface the preflight risk above.

## Behavior recap

- Digest at each check-in when today's list has open items and was synced today.
- Silence when everything's done. The 13:00/17:00 slots can only ever produce the
  digest branch or silence — the "haven't planned" reminder is only evaluated at the
  09:00 slot, there is no send-tracking involved.
- "You haven't planned today yet" only at the 09:00 slot, only if nothing was
  synced today.
