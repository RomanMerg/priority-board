# Finance Tab 2 & Task Nudges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second "Finance" tab to `priority_board.html` that renders the already-built finance backend, and a Telegram check-in nudge system for the daily task list — both reusing the existing local n8n/Postgres/Telegram stack from the finance pipeline.

**Architecture:** `priority_board.html` gains a CSS-driven tab switch (`.tab-board` / `.tab-finance` on `.layout`) and a self-contained Finance IIFE that renders a hardcoded sample payload by default and fetches `GET /finance-data` on tab switch / manual refresh, falling back to the sample silently on any failure. A second, smaller IIFE debounces pushes of the "today" task list to a new `POST /tasks-sync` webhook. Two new n8n workflows (imported by the user, not run by this plan) and one new Postgres schema (`pb`) complete the nudge loop: a 09:00/13:00/17:00 schedule reads the latest synced snapshot and messages Telegram.

**Tech Stack:** Vanilla JS/HTML/CSS (no build step, no new dependencies), PostgreSQL (schema `pb`, alongside existing `fin`), n8n workflow JSON (matching the existing `finance/02_n8n_sync.json` / `finance/03_n8n_dashboard_api.json` conventions), Telegram Bot API via n8n's `telegram` node.

## Global Constraints

- Single file: all board-side changes stay inside `priority_board.html`. No new files for HTML/CSS/JS, no CDN additions, no new npm/build tooling.
- Reuse existing CSS vars only: `--bg --sur --sur2 --bd --bd2 --tx --tx2 --tx3 --rad-lg`. Category colors come from the API payload, not new CSS variables.
- Numbers in `'JetBrains Mono', monospace` with `font-variant-numeric: tabular-nums`; body text stays DM Sans; icons via the Tabler webfont (`<i class="ti ti-*">`), already loaded.
- Font sizes stay in the existing 8–11px range; panels use `.5px` borders — match the board's existing density, don't introduce a differently-scaled sub-UI.
- All new DOM construction uses `document.createElement` + property assignment, matching every existing render function in this file (`renderDaily`, `renderNotes`, `openModal`) — no `innerHTML` template-literal building, except the one-line `container.innerHTML=''` clear pattern already used throughout.
- New behavior is wrapped in IIFEs (matching the Pomodoro block's pattern), exposing only the functions `onclick` handlers or other code actually needs on `window`.
- Never use `alert()` for error states — failures show a small `--tx3` inline note instead, matching the existing "offline" tone described in the specs.
- Do not touch pomodoro, kanban, venn, or sticky-notes code except the single one-line hook described in Task 8.
- Existing function name `switchTab` is already used for the kanban drawer tabs (open/planned/done) — the new main-tab switcher **must** be named `switchMainTab` to avoid colliding with it.
- n8n node `typeVersion`s and expression syntax in the new workflow JSON files are modeled directly on the already-imported `finance/02_n8n_sync.json` / `finance/03_n8n_dashboard_api.json` for consistency, but (like those files) may need small adjustments against the installed n8n build at import time — check against `n8n-mcp-docs` rather than assuming, per the existing `finance/HANDOFF.md` caveat.

Relevant specs (read before starting):
- `docs/superpowers/specs/2026-09-20-finance-tab2-design.md`
- `docs/superpowers/specs/2026-09-20-task-nudges-design.md`
- `finance/HANDOFF.md` (existing backend architecture and API contract this plan builds against)

---

## Task 1: Main tab switching skeleton

**Files:**
- Modify: `priority_board.html` (CSS block before `</style>`, header buttons, new mount div, `load()`, new `switchMainTab` function)

**Interfaces:**
- Produces: `window.switchMainTab(tab)` where `tab` is `'board'` or `'finance'` — toggles `.layout`'s state class, toggles `.on` on the two tab buttons, persists to `localStorage['pb_main_tab']`, and — when switching to `'finance'` — calls `window.finOnShow()` if it exists (defined in Task 4; guarded so this task works standalone before that exists).
- Produces: DOM mount point `<div class="view-finance" id="view-finance"></div>`, empty until Task 2 renders into it.

- [ ] **Step 1: Add the tab-switching CSS**

In `priority_board.html`, find this exact line (currently line 253):

```
</style>
```

Insert the following block immediately **before** it:

```css

/* ── MAIN TABS ── */
.main-tabs{display:flex;gap:4px}
.main-tab{font-size:11px;padding:3px 10px;border-radius:5px;border:.5px solid var(--bd2);background:var(--sur);color:var(--tx);cursor:pointer;font-family:inherit}
.main-tab:hover{background:var(--sur2)}
.main-tab.on{background:var(--tx);color:var(--bg);border-color:var(--tx)}
.tab-finance .col-daily,
.tab-finance .col-mid,
.tab-finance .col-right{display:none}
.view-finance{grid-column:1/-1;grid-row:2;display:none;flex-direction:column;gap:6px;min-height:0}
.tab-finance .view-finance{display:flex}
```

- [ ] **Step 2: Add the tab buttons to the header**

Find this exact block:

```html
    <h1>Priority Board</h1>
    <span class="hdr-date" id="hdr-date"></span>
    <div class="hdr-tools">
```

Replace it with:

```html
    <h1>Priority Board</h1>
    <span class="hdr-date" id="hdr-date"></span>
    <div class="main-tabs">
      <button class="main-tab on" id="main-tab-board" onclick="switchMainTab('board')">Board</button>
      <button class="main-tab" id="main-tab-finance" onclick="switchMainTab('finance')">Finance</button>
    </div>
    <div class="hdr-tools">
```

- [ ] **Step 3: Add the Finance view mount point**

Find this exact block (the end of `.col-right` and the end of `.layout`):

```html
    </div>
  </div>
</div>

<div class="pom-popup-bg" id="pom-popup" style="display:none" onclick="if(event.target===this)pomPopupClose()">
```

Replace it with:

```html
    </div>
  </div>
  <div class="view-finance" id="view-finance"></div>
</div>

<div class="pom-popup-bg" id="pom-popup" style="display:none" onclick="if(event.target===this)pomPopupClose()">
```

- [ ] **Step 4: Add the `switchMainTab` function**

Find this exact block:

```js
  if(!drawerOpen){drawerOpen=true;applyDrawerState();}
  save();
}

/* ─── COLOR HELPERS ─── */
```

Replace it with:

```js
  if(!drawerOpen){drawerOpen=true;applyDrawerState();}
  save();
}

/* ─── MAIN TABS ─── */
function switchMainTab(tab){
  const layout=document.querySelector('.layout');
  layout.classList.remove('tab-board','tab-finance');
  layout.classList.add('tab-'+tab);
  document.getElementById('main-tab-board').classList.toggle('on',tab==='board');
  document.getElementById('main-tab-finance').classList.toggle('on',tab==='finance');
  try{localStorage.setItem('pb_main_tab',tab);}catch(e){}
  if(tab==='finance'&&window.finOnShow)window.finOnShow();
}
window.switchMainTab=switchMainTab;

/* ─── COLOR HELPERS ─── */
```

- [ ] **Step 5: Restore the saved tab on load**

Find this exact block inside `function load(){...}`:

```js
  applyDrawerState();
  render();
  setTimeout(autoSnapshotIfNeeded,2000);
}
```

Replace it with:

```js
  applyDrawerState();
  render();
  let savedMainTab='board';
  try{savedMainTab=localStorage.getItem('pb_main_tab')||'board';}catch(e){}
  switchMainTab(savedMainTab);
  setTimeout(autoSnapshotIfNeeded,2000);
}
```

- [ ] **Step 6: Manually verify**

Open `priority_board.html` directly in a browser (double-click, or via the existing nginx/docker setup from `README.md`).

Expected:
- Two buttons, "Board" and "Finance", appear in the header after the title/date, before the existing export/import/snapshots buttons.
- "Board" is active (dark background) by default; the normal board UI shows.
- Clicking "Finance" switches the active button, hides the daily/venn/sticky columns, and shows an empty area where `#view-finance` is (nothing rendered yet — expected until Task 2).
- Reload the page after clicking "Finance": the Finance tab should still be active (persisted via `pb_main_tab`).
- Click back to "Board": normal board UI returns, unaffected.

- [ ] **Step 7: Commit**

```bash
git add priority_board.html
git commit -m "Add main tab switching skeleton (Board / Finance)

Empty Finance view mount point, CSS-driven tab visibility, and
localStorage persistence. Finance rendering itself lands in the next
task."
```

---

## Task 2: Finance tab core render (sample data, all panels)

**Files:**
- Modify: `priority_board.html` (CSS block before `</style>`, new Finance IIFE before `load();`)

**Interfaces:**
- Consumes: `#view-finance` mount point (from Task 1).
- Produces: `window.finRender(data)` — clears and rebuilds `#view-finance` from a payload matching the `GET /finance-data` contract in `finance/HANDOFF.md`. Called internally with a hardcoded `SAMPLE` payload; later tasks (3, 4) call it with live/optimistic data.
- Produces: module-scoped (IIFE-private) `SAMPLE` object, `finData` (last-rendered payload, mutated by Task 3's recategorize), `buildSummary`, `buildCategories`, `buildTransactions`, `buildSide` — all referenced by name in Tasks 3 and 4, which edit this same IIFE in place.

- [ ] **Step 1: Add the Finance panel CSS**

Find this exact line (now shifted down by the Task 1 CSS addition — locate by content, not line number):

```
</style>
```

Insert the following block immediately **before** it:

```css

/* ── FINANCE TAB ── */
.fin-summary{display:flex;gap:6px;flex-shrink:0}
.fin-card{flex:1;background:var(--sur);border:.5px solid var(--bd);border-radius:var(--rad-lg);padding:8px 10px;display:flex;flex-direction:column;gap:2px}
.fin-card-lbl{font-size:9px;font-weight:600;color:var(--tx2);text-transform:uppercase;letter-spacing:.06em}
.fin-card-val{font-size:17px;font-weight:600;font-family:'JetBrains Mono',monospace;font-variant-numeric:tabular-nums;color:var(--tx)}
.fin-card-val.neg{color:#E24B4A}
.fin-card-val.pos{color:#0F6E56}
.fin-cols{flex:1;display:flex;gap:6px;min-height:0}
.fin-col{flex:1;display:flex;flex-direction:column;min-height:0;background:var(--sur);border:.5px solid var(--bd);border-radius:var(--rad-lg);overflow:hidden}
.fin-col-hd{padding:5px 8px 4px;border-bottom:.5px solid var(--bd);font-size:10px;font-weight:600;color:var(--tx2);text-transform:uppercase;letter-spacing:.06em;display:flex;align-items:center;gap:5px;flex-shrink:0}
.fin-col-body{flex:1;overflow-y:auto;padding:5px;display:flex;flex-direction:column;gap:4px}
.fin-refresh-btn{margin-left:auto;background:none;border:none;color:var(--tx3);cursor:pointer;font-size:11px;padding:0;line-height:1}
.fin-refresh-btn:hover{color:var(--tx)}
.fin-offline{font-size:9px;color:var(--tx3);padding:4px 8px 2px}
.fin-cat-row{display:flex;flex-direction:column;gap:2px;padding:3px 2px}
.fin-cat-top{display:flex;justify-content:space-between;align-items:center;font-size:10px}
.fin-cat-name{display:flex;align-items:center;gap:4px;color:var(--tx)}
.fin-cat-nums{font-family:'JetBrains Mono',monospace;font-size:9px;color:var(--tx2)}
.fin-cat-bar-track{height:5px;border-radius:3px;background:var(--sur2);overflow:hidden}
.fin-cat-bar-fill{height:100%;border-radius:3px}
.fin-cat-bar-fill.over{background:#E24B4A!important}
.fin-txn-row{display:flex;align-items:center;gap:6px;font-size:10px;padding:3px 2px;border-bottom:.5px solid var(--bd)}
.fin-txn-date{font-family:'JetBrains Mono',monospace;color:var(--tx3);font-size:9px;flex-shrink:0;width:32px}
.fin-txn-desc{flex:1;color:var(--tx);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.fin-txn-cat{font-size:9px;padding:1px 6px;border-radius:8px;border:1px solid;cursor:pointer;flex-shrink:0;white-space:nowrap}
.fin-txn-cat-sel{font-size:9px;padding:1px 3px;border-radius:5px;border:.5px solid var(--bd2);background:var(--sur);color:var(--tx);font-family:inherit}
.fin-txn-amt{font-family:'JetBrains Mono',monospace;font-size:10px;font-variant-numeric:tabular-nums;flex-shrink:0;width:56px;text-align:right}
.fin-txn-amt.neg{color:var(--tx)}
.fin-txn-amt.pos{color:#0F6E56}
.fin-rec-row{display:flex;align-items:center;gap:6px;font-size:10px;padding:3px 2px}
.fin-rec-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.fin-rec-name{flex:1;color:var(--tx)}
.fin-rec-day{font-size:9px;color:var(--tx3);font-family:'JetBrains Mono',monospace}
.fin-rec-amt{font-family:'JetBrains Mono',monospace;font-size:10px;color:var(--tx)}
.fin-rem-row{display:flex;align-items:center;gap:6px;font-size:10px;padding:3px 2px}
.fin-rem-lbl{flex:1;color:var(--tx)}
.fin-rem-days{font-size:9px;font-family:'JetBrains Mono',monospace;color:var(--tx2)}
.fin-rem-days.urgent{color:#E24B4A;font-weight:600}
.fin-rem-amt{font-family:'JetBrains Mono',monospace;font-size:10px;color:var(--tx2)}
.fin-integ{padding:6px 8px;display:flex;flex-direction:column;gap:5px;border-top:.5px solid var(--bd)}
.fin-integ label{font-size:9px;color:var(--tx3);display:flex;flex-direction:column;gap:2px}
.fin-integ input{font-size:10px;padding:3px 6px;border-radius:4px;border:.5px solid var(--bd2);background:var(--sur);color:var(--tx);outline:none;font-family:inherit;box-sizing:border-box}
```

- [ ] **Step 2: Add the Finance IIFE**

Find this exact block (the end of the Pomodoro IIFE, just before the final `load();` call):

```js
  pomUpd();
})();

load();
</script>
```

Replace it with:

```js
  pomUpd();
})();

/* ─── FINANCE TAB ─── */
(function(){
  const SAMPLE={
    month:'Sep 2026', spent:1247.8, income:2100.0,
    balance:3450.2, budget:2040.0, uncategorized:3,
    synced_at:'2026-09-19T05:15:22Z',
    categories:[
      {name:'Food',spent:312.4,budget:400,pct:78,color:'#0F6E56',icon:'shopping-cart'},
      {name:'Transport',spent:96.0,budget:150,pct:64,color:'#534AB7',icon:'car'},
      {name:'Bills',spent:620.0,budget:600,pct:103,color:'#EF9F27',icon:'receipt'},
      {name:'Other',spent:219.4,budget:300,pct:73,color:'#6b6960',icon:'dots'}
    ],
    transactions:[
      {id:'sample-1',date:'19/09',desc:'MAXIMA',cat:'Food',color:'#0F6E56',amount:-23.4,by:'rule'},
      {id:'sample-2',date:'18/09',desc:'Salary',cat:'Income',color:'#0F6E56',amount:1200.0,by:'rule'},
      {id:'sample-3',date:'17/09',desc:'Swedbank fee',cat:'Bills',color:'#EF9F27',amount:-3.5,by:'rule'},
      {id:'sample-4',date:'16/09',desc:'Unknown merchant',cat:'Uncategorized',color:'#a09e96',amount:-14.2,by:'none'}
    ],
    recurring:[
      {name:'Rent',amount:800,day:1,paid:true,color:'#534AB7'},
      {name:'Netflix',amount:12.99,day:5,paid:true,color:'#E24B4A'},
      {name:'Gym',amount:29.0,day:10,paid:false,color:'#0F6E56'}
    ],
    reminders:[
      {label:'Car insurance',due:'2026-09-24',amount:180,days:5,urgent:false},
      {label:'Internet bill',due:'2026-09-21',amount:35,days:2,urgent:true}
    ]
  };
  let finData=SAMPLE;
  let shown=false;

  function fmtAmt(n){return(n<0?'-':'+')+Math.abs(n).toFixed(2);}
  function el(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!==undefined)e.textContent=txt;return e;}

  function buildSummary(data){
    const wrap=el('div','fin-summary');
    const savings=data.income>0?Math.round((data.income-data.spent)/data.income*100):0;
    const cards=[
      {lbl:'spent',val:data.spent.toFixed(2),cls:'neg'},
      {lbl:'income',val:data.income.toFixed(2),cls:'pos'},
      {lbl:'balance',val:data.balance.toFixed(2),cls:''},
      {lbl:'savings rate',val:savings+'%',cls:savings>=0?'pos':'neg'}
    ];
    cards.forEach(c=>{
      const card=el('div','fin-card');
      card.appendChild(el('div','fin-card-lbl',c.lbl));
      card.appendChild(el('div','fin-card-val'+(c.cls?' '+c.cls:''),c.val));
      wrap.appendChild(card);
    });
    return wrap;
  }

  function buildCategories(data){
    const col=el('div','fin-col');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'categories'));
    col.appendChild(hd);
    const body=el('div','fin-col-body');
    data.categories.forEach(c=>{
      const row=el('div','fin-cat-row');
      const top=el('div','fin-cat-top');
      const name=el('span','fin-cat-name');
      const ic=document.createElement('i');ic.className='ti ti-'+c.icon;ic.style.cssText='font-size:10px;color:'+c.color;
      name.appendChild(ic);
      name.appendChild(document.createTextNode(c.name));
      top.appendChild(name);
      top.appendChild(el('span','fin-cat-nums',c.spent.toFixed(2)+' / '+c.budget.toFixed(2)));
      row.appendChild(top);
      const track=el('div','fin-cat-bar-track');
      const fill=el('div','fin-cat-bar-fill'+(c.pct>100?' over':''));
      fill.style.width=Math.min(c.pct,100)+'%';
      if(c.pct<=100)fill.style.background=c.color;
      track.appendChild(fill);
      row.appendChild(track);
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }

  function buildTransactions(data){
    const col=el('div','fin-col');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'transactions'));
    if(data.uncategorized>0)hd.appendChild(el('span','fin-cat-nums',data.uncategorized+' uncat'));
    col.appendChild(hd);
    const body=el('div','fin-col-body');
    data.transactions.forEach(t=>{
      const row=el('div','fin-txn-row');
      row.appendChild(el('span','fin-txn-date',t.date));
      row.appendChild(el('span','fin-txn-desc',t.desc));
      const chip=el('span','fin-txn-cat',t.cat);
      chip.style.cssText='border-color:'+t.color+';color:'+t.color;
      row.appendChild(chip);
      row.appendChild(el('span','fin-txn-amt '+(t.amount<0?'neg':'pos'),fmtAmt(t.amount)));
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }

  function buildSide(data){
    const col=el('div','fin-col');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'recurring'));
    col.appendChild(hd);
    const body=el('div','fin-col-body');
    data.recurring.forEach(r=>{
      const row=el('div','fin-rec-row');
      const dot=el('span','fin-rec-dot');dot.style.background=r.color;
      row.appendChild(dot);
      row.appendChild(el('span','fin-rec-name',r.name));
      row.appendChild(el('span','fin-rec-day','day '+r.day));
      const amt=el('span','fin-rec-amt',r.amount.toFixed(2));
      amt.style.opacity=r.paid?'1':'.5';
      row.appendChild(amt);
      body.appendChild(row);
    });
    body.appendChild(el('div','fin-col-hd','reminders'));
    data.reminders.forEach(r=>{
      const row=el('div','fin-rem-row');
      row.appendChild(el('span','fin-rem-lbl',r.label));
      row.appendChild(el('span','fin-rem-days'+(r.urgent?' urgent':''),r.days+'d'));
      row.appendChild(el('span','fin-rem-amt',r.amount.toFixed(2)));
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }

  function finRender(data){
    finData=data;
    const mount=document.getElementById('view-finance');
    if(!mount)return;
    mount.innerHTML='';
    mount.appendChild(buildSummary(data));
    const cols=el('div','fin-cols');
    cols.appendChild(buildCategories(data));
    cols.appendChild(buildTransactions(data));
    cols.appendChild(buildSide(data));
    mount.appendChild(cols);
  }

  window.finRender=finRender;
})();

load();
</script>
```

- [ ] **Step 3: Manually verify**

Reload `priority_board.html`, click the "Finance" tab.

Expected:
- Four summary cards (spent / income / balance / savings rate) with sample numbers, spent in red-ish tone, income/savings-rate in green.
- Three columns: categories (4 rows with horizontal bars — "Bills" bar should render fully colored red/`#E24B4A` since its `pct` is 103), transactions (4 rows with colored category chips and signed amounts), and a combined recurring/reminders column (3 recurring rows, then a "reminders" sub-header, then 2 reminder rows — "Internet bill" shows its day count in red since `urgent:true`).
- No errors in the browser console.
- Switching back to "Board" and forward to "Finance" again re-renders correctly (no duplicate content, no leftover DOM from the previous render).

- [ ] **Step 4: Commit**

```bash
git add priority_board.html
git commit -m "Render Finance tab from sample data

Summary cards, category budget bars, transaction feed, and combined
recurring/reminders column, all built with the sample payload from
finance/HANDOFF.md's API contract. Live fetch and recategorize wiring
land in the next two tasks."
```

---

## Task 3: Recategorize interaction

**Files:**
- Modify: `priority_board.html` (Finance IIFE from Task 2: `buildTransactions`, plus two new functions)
- Modify: `finance/03_n8n_dashboard_api.json` (add `id` to the transactions payload — see rationale below)

**Interfaces:**
- Consumes: `finData`, `SAMPLE.transactions[].id` (added in this task), `fmtAmt`, `el` — all from Task 2's IIFE.
- Produces: `finRecategorize(t, newCat, data)` (IIFE-private, called from the inline `<select>`'s `onchange`) and `finWriteUrl(readUrl)` (IIFE-private helper), plus a modified `buildTransactions` that renders a clickable, recategorizable chip per row.

**Why the backend file changes:** `finance/HANDOFF.md`'s documented `GET /finance-data` contract (and the `finance/03_n8n_dashboard_api.json` workflow that implements it) does not include a transaction `id` in the `transactions` array, but `POST /finance-write`'s `recategorize` action requires exactly that (`$json.body.txn_id`, per the existing `Recategorize` node's query). Without an id, clicking a transaction to recategorize it has nothing valid to send. The underlying SQL view `fin.v_recent_txn` (`finance/01_schema.sql:142-155`) already selects `t.id` — it's only missing from the `json_build_object` in `Query All Panels`. This is the same category of gap `finance/HANDOFF.md` already flags and asks Claude Code to fix for the `Parse LLM` node ("Known defect to fix on import") — a one-field addition to an already-built workflow, not a redesign.

- [ ] **Step 1: Add `id` to the dashboard API's transactions payload**

In `finance/03_n8n_dashboard_api.json`, find this exact fragment inside the `Query All Panels` node's `query` parameter:

```
  'transactions', COALESCE((\n     SELECT json_agg(json_build_object(\n       'date', date, 'desc', descr, 'cat', category,\n       'color', trim(color), 'amount', amount::float8, 'by', categorized_by))\n     FROM fin.v_recent_txn), '[]'::json),\n
```

Replace it with:

```
  'transactions', COALESCE((\n     SELECT json_agg(json_build_object(\n       'id', id, 'date', date, 'desc', descr, 'cat', category,\n       'color', trim(color), 'amount', amount::float8, 'by', categorized_by))\n     FROM fin.v_recent_txn), '[]'::json),\n
```

(This is a single-line edit inside the existing JSON-escaped SQL string — the only change is inserting `'id', id, ` right after `json_build_object(`.)

- [ ] **Step 2: Replace `buildTransactions` and add the recategorize functions**

In the Finance IIFE (added in Task 2), find this exact block:

```js
  function buildTransactions(data){
    const col=el('div','fin-col');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'transactions'));
    if(data.uncategorized>0)hd.appendChild(el('span','fin-cat-nums',data.uncategorized+' uncat'));
    col.appendChild(hd);
    const body=el('div','fin-col-body');
    data.transactions.forEach(t=>{
      const row=el('div','fin-txn-row');
      row.appendChild(el('span','fin-txn-date',t.date));
      row.appendChild(el('span','fin-txn-desc',t.desc));
      const chip=el('span','fin-txn-cat',t.cat);
      chip.style.cssText='border-color:'+t.color+';color:'+t.color;
      row.appendChild(chip);
      row.appendChild(el('span','fin-txn-amt '+(t.amount<0?'neg':'pos'),fmtAmt(t.amount)));
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }
```

Replace it with:

```js
  function buildTransactions(data){
    const col=el('div','fin-col');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'transactions'));
    if(data.uncategorized>0)hd.appendChild(el('span','fin-cat-nums',data.uncategorized+' uncat'));
    col.appendChild(hd);
    const body=el('div','fin-col-body');
    data.transactions.forEach(t=>{
      const row=el('div','fin-txn-row');
      row.appendChild(el('span','fin-txn-date',t.date));
      row.appendChild(el('span','fin-txn-desc',t.desc));
      const chipWrap=document.createElement('span');
      row.appendChild(chipWrap);
      renderTxnCat(chipWrap,t,data);
      row.appendChild(el('span','fin-txn-amt '+(t.amount<0?'neg':'pos'),fmtAmt(t.amount)));
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }

  function renderTxnCat(wrap,t,data){
    wrap.innerHTML='';
    const chip=el('span','fin-txn-cat',t.cat);
    chip.style.cssText='border-color:'+t.color+';color:'+t.color;
    chip.title='click to recategorize';
    chip.onclick=()=>{
      wrap.innerHTML='';
      const sel=document.createElement('select');sel.className='fin-txn-cat-sel';
      const names=data.categories.map(c=>c.name);
      if(names.indexOf(t.cat)===-1)names.unshift(t.cat);
      names.forEach(n=>{const o=document.createElement('option');o.value=n;o.textContent=n;if(n===t.cat)o.selected=true;sel.appendChild(o);});
      sel.onchange=()=>{finRecategorize(t,sel.value,data);renderTxnCat(wrap,t,data);};
      sel.onblur=()=>{renderTxnCat(wrap,t,data);};
      wrap.appendChild(sel);
      sel.focus();
    };
    wrap.appendChild(chip);
  }

  function finWriteUrl(readUrl){
    const idx=readUrl.lastIndexOf('/');
    return idx===-1?readUrl:readUrl.slice(0,idx+1)+'finance-write';
  }

  function finRecategorize(t,newCat,data){
    const prevCat=t.cat,prevColor=t.color;
    const newCatObj=data.categories.find(c=>c.name===newCat);
    t.cat=newCat;
    if(newCatObj)t.color=newCatObj.color;
    let url='';
    try{url=localStorage.getItem('pb_fin_webhook')||'';}catch(e){}
    if(!url||!t.id)return;
    fetch(finWriteUrl(url),{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({action:'recategorize',txn_id:t.id,category:newCat})})
      .catch(()=>{t.cat=prevCat;t.color=prevColor;finRender(data);});
  }
```

- [ ] **Step 3: Manually verify (frontend, no live backend needed)**

Reload the board, open the Finance tab, open the browser's Network tab.

Expected:
- Clicking a transaction's category chip swaps it for a `<select>` populated with all category names (plus the current one if it's not in the list, e.g. "Uncategorized").
- Picking a different category immediately reverts the `<select>` back to a chip showing the new category and color (optimistic update) — no visible delay.
- In the Network tab, a `POST` request fires to `.../finance-write` (or nothing, if `pb_fin_webhook` is still unset at this point — expected, since Task 4 adds the field to set it; if you want to see the request fire now, temporarily run `localStorage.setItem('pb_fin_webhook','http://localhost:5678/webhook/finance-data')` in the console first). The request body is `{"action":"recategorize","txn_id":"sample-1","category":"<picked category>"}` for whichever sample row you clicked.
- Since no real backend is listening yet, the request fails; confirm the chip reverts to its original category (rollback path).

- [ ] **Step 4: Commit**

```bash
git add priority_board.html finance/03_n8n_dashboard_api.json
git commit -m "Add transaction recategorize interaction

Inline dropdown on the category chip, optimistic update, POST to
/finance-write. Also fixes finance/03_n8n_dashboard_api.json to
include the transaction id in GET /finance-data — the write-back
action requires it and the underlying view already selects it, it
was just missing from the JSON payload."
```

---

## Task 4: Integrations panel + fetch wiring + refresh + offline note

**Files:**
- Modify: `priority_board.html` (Finance IIFE: `buildSide`, `finOnShow`, `finFetch`)

**Interfaces:**
- Consumes: `finRender`, `finData`, `el`, `localStorage['pb_fin_webhook']`, `localStorage['pb_tasks_webhook']` (the latter also read by Task 8's sync IIFE — this task only writes the field, doesn't consume it).
- Produces: `window.finOnShow()` (called by `switchMainTab` from Task 1), `finFetch()` (IIFE-private, also wired to the refresh button).

- [ ] **Step 1: Add the integrations panel to `buildSide` and wire fetch**

Find this exact block (the end of `buildSide`, from Task 2):

```js
    body.appendChild(el('div','fin-col-hd','reminders'));
    data.reminders.forEach(r=>{
      const row=el('div','fin-rem-row');
      row.appendChild(el('span','fin-rem-lbl',r.label));
      row.appendChild(el('span','fin-rem-days'+(r.urgent?' urgent':''),r.days+'d'));
      row.appendChild(el('span','fin-rem-amt',r.amount.toFixed(2)));
      body.appendChild(row);
    });
    col.appendChild(body);
    return col;
  }

  function finRender(data){
```

Replace it with:

```js
    body.appendChild(el('div','fin-col-hd','reminders'));
    data.reminders.forEach(r=>{
      const row=el('div','fin-rem-row');
      row.appendChild(el('span','fin-rem-lbl',r.label));
      row.appendChild(el('span','fin-rem-days'+(r.urgent?' urgent':''),r.days+'d'));
      row.appendChild(el('span','fin-rem-amt',r.amount.toFixed(2)));
      body.appendChild(row);
    });
    col.appendChild(body);
    col.appendChild(buildIntegrations());
    return col;
  }

  function buildIntegrations(){
    const wrap=el('div','fin-integ');
    const hd=el('div','fin-col-hd');
    hd.appendChild(el('span',null,'integrations'));
    const refreshBtn=el('button','fin-refresh-btn');
    refreshBtn.innerHTML='<i class="ti ti-refresh" style="font-size:11px"></i>';
    refreshBtn.title='refresh finance data';
    refreshBtn.onclick=finFetch;
    hd.appendChild(refreshBtn);
    wrap.appendChild(hd);

    const finLbl=el('label',null,'Finance data URL');
    const finInp=document.createElement('input');
    finInp.type='text';finInp.placeholder='http://localhost:5678/webhook/finance-data';
    try{finInp.value=localStorage.getItem('pb_fin_webhook')||'';}catch(e){}
    finInp.onchange=()=>{try{localStorage.setItem('pb_fin_webhook',finInp.value.trim());}catch(e){}finFetch();};
    finLbl.appendChild(finInp);
    wrap.appendChild(finLbl);

    const taskLbl=el('label',null,'Tasks sync URL');
    const taskInp=document.createElement('input');
    taskInp.type='text';taskInp.placeholder='http://localhost:5678/webhook/tasks-sync';
    try{taskInp.value=localStorage.getItem('pb_tasks_webhook')||'';}catch(e){}
    taskInp.onchange=()=>{try{localStorage.setItem('pb_tasks_webhook',taskInp.value.trim());}catch(e){}};
    taskLbl.appendChild(taskInp);
    wrap.appendChild(taskLbl);

    wrap.appendChild(el('div','fin-offline',''));
    wrap.lastChild.id='fin-offline-note';
    return wrap;
  }

  function finFetch(){
    let url='';
    try{url=localStorage.getItem('pb_fin_webhook')||'';}catch(e){}
    const note=document.getElementById('fin-offline-note');
    if(!url){if(note)note.textContent='offline · sample data';return;}
    fetch(url).then(r=>{if(!r.ok)throw new Error('bad status');return r.json();})
      .then(data=>{finRender(data);const n=document.getElementById('fin-offline-note');if(n)n.textContent='';})
      .catch(()=>{if(note)note.textContent='offline · sample data';});
  }

  function finRender(data){
```

- [ ] **Step 2: Expose `finOnShow` for `switchMainTab` to call**

Find this exact block (the end of the Finance IIFE, from Task 2):

```js
  window.finRender=finRender;
})();
```

Replace it with:

```js
  window.finRender=finRender;
  window.finOnShow=function(){
    if(!shown){finRender(finData);shown=true;}
    finFetch();
  };
})();
```

- [ ] **Step 3: Manually verify**

Reload the board (clear `pb_fin_webhook`/`pb_tasks_webhook` from localStorage first if you set them during Task 3's verification, to test the unset-URL path cleanly). Open the Finance tab.

Expected:
- The recurring/reminders column now ends with an "integrations" sub-panel: two labeled text inputs ("Finance data URL", "Tasks sync URL") and a small refresh icon next to the "integrations" heading.
- With both fields empty, an "offline · sample data" note appears under the inputs.
- Typing a URL into "Finance data URL" and tabbing away (change event) triggers a fetch attempt (visible in the Network tab); since nothing is listening yet, it fails and the offline note stays.
- Clicking the refresh icon re-triggers the same fetch attempt.
- The value typed persists across a page reload (localStorage).
- Switching to "Board" and back to "Finance" does not re-fetch from scratch every time — `shown` guards the first synchronous render, but `finFetch()` still runs on every show (by design, per the spec's "fetch on tab switch" behavior) — confirm this is a single fetch per switch, not a loop or repeated calls.

- [ ] **Step 4: Commit**

```bash
git add priority_board.html
git commit -m "Add finance integrations panel, fetch-on-switch, and refresh

Two webhook URL fields (finance data, tasks sync) saved to
localStorage, a manual refresh button, and an offline/sample-data
note on fetch failure or unset URL. No polling, per the design spec."
```

---

## Task 5: `pb` schema for task snapshots

**Files:**
- Create: `finance/04_pb_schema.sql`

**Interfaces:**
- Produces: table `pb.daily_snapshot` (singleton row, `id=1`), consumed by Task 6 (webhook upsert) and Task 7 (scheduled read).

- [ ] **Step 1: Write the schema file**

Create `finance/04_pb_schema.sql`:

```sql
-- ============================================================
-- Priority Board · Task nudges schema
-- Target: local PostgreSQL (docker), schema `pb`
-- Run: psql -U postgres -d automation -f 04_pb_schema.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS pb;
SET search_path TO pb, public;

-- ── daily_snapshot (singleton row, always upserted) ───────────
-- Holds the board's current "today" list so the tasks-nudge
-- workflow can read it on a schedule even when the board isn't
-- open. Not a history table by design — see
-- docs/superpowers/specs/2026-09-20-task-nudges-design.md.
CREATE TABLE IF NOT EXISTS daily_snapshot (
  id          SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  tasks       JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{num,label,severity,due,dailyDone}]
  synced_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Manually verify**

Run against the local Postgres instance (adjust connection details to match your setup, per `finance/HANDOFF.md`'s setup order):

```bash
psql -U postgres -d automation -f finance/04_pb_schema.sql
```

Expected output: `CREATE SCHEMA` (or no-op if it already exists) and `CREATE TABLE`, no errors.

Confirm the table exists:

```bash
psql -U postgres -d automation -c "\d pb.daily_snapshot"
```

Expected: column list showing `id`, `tasks`, `synced_at` with the types above.

- [ ] **Step 3: Commit**

```bash
git add finance/04_pb_schema.sql
git commit -m "Add pb schema for task-nudge daily snapshots

Singleton table holding the board's current 'today' list, upserted
by the new tasks-sync webhook and read by the tasks-nudge schedule."
```

---

## Task 6: n8n `tasks-sync` webhook workflow

**Files:**
- Create: `finance/05_n8n_tasks_sync.json`

**Interfaces:**
- Consumes: `pb.daily_snapshot` table (Task 5), the `Postgres local` credential already configured per `finance/HANDOFF.md` (id `PG_LOCAL`).
- Produces: webhook `POST http://localhost:5678/webhook/tasks-sync`, the URL the board's "Tasks sync URL" field (Task 4) and sync IIFE (Task 8) target.

- [ ] **Step 1: Write the workflow file**

Create `finance/05_n8n_tasks_sync.json`:

```json
{
  "name": "Priority Board · Tasks Sync",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "tasks-sync",
        "responseMode": "responseNode",
        "options": {}
      },
      "id": "c1000000-0000-4000-8000-000000000001",
      "name": "POST /tasks-sync",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [-400, 0],
      "webhookId": "tasks-sync",
      "notes": "Final URL: http://localhost:5678/webhook/tasks-sync — paste into the board's Tasks sync URL field."
    },
    {
      "parameters": {
        "operation": "executeQuery",
        "query": "INSERT INTO pb.daily_snapshot (id, tasks, synced_at)\nVALUES (1, $1::jsonb, now())\nON CONFLICT (id) DO UPDATE SET tasks = EXCLUDED.tasks, synced_at = EXCLUDED.synced_at;",
        "options": { "queryReplacement": "={{ JSON.stringify($json.body.tasks) }}" }
      },
      "id": "c1000000-0000-4000-8000-000000000002",
      "name": "Upsert Snapshot",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2.5,
      "position": [-180, 0],
      "credentials": { "postgres": { "id": "PG_LOCAL", "name": "Postgres local" } }
    },
    {
      "parameters": {
        "respondWith": "json",
        "responseBody": "={{ JSON.stringify({ ok: true }) }}",
        "options": { "responseHeaders": { "entries": [
          { "name": "Access-Control-Allow-Origin", "value": "*" }
        ] } }
      },
      "id": "c1000000-0000-4000-8000-000000000003",
      "name": "Respond OK",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1.1,
      "position": [40, 0],
      "notes": "CORS header is required: the board is opened as file:// so its origin is null."
    }
  ],
  "connections": {
    "POST /tasks-sync": { "main": [ [ { "node": "Upsert Snapshot", "type": "main", "index": 0 } ] ] },
    "Upsert Snapshot":  { "main": [ [ { "node": "Respond OK", "type": "main", "index": 0 } ] ] }
  },
  "settings": { "executionOrder": "v1", "timezone": "Europe/Vilnius" },
  "active": false,
  "pinData": {},
  "meta": { "instanceId": "priority-board-tasks" },
  "tags": [ { "name": "tasks-nudge" } ]
}
```

- [ ] **Step 2: Manually verify**

Import into n8n (per the same import process used for `finance/02_n8n_sync.json` / `finance/03_n8n_dashboard_api.json` in `finance/HANDOFF.md` — remap the `PG_LOCAL` credential if prompted), activate it, then:

```bash
curl -X POST http://localhost:5678/webhook/tasks-sync \
  -H "Content-Type: application/json" \
  -d '{"tasks":[{"num":7,"label":"Apply to Company X","severity":1,"due":"2026-09-20","dailyDone":false}]}'
```

Expected: `{"ok":true}` response. Then:

```bash
psql -U postgres -d automation -c "SELECT tasks, synced_at FROM pb.daily_snapshot WHERE id=1;"
```

Expected: one row, `tasks` containing the posted array, `synced_at` at (or just after) the current time.

- [ ] **Step 3: Commit**

```bash
git add finance/05_n8n_tasks_sync.json
git commit -m "Add n8n tasks-sync webhook workflow

POST /tasks-sync upserts the board's current daily task list into
pb.daily_snapshot. Import and activate per finance/HANDOFF.md's
existing import process; remap the PG_LOCAL credential if prompted."
```

---

## Task 7: n8n `tasks-nudge` schedule workflow

**Files:**
- Create: `finance/06_n8n_tasks_nudge.json`

**Interfaces:**
- Consumes: `pb.daily_snapshot` (Task 5, kept fresh by Task 6), the `Postgres local` (`PG_LOCAL`) and `Telegram bot` (`TG_BOT`) credentials already configured per `finance/HANDOFF.md`, and the `TG_CHAT_ID` n8n variable already set for the finance digest.

- [ ] **Step 1: Write the workflow file**

Create `finance/06_n8n_tasks_nudge.json`:

```json
{
  "name": "Priority Board · Tasks Nudge",
  "nodes": [
    {
      "parameters": {
        "rule": { "interval": [
          { "field": "cronExpression", "expression": "0 9 * * *" },
          { "field": "cronExpression", "expression": "0 13 * * *" },
          { "field": "cronExpression", "expression": "0 17 * * *" }
        ] }
      },
      "id": "c2000000-0000-4000-8000-000000000001",
      "name": "Check-in times",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1.2,
      "position": [-640, 0],
      "notes": "09:00 / 13:00 / 17:00 daily. Downstream SQL reads now() to tell which slot fired."
    },
    {
      "parameters": {
        "operation": "executeQuery",
        "query": "-- One round trip: counts, a formatted open-items summary, and\n-- which message (if any) is worth sending, all in one row.\nWITH s AS (\n  SELECT tasks, synced_at FROM pb.daily_snapshot WHERE id = 1\n),\nbase AS (\n  SELECT\n    COALESCE((SELECT tasks FROM s), '[]'::jsonb) AS tasks,\n    COALESCE((SELECT synced_at::date = CURRENT_DATE FROM s), FALSE) AS is_fresh\n)\nSELECT\n  (SELECT count(*) FROM jsonb_array_elements(tasks) t\n     WHERE (t->>'dailyDone')::boolean) AS done_count,\n  (SELECT count(*) FROM jsonb_array_elements(tasks) t\n     WHERE NOT (t->>'dailyDone')::boolean) AS open_count,\n  (SELECT string_agg(\n      '#' || (t->>'num') || ' ' || (t->>'label') ||\n      CASE WHEN (t->>'severity')::int = 1 THEN ' (urgent)' ELSE '' END ||\n      CASE WHEN (t->>'due') = to_char(CURRENT_DATE,'YYYY-MM-DD') THEN ', due today' ELSE '' END,\n      ', ')\n   FROM jsonb_array_elements(tasks) t\n   WHERE NOT (t->>'dailyDone')::boolean) AS open_summary,\n  CASE\n    WHEN is_fresh AND (SELECT count(*) FROM jsonb_array_elements(tasks) t\n                          WHERE NOT (t->>'dailyDone')::boolean) > 0\n      THEN 'digest'\n    WHEN NOT is_fresh AND EXTRACT(HOUR FROM now()) = 9\n      THEN 'remind_to_plan'\n    ELSE ''\n  END AS nudge_kind\nFROM base;",
        "options": {}
      },
      "id": "c2000000-0000-4000-8000-000000000002",
      "name": "Read Snapshot",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2.5,
      "position": [-420, 0],
      "credentials": { "postgres": { "id": "PG_LOCAL", "name": "Postgres local" } }
    },
    {
      "parameters": {
        "rules": { "values": [
          { "conditions": { "options": { "version": 2, "caseSensitive": true, "leftValue": "" }, "combinator": "and",
            "conditions": [ { "id": "n1", "operator": { "type": "string", "operation": "equals" },
              "leftValue": "={{ $json.nudge_kind }}", "rightValue": "digest" } ] },
            "outputKey": "digest" },
          { "conditions": { "options": { "version": 2, "caseSensitive": true, "leftValue": "" }, "combinator": "and",
            "conditions": [ { "id": "n2", "operator": { "type": "string", "operation": "equals" },
              "leftValue": "={{ $json.nudge_kind }}", "rightValue": "remind_to_plan" } ] },
            "outputKey": "remind_to_plan" }
        ] },
        "options": { "fallbackOutput": "none" }
      },
      "id": "c2000000-0000-4000-8000-000000000003",
      "name": "Worth pinging?",
      "type": "n8n-nodes-base.switch",
      "typeVersion": 3.2,
      "position": [-200, 0],
      "notes": "All-done and already-said-once cases fall through to no output — silence by default, same philosophy as the finance digest."
    },
    {
      "parameters": {
        "chatId": "={{ $vars.TG_CHAT_ID }}",
        "text": "=*{{ $now.toFormat('HH:mm') }}* · {{ $json.done_count }} of {{ $json.done_count + $json.open_count }} done. Still open: {{ $json.open_summary }}",
        "additionalFields": { "parse_mode": "Markdown", "appendAttribution": false }
      },
      "id": "c2000000-0000-4000-8000-000000000004",
      "name": "Send Digest",
      "type": "n8n-nodes-base.telegram",
      "typeVersion": 1.2,
      "position": [40, -80],
      "credentials": { "telegramApi": { "id": "TG_BOT", "name": "Telegram bot" } }
    },
    {
      "parameters": {
        "chatId": "={{ $vars.TG_CHAT_ID }}",
        "text": "You haven't planned today yet — open the board.",
        "additionalFields": { "parse_mode": "Markdown", "appendAttribution": false }
      },
      "id": "c2000000-0000-4000-8000-000000000005",
      "name": "Send Plan Reminder",
      "type": "n8n-nodes-base.telegram",
      "typeVersion": 1.2,
      "position": [40, 80],
      "credentials": { "telegramApi": { "id": "TG_BOT", "name": "Telegram bot" } }
    }
  ],
  "connections": {
    "Check-in times": { "main": [ [ { "node": "Read Snapshot", "type": "main", "index": 0 } ] ] },
    "Read Snapshot":  { "main": [ [ { "node": "Worth pinging?", "type": "main", "index": 0 } ] ] },
    "Worth pinging?": { "main": [
                          [ { "node": "Send Digest", "type": "main", "index": 0 } ],
                          [ { "node": "Send Plan Reminder", "type": "main", "index": 0 } ]
                        ] }
  },
  "settings": { "executionOrder": "v1", "timezone": "Europe/Vilnius" },
  "active": false,
  "pinData": {},
  "meta": { "instanceId": "priority-board-tasks" },
  "tags": [ { "name": "tasks-nudge" } ]
}
```

- [ ] **Step 2: Manually verify all three branches**

Import into n8n (remap `PG_LOCAL`/`TG_BOT` credentials if prompted). For each branch, set up the data with `psql`, then manually execute the workflow from the n8n editor (not waiting for the schedule) and confirm the Telegram message:

**Branch A — fresh snapshot, open items (expect a digest message):**
```bash
psql -U postgres -d automation -c "
INSERT INTO pb.daily_snapshot (id, tasks, synced_at) VALUES (1,
  '[{\"num\":7,\"label\":\"Apply to Company X\",\"severity\":1,\"due\":\"'||CURRENT_DATE||'\",\"dailyDone\":false},
    {\"num\":9,\"label\":\"Pick up meds\",\"severity\":0,\"due\":null,\"dailyDone\":true}]'::jsonb, now())
ON CONFLICT (id) DO UPDATE SET tasks=EXCLUDED.tasks, synced_at=EXCLUDED.synced_at;"
```
Execute the workflow manually. Expected Telegram message: `"<HH:mm> · 1 of 2 done. Still open: #7 Apply to Company X (urgent, due today)"`.

**Branch B — fresh snapshot, all done (expect silence):**
```bash
psql -U postgres -d automation -c "
UPDATE pb.daily_snapshot SET tasks = jsonb_set(tasks,'{0,dailyDone}','true') WHERE id=1;"
```
Execute manually. Expected: `Worth pinging?` produces no output on either branch — no Telegram message sent.

**Branch C — stale snapshot (expect the plan-reminder message only if the current wall-clock hour is 9; otherwise silence):**
```bash
psql -U postgres -d automation -c "
UPDATE pb.daily_snapshot SET synced_at = now() - interval '2 days' WHERE id=1;"
```
Execute manually at any time and check the `Read Snapshot` node's output data (not the Telegram send) for `nudge_kind`: it should be `'remind_to_plan'` only when run during the 9 o'clock hour, and `''` otherwise. If you want to see the actual Telegram message fire, temporarily edit the `Send Plan Reminder`/`Worth pinging?` node's hour check or just trust the `nudge_kind` output — don't wait for exactly 9am to consider this verified.

- [ ] **Step 3: Commit**

```bash
git add finance/06_n8n_tasks_nudge.json
git commit -m "Add n8n tasks-nudge schedule workflow

09:00/13:00/17:00 check-ins reading pb.daily_snapshot: a digest of
open/done tasks when the snapshot is fresh, a one-time 'plan your
day' nudge at 09:00 if it's stale, and silence otherwise. Import and
activate per finance/HANDOFF.md's existing import process."
```

---

## Task 8: Board-side debounced daily-list sync

**Files:**
- Modify: `priority_board.html` (`renderDaily()` one-line hook, new small IIFE)

**Interfaces:**
- Consumes: global `tasks` array (already declared at the top of the script), `localStorage['pb_tasks_webhook']` (written by Task 4's integrations panel).
- Produces: `window.pbTasksSyncPing()` — called once per `renderDaily()` invocation; internally debounces to one `POST` per 2 seconds of inactivity.

- [ ] **Step 1: Hook the sync ping into `renderDaily`**

Find this exact block:

```js
function renderDaily(){
  const inner=document.getElementById('daily-inner');inner.innerHTML='';
  const daily=tasks.filter(t=>t.inDaily);
  if(!daily.length){const h=document.createElement('div');h.className='daily-hint';h.textContent='drag tasks here for today';inner.appendChild(h);return;}
```

Replace it with:

```js
function renderDaily(){
  const inner=document.getElementById('daily-inner');inner.innerHTML='';
  const daily=tasks.filter(t=>t.inDaily);
  if(window.pbTasksSyncPing)window.pbTasksSyncPing();
  if(!daily.length){const h=document.createElement('div');h.className='daily-hint';h.textContent='drag tasks here for today';inner.appendChild(h);return;}
```

- [ ] **Step 2: Add the sync IIFE**

Find this exact block (the end of the Finance IIFE from Task 4, just before `load();`):

```js
  window.finOnShow=function(){
    if(!shown){finRender(finData);shown=true;}
    finFetch();
  };
})();

load();
</script>
```

Replace it with:

```js
  window.finOnShow=function(){
    if(!shown){finRender(finData);shown=true;}
    finFetch();
  };
})();

/* ─── TASKS SYNC (nudges) ─── */
(function(){
  let syncTimer=null;
  function doSync(){
    let url='';
    try{url=localStorage.getItem('pb_tasks_webhook')||'';}catch(e){}
    if(!url)return;
    const daily=tasks.filter(t=>t.inDaily).map(t=>({num:t.num,label:t.label,severity:t.severity,due:t.due,dailyDone:t.dailyDone}));
    fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({tasks:daily})}).catch(()=>{});
  }
  window.pbTasksSyncPing=function(){
    clearTimeout(syncTimer);
    syncTimer=setTimeout(doSync,2000);
  };
})();

load();
</script>
```

- [ ] **Step 3: Manually verify**

Reload the board. In the Finance tab's integrations panel, set "Tasks sync URL" to `http://localhost:5678/webhook/tasks-sync` (or any URL you can observe — even a nonexistent one, watched via the Network tab). Switch back to the Board tab, open the Network tab.

Expected:
- Drag a task into "today" (or add one, or toggle a daily item done/undone). No request fires immediately.
- After ~2 seconds of no further changes, exactly one `POST` fires to the tasks-sync URL, with a body like `{"tasks":[{"num":7,"label":"...","severity":0,"due":"","dailyDone":false}]}` matching the current daily list.
- Make two changes within 2 seconds of each other (e.g. toggle two items quickly): confirm only **one** POST fires afterward (debounce working), not two.
- If a real `tasks-sync` webhook is running (Task 6, imported and active), confirm via `psql -c "SELECT tasks, synced_at FROM pb.daily_snapshot;"` that the row updates after each debounced sync.

- [ ] **Step 4: Commit**

```bash
git add priority_board.html
git commit -m "Add debounced daily-task sync for the tasks-nudge pipeline

renderDaily() pings a 2s-debounced POST to the tasks-sync webhook
whenever the today list changes (add/remove/toggle-done), so the
nudge schedule always has a reasonably current snapshot even when
the board isn't open at check-in time."
```

---

## Task 9: Setup docs + final walkthrough

**Files:**
- Create: `finance/NUDGES_SETUP.md`

**Interfaces:**
- None — documentation and final manual verification only.

- [ ] **Step 1: Write the setup doc**

Create `finance/NUDGES_SETUP.md`:

```markdown
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
```

- [ ] **Step 2: Full walkthrough verification**

With both n8n workflows active and the board's webhook fields set:

1. Open `priority_board.html`. Confirm the Board tab looks exactly as it did before this plan (venn, kanban, daily planner, sticky notes, pomodoro all unaffected).
2. Switch to the Finance tab. Confirm it now fetches from the real `GET /finance-data` endpoint (per `finance/03_n8n_dashboard_api.json`) instead of showing sample data — the offline note should be gone if the finance sync has run at least once (per `finance/HANDOFF.md`'s setup steps 1–8).
3. Click a transaction's category chip, recategorize it, confirm the change persists after a manual refresh (i.e. it actually wrote back via `POST /finance-write`).
4. Add/remove/toggle a few items on today's list; confirm `pb.daily_snapshot` updates.
5. Take one screenshot of the Board tab and one of the Finance tab (e.g. via your browser's own screenshot tool, or the project's existing screenshot workflow if any) for your own record of the finished state — not committed to the repo.

- [ ] **Step 3: Commit**

```bash
git add finance/NUDGES_SETUP.md
git commit -m "Add task-nudges setup doc

Companion to HANDOFF.md covering the pb schema, the two new n8n
workflows, and the board-side webhook field for the Telegram
check-in nudges."
```
