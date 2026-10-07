-- ============================================================
-- Priority Board · Task nudges schema
-- Target: local PostgreSQL (docker), schema `pb`
-- Run: psql -U postgres -d automation_internal -f 04_pb_schema.sql
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

-- ── task_inbox (claim-on-read) ────────────────────────────────
-- Tasks created outside the board (voice agent, daily-brief routine).
-- The board claims unclaimed rows once per page load. `ref` dedupes
-- routine picks across days. See
-- docs/superpowers/specs/2026-09-28-task-inbox-design.md and the
-- daily-brief spec in smb-automation-internal.
CREATE TABLE IF NOT EXISTS task_inbox (
  id          SERIAL PRIMARY KEY,
  label       TEXT NOT NULL,
  due         DATE,
  severity    SMALLINT,
  source      TEXT NOT NULL DEFAULT 'voice',
  ref         TEXT,
  claimed     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One *open* row per ref: a ref can be re-picked on a later day once the earlier row was claimed.
CREATE UNIQUE INDEX IF NOT EXISTS task_inbox_ref_open ON task_inbox (ref) WHERE NOT claimed;
