# Finance Tab 2 — design

## Problem

Roman is unemployed and wants tighter visibility into spending, budgets, and
recurring fees (subscriptions, home-appliance costs) without leaving the priority
board. The finance backend pipeline (Postgres schema, n8n sync, n8n dashboard API)
is already built and documented in `finance/HANDOFF.md`. This spec covers the one
remaining piece: a second tab in `priority_board.html` that renders it.

This design incorporates `finance/HANDOFF.md` directly (architecture, API contract,
and conventions are unchanged from that document) and resolves the handful of points
it left open: recategorize interaction, refresh cadence, webhook field placement,
and header behavior.

## Non-goals

- No new backend work — `01_schema.sql`, `02_n8n_sync.json`, `03_n8n_dashboard_api.json`
  are already built (see `finance/HANDOFF.md`) and out of scope here.
- No CDN chart library, no new dependencies, no new CSS variables/colors beyond what
  the API supplies per-category.
- Does not touch pomodoro, kanban, venn, or sticky-notes code.

## Tab switching

A state class on `.layout` (`tab-board` / `tab-finance`) controls visibility via CSS
— no JS show/hide of individual elements, no `display:contents` tricks:

```css
.tab-finance .col-daily,
.tab-finance .col-mid,
.tab-finance .col-right { display: none }
.view-finance { grid-column: 1/-1; grid-row: 2; display: none;
                flex-direction: column; gap: 6px; min-height: 0 }
.tab-finance .view-finance { display: flex }
```

Two buttons ("Board" / "Finance") added to `.hdr` after the `<h1>`, styled like the
existing `.pom-btn.pri` (active state: `background:var(--tx); color:var(--bg)`).
Active tab persists under `localStorage['pb_main_tab']`; on load, the saved tab is
applied before first render so there's no flash of the wrong view.

**Header title stays "Priority Board"** regardless of active tab — the tab buttons
themselves already communicate which view is showing.

## API contract

`GET` to the URL in `localStorage['pb_fin_webhook']` returns exactly this shape
(already implemented by `finance/03_n8n_dashboard_api.json` — do not redesign it):

```json
{
  "month": "Sep 2026", "spent": 1247.8, "income": 2100.0,
  "balance": 3450.2, "budget": 2040.0, "uncategorized": 3,
  "synced_at": "2026-09-19T05:15:22Z",
  "categories":   [{ "name":"Food","spent":312.4,"budget":400,"pct":78,"color":"#0F6E56","icon":"shopping-cart" }],
  "transactions": [{ "date":"19/09","desc":"MAXIMA","cat":"Food","color":"#0F6E56","amount":-23.4,"by":"rule" }],
  "recurring":    [{ "name":"Rent","amount":800,"day":1,"paid":true,"color":"#534AB7" }],
  "reminders":    [{ "label":"Car insurance","due":"2026-09-24","amount":180,"days":5,"urgent":false }]
}
```

`amount` is signed: negative outflow rendered `-` in `--tx`, positive rendered `+`
in `#0F6E56`.

## Layout

1. **Summary row** — 4 cards: spent, income, balance, savings rate (derived:
   `(income - spent) / income`, blank/dash if income is 0).
2. **Three flex columns**, matching the board's existing column density:
   - **Categories** — one row per category: name, icon, horizontal budget bar
     (`div` with `width:%`, capped visually at 100% but bar turns `#E24B4A` when
     `pct > 100`), spent/budget figures in JetBrains Mono.
   - **Transactions** — scrolling feed, newest first as returned by the API. Each
     row: date, description, category chip (colored per `cat`/`color`), signed
     amount. `uncategorized` count surfaces as a small badge if > 0.
   - **Recurring + reminders + integrations panel**, stacked:
     - Recurring: name, amount, day-of-month, paid/unpaid dot in `color`.
     - Reminders: label, due date, amount, days-remaining; `urgent:true` renders the
       day count in `#E24B4A` (`--s1-bd` equivalent) / red.
     - **Integrations panel** (new, shared with the task-nudges feature): two
       labeled text inputs styled like existing `.btn`/input elements —
       "Finance data URL" (`pb_fin_webhook`) and "Tasks sync URL"
       (`pb_tasks_webhook`, per `2026-09-20-task-nudges-design.md`). Saved to
       localStorage on blur/change, no separate save button.

## Recategorize interaction

Clicking a transaction's category chip turns it into an inline `<select>` populated
from the current payload's `categories[].name` (plus whatever category the
transaction currently has, in case it's not in the active list). Picking a new value:

1. Fires `POST` to the `/finance-write` endpoint (same base host as
   `pb_fin_webhook`, per `finance/03_n8n_dashboard_api.json`) with a `recategorize`
   action, the transaction identity, and the new category.
2. Reverts the `<select>` back to a static chip showing the new category
   immediately (optimistic UI) — does not wait for a re-fetch.
3. On request failure, reverts to the original category and shows the existing
   `--tx3` offline-style note rather than an `alert()`.

## Data / refresh behavior

- **Sample payload** (the JSON above) is hardcoded as the fallback so the tab
  renders fully before any backend exists or when `pb_fin_webhook` is unset.
- **Fetch triggers**: on switching to the Finance tab, and via a small refresh icon
  button in the tab's own toolbar. No polling — the underlying sync only runs once
  daily at 05:15, so periodic refetching adds fetch cost with no data benefit.
- On fetch failure (network error, non-2xx, unset URL), keep the last-known-good
  data (sample data on first load) and show a small `--tx3` "offline · sample data"
  note near the summary row. Never `alert()`.

## Conventions (unchanged from `finance/HANDOFF.md`)

- Reuse existing CSS vars only (`--bg --sur --sur2 --bd --bd2 --tx --tx2 --tx3
  --rad-lg`); category colors come from the API, not new CSS variables.
- Numbers in `'JetBrains Mono', monospace` with `font-variant-numeric:
  tabular-nums`; body text in DM Sans; icons via the Tabler webfont.
- No CDN chart library — budget bars are `div`s with `width:%`.
- Font sizes stay in the 8–11px range; panels use `.5px` borders.
- Wrap all of it in one IIFE, matching the Pomodoro block's pattern, exposing only
  what `onclick` handlers need on `window`.

## Testing / verification

- Open the file locally with no `pb_fin_webhook` set: confirm the tab renders the
  sample payload and shows the offline note.
- Set `pb_fin_webhook` to a mock endpoint (or the real n8n webhook once imported)
  returning the contract shape; confirm summary/categories/transactions/
  recurring/reminders all render and the offline note disappears.
- Click a transaction's category chip, pick a different category, confirm the POST
  fires with the right payload shape and the chip updates optimistically.
- Toggle between Board and Finance tabs repeatedly; confirm `pb_main_tab` persists
  across a page reload and no board (venn/kanban/notes/pomodoro) state is disturbed.
- Screenshot both tabs to confirm layout density matches the rest of the board.
