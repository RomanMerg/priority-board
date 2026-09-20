# Finance module — handoff spec

Pipeline artifacts are **done** and in this folder. What remains is the Tab 2 UI in
`priority_board.html`, which is deliberately left for Claude Code because it must read
the current local file first — the board has been edited several times since the last
push to `github.com/RomanMerg/priority-board`, so the version on GitHub is not the
source of truth. **Claude Code: read the local file, not the repo.**

## Files in this folder

| File | What it is | State |
|---|---|---|
| `01_schema.sql` | Schema `fin`: 7 tables, 5 views, seeded categories + ~24 merchant rules | ready to run |
| `02_n8n_sync.json` | Daily 05:15 pull → upsert → categorize → Telegram digest | import, then fix one node (below) |
| `03_n8n_dashboard_api.json` | `GET /finance-data` read API + `POST /finance-write` write-back | import, works as-is |
| `HANDOFF.md` | this file | — |

## Architecture

```
Swedbank ──PSD2──> GoCardless BankAccount Data (free tier)
                          │  daily 05:15
                          ▼
                    n8n (docker, local)
                          │
            ┌─────────────┼──────────────┐
            ▼             ▼              ▼
      Postgres        Ollama          Telegram
      schema fin    qwen3.5:9b      (only when
      (truth)     (new merchants     something
                   only)              is wrong)
                          │
                    GET /finance-data
                          ▼
            priority_board.html · Tab 2
```

Two design choices worth keeping, because both are about cost that compounds:

**Rules before LLM.** `fin.rules` is matched first with plain `ILIKE`. Only genuinely
unseen merchants reach Ollama. The `Promote Rules` node then writes any LLM guess seen
3+ times at ≥0.8 confidence back into `fin.rules`. Inference load *falls* over time
instead of being paid again every morning for the same Maxima run. A manual correction
in the UI writes a rule at priority 20, so correcting something once fixes it forever.

**Silence by default.** `Worth pinging?` suppresses the Telegram message unless a
category is ≥85% of budget or a reminder is inside its notify window. A bot that
messages daily gets muted in a week, which costs you the whole alerting channel.

## Setup order

1. `psql -U postgres -d automation -f 01_schema.sql`
2. GoCardless: register at bankaccountdata.gocardless.com, create secret_id/secret_key.
3. n8n → Settings → Variables: `GC_SECRET_ID`, `GC_SECRET_KEY`, `TG_CHAT_ID`.
4. n8n credentials: Postgres named `Postgres local`, Telegram named `Telegram bot`
   (the JSON references these by id `PG_LOCAL` / `TG_BOT` — n8n will prompt to remap
   on import, that is normal).
5. One-time Swedbank consent, outside these workflows — three calls:
   `POST /api/v2/token/new/` → `POST /api/v2/requisitions/`
   (institution_id `SWEDBANK_HABALV22` / `_HABAEE2X` / `_HABALT22`, pick your country)
   → open the returned `link`, authenticate in Swedbank → `GET /api/v2/requisitions/{id}/`
   returns `accounts[]`.
6. Insert each account id, and **`consent_expires = today + 90 days`**:
   ```sql
   INSERT INTO fin.accounts (id, label, currency, requisition_id, consent_expires)
   VALUES ('<uuid>', 'Swedbank current', 'EUR', '<req-uuid>', CURRENT_DATE + 90);
   ```
7. Import both workflows, run the sync manually once, check `SELECT * FROM fin.sync_log`.
8. Activate. Paste `http://localhost:5678/webhook/finance-data` into Tab 2's field.

## Known defect to fix on import

`02_n8n_sync.json` → the `Parse LLM` node cannot reliably pair Ollama's response back
to its transaction id, because the HTTP Request node does not carry input fields
through. **Fix:** insert a Set node between `Any left?` and `Ollama Classify` that
keeps `_txn_id = {{ $json.id }}`, and reference `$('Still Uncategorized').item.json.id`
inside `Parse LLM` via item pairing. Until that is fixed the LLM leg mislabels under
load; the rules leg is unaffected, so the pipeline is still useful on day one.

Also unverified: exact `typeVersion` values against the installed n8n build, and the
`queryReplacement` expression syntax on Postgres node v2.5. Expect to adjust one or two
on import — check these against `n8n-mcp-docs` rather than guessing.

## Tab 2 UI — the actual remaining work

### API contract

`GET /finance-data` returns exactly this. Build the renderer against this shape; it is
what `Query All Panels` already produces, so don't redesign it.

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

`amount` is signed — negative is outflow. Render `-` in `--tx` and `+` in `#0F6E56`.

### Tab switching

Cleanest approach given the existing grid, and the one to use: put a state class on
`.layout` (`tab-board` / `tab-finance`) and let CSS decide visibility. Do **not** try
`display:contents` on a wrapper — it cannot be toggled back off cleanly.

```css
.tab-finance .col-daily,
.tab-finance .col-mid,
.tab-finance .col-right { display: none }
.view-finance { grid-column: 1/-1; grid-row: 2; display: none;
                flex-direction: column; gap: 6px; min-height: 0 }
.tab-finance .view-finance { display: flex }
```

Tab buttons go in `.hdr` after the `<h1>`, styled like the existing `.pom-btn.pri`
(active: `background:var(--tx); color:var(--bg)`). Persist the active tab under
localStorage key `pb_main_tab`.

### Layout

Summary row of 4 cards (spent / income / balance / savings rate), then three flex
columns: **categories** (horizontal budget bars), **transactions** (scrolling feed),
**recurring + reminders + webhook field** stacked.

### Non-negotiable conventions — the board has no build step and no libraries

- Reuse existing vars only: `--bg --sur --sur2 --bd --bd2 --tx --tx2 --tx3 --rad-lg`.
  Do not introduce new colors; category colors arrive from the API.
- Numbers in `'JetBrains Mono', monospace` with `font-variant-numeric: tabular-nums`,
  body in DM Sans. Icons are the Tabler webfont, `<i class="ti ti-*">`.
- **No CDN chart library.** Bars are divs with a `width:%`. This matches the venn
  diagram already being hand-rolled SVG.
- Font sizes stay in the existing 8–11px range; panels use `.5px` borders. The board is
  deliberately dense — a finance tab in 14px type will look pasted in from elsewhere.
- Wrap all of it in one IIFE like the pomodoro block, exposing only what `onclick`
  handlers need on `window`.

### Behaviour

Ship with the sample payload above hardcoded as the fallback, so the tab renders
before any of the backend exists. On load, read `pb_fin_webhook` from localStorage and
`fetch` it; on failure keep the sample data and show a small `--tx3` "offline · sample
data" note rather than an `alert()`. Bars turn `#E24B4A` when `pct > 100`. Reminders
with `urgent:true` show their day count in red. Clicking a transaction's category chip
should `POST` a `recategorize` action to `/finance-write` — that endpoint exists and is
what makes the rules table self-improving, so wire it rather than leaving the chips dead.

## Suggested Claude Code prompt

> Read `C:\Users\markm\Documents\Claude\Projects\PriorityBoard\priority_board.html` in
> full, then `finance/HANDOFF.md` in the same project. Implement the Tab 2 finance
> dashboard per that spec. Constraints: single file, no new dependencies, no CDN, reuse
> the existing CSS variables and density. Do not touch the pomodoro, kanban, venn, or
> sticky-notes code. Verify by opening the file and screenshotting both tabs.

Worth a `git commit` before it starts, since the repo is behind the local file.
