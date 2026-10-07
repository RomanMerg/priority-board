# Priority Board v1.0

A self-hosted personal dashboard — Venn diagram priority mapper, Kanban board, daily planner, sticky notes, and Google Calendar embed. Single HTML file, zero dependencies, `localStorage` persistence.

## Features

- **Venn diagram** with draggable/resizable zones — drop tasks onto circles to map priorities
- **Epic bubbles** on the Venn with child tasks connected by dashed ropes
- **Kanban drawer** (open / planned / done) with severity, deadlines, inline editing
- **Daily planner** column — drag tasks to today's list, tick them off
- **Sticky notes** — free text or checklist, drag tasks into notes
- **Display modes** — chips show number only / number+name / due+severity; double-click to toggle per chip
- **Filters** — zone and severity filters fade non-matching chips
- **Dark/light mode toggle** — persists across sessions
- **Google Calendar embed** — slide-up panel (requires local server, see below)
- **Snapshots** — auto daily snapshot + manual saves; restore any previous state
- **Export / Import JSON** — survive any future version update without data loss

## Quickstart (local server — required for Google Calendar embed)

```bash
# Serve the file over HTTP so Google Calendar iframe works
docker run -d \
  --name priority-board \
  --restart unless-stopped \
  -p 8080:80 \
  -v /path/to/this/repo:/usr/share/nginx/html:ro \
  nginx:alpine
```

Then open **http://localhost:8080/priority_board.html** and set it as your Chrome homepage:

`chrome://settings/` → On startup → Open a specific page → `http://localhost:8080/priority_board.html`

Also set as homepage button: Settings → Appearance → Show home button → custom URL → same.

## Google Calendar embed setup

1. Go to [Google Calendar Settings](https://calendar.google.com/calendar/r/settings)
2. Click your calendar → **Integrate calendar** → copy the URL inside `src="..."` from the embed code
3. Click **calendar** button in the Venn toolbar, paste the URL into the field
4. The URL is saved to `localStorage` — you only do this once

The embed reuses your existing Chrome Google session — no extra login needed.

## Preserving data across updates

**Before pulling a new version:**
1. Open the board → click **↓ export** → save the JSON somewhere
2. Pull the new `priority_board.html`
3. Open it → click **↑ import** → pick the JSON

The board also auto-migrates from previous versions (`pb5_*`, `pb6_*`, `pb7_*` localStorage keys).

## Pulling updates from Docker

```bash
# From the directory containing priority_board.html
git pull

# nginx serves the file directly from the mounted volume
# No container restart needed — refresh the browser tab
```

## Initial push to this repo (one-time setup)

```bash
git clone https://github.com/RomanMerg/priority-board
cd priority-board
cp /path/to/priority_board.html .
cp /path/to/README.md .
git add priority_board.html README.md
git commit -m "v1.0 - Priority Board"
git push origin main
```

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
| `pb_theme` | `dark` or `light` |
| `pb_cal_url` | Google Calendar embed URL |
| `pb_snapshots` | array of up to 30 snapshots |

## Version history

- **v1.0** — dark mode toggle, Google Calendar embed, scaled/transparent zone labels, inline task editing, export/import, daily snapshots
