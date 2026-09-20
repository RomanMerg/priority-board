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
