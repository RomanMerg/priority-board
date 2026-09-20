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

## Behavior recap

- Digest at each check-in when today's list has open items and was synced today.
- Silence when everything's done, or after 09:00 if the plan-reminder was already sent.
- "You haven't planned today yet" only at the 09:00 slot, only if nothing was
  synced today.
