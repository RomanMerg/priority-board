# Priority Board

A self-hosted personal dashboard: Venn diagram priority mapper, Kanban board, daily planner, sticky notes, focus timer, and an optional **Finance** tab. One HTML file, no build step, no dependencies beyond a CDN icon font. Everything is stored in your browser's `localStorage`.

An optional local backend (n8n + Postgres, in [`finance/`](finance/)) adds bank-synced spending, Telegram check-in nudges, and an inbox for tasks created outside the board (e.g. by a voice agent). The board works fully without it.

## Features

### Board tab (works standalone)

- **Venn diagram** with draggable/resizable zones. Drop tasks onto circles to map priorities.
- **Epic bubbles** on the Venn with child tasks connected by dashed ropes.
- **Kanban drawer** (open / planned / done) with severity (S1-S3), due dates and inline editing.
- **Daily planner** column: drag tasks to today's list, tick them off.
- **Sticky notes**: free text or checklist; drag tasks into notes.
- **Focus timer** (Pomodoro): adjustable length, bell + browser notification + popup on finish, small daily checklist.
- **Display modes**: chips show number, number+name, or due+severity. Double-click a chip to toggle it individually.
- **Filters** by zone and severity.
- **Snapshots**: automatic daily snapshot plus manual saves; restore any previous state.
- **Export / Import JSON** so you can survive version updates without losing data.
- Dark mode follows your system setting (`prefers-color-scheme`); there is no manual toggle.

### Finance tab (sample data until you connect the backend)

- **Board / Finance** tab switch in the header (remembered across reloads).
- Summary cards (spent, income, balance, savings rate), category budget bars, transaction feed with click-to-recategorize, recurring payments and reminders.
- Ships with hardcoded sample data and shows `offline · sample data` until a Finance data URL is set and reachable.
- Recategorizing a transaction writes back to the backend and teaches it a rule for next time.

### Task nudges and inbox (need the n8n backend)

- **Tasks sync**: the board pushes today's list (debounced) to n8n, so a Telegram digest can summarise it at 09:00 / 13:00 / 17:00.
- **Task inbox**: tasks created outside the board land in `pb.task_inbox`; the board claims them once per page load. A task with no due date goes into Today; one with a due date keeps that date.
- Source markers on tasks: a microphone for voice-created tasks, a calendar-check for routine picks.

## Quickstart (local server)

Serve the file over HTTP (a plain `file://` open also works for the Board tab):

```bash
docker run -d \
  --name priority-board \
  --restart unless-stopped \
  -p 8080:80 \
  -v /path/to/this/repo:/usr/share/nginx/html:ro \
  nginx:alpine
```

Open **http://localhost:8080/priority_board.html**. To make it your Chrome homepage: `chrome://settings/` → On startup → Open a specific page, and optionally Appearance → Show home button.

## Connecting the backend (optional)

The board talks to n8n through two URLs, set on the **Finance** tab → *integrations* panel (stored in your browser only):

| Field | Example | Used for |
|-------|---------|----------|
| Finance data URL | `http://localhost:5678/webhook/finance-data` | Finance tab data (the recategorize write path is derived from it) |
| Tasks sync URL | `http://localhost:5678/webhook/tasks-sync` | Daily-list sync, and the task inbox read path (derived from it) |

Setup, in order:

1. Finance: follow [`finance/HANDOFF.md`](finance/HANDOFF.md) (schema, GoCardless/Swedbank consent, workflows `02`-`03`).
2. Nudges and inbox: follow [`finance/NUDGES_SETUP.md`](finance/NUDGES_SETUP.md) (`04_pb_schema.sql`, workflows `05`-`07`).

The `offline · sample data` note reflects the **Finance data URL** only; setting just the Tasks sync URL won't clear it.

Status: the backend files are written and reviewed but have not been run end to end against a live n8n instance. `NUDGES_SETUP.md` lists the known risks to verify on import (query parameter handling, CORS preflight on POST requests).

### Backend files

| File | What it is |
|------|------------|
| `finance/01_schema.sql` | Schema `fin`: accounts, transactions, categories, rules, reminders, views |
| `finance/02_n8n_sync.json` | Daily bank pull, categorize (rules first, local LLM for unknowns), Telegram alert |
| `finance/03_n8n_dashboard_api.json` | `GET /finance-data`, `POST /finance-write` |
| `finance/04_pb_schema.sql` | Schema `pb`: `daily_snapshot`, `task_inbox` |
| `finance/05_n8n_tasks_sync.json` | `POST /tasks-sync` |
| `finance/06_n8n_tasks_nudge.json` | 09:00 / 13:00 / 17:00 Telegram check-ins |
| `finance/07_n8n_task_inbox.json` | `POST /add-task`, `GET /task-inbox`, `GET /task-snapshot` |

Design specs and the implementation plan are under [`docs/superpowers/`](docs/superpowers/).

## Secrets

No credentials live in this repo. Bank API keys, the Telegram bot token and chat ID are n8n credentials and Variables. If you add a `.env` or exports, `.gitignore` already excludes `.env*`, n8n exports, board exports and snapshots.

## Preserving data across updates

**Before pulling a new version:**
1. Open the board → click **↓ export** → save the JSON somewhere.
2. Pull the new `priority_board.html`.
3. Open it → click **↑ import** → pick the JSON.

The board also auto-migrates from previous versions (`pb5_*`, `pb6_*`, `pb7_*` keys).

## localStorage keys

| Key | Content |
|-----|---------|
| `pb7_t` | tasks array |
| `pb7_n` | next task ID |
| `pb7_nt` | notes array |
| `pb7_z` | zones array |
| `pb7_dr` | drawer open state |
| `pb7_tab` | active kanban tab |
| `pb7_gmode` | global chip display mode |
| `pb7_cmode` | per-chip mode overrides |
| `pb_snapshots` | array of up to 30 snapshots |
| `pb_main_tab` | active main tab (`board` or `finance`) |
| `pb_fin_webhook` | Finance data URL |
| `pb_tasks_webhook` | Tasks sync URL |

## Version history

- **Unreleased** (Finance and nudges): Finance tab, Telegram task nudges, task inbox with voice/routine markers, Pomodoro focus timer, `.gitignore`, this README rewrite. Removed README claims for a Google Calendar embed and a dark/light toggle, which are not in the current file.
- **v1.0**: Venn priority mapper, Kanban, daily planner, sticky notes, inline task editing, export/import, daily snapshots.
