-- ============================================================
-- Priority Board · Finance module schema
-- Target: local PostgreSQL (docker), schema `fin`
-- Run: psql -U postgres -d automation -f 01_schema.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS fin;
SET search_path TO fin, public;

-- ── accounts (one row per GoCardless account id) ─────────────
CREATE TABLE IF NOT EXISTS accounts (
  id            TEXT PRIMARY KEY,              -- GoCardless account UUID
  label         TEXT NOT NULL,                 -- "Swedbank current"
  iban          TEXT,
  currency      CHAR(3) NOT NULL DEFAULT 'EUR',
  balance       NUMERIC(12,2),
  balance_at    TIMESTAMPTZ,
  requisition_id TEXT,                         -- for re-consent tracking
  consent_expires DATE,                        -- PSD2: 90 days, must re-auth
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  last_synced   TIMESTAMPTZ
);

-- ── categories ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
  id            SMALLSERIAL PRIMARY KEY,
  name          TEXT UNIQUE NOT NULL,
  budget_month  NUMERIC(10,2) NOT NULL DEFAULT 0,
  color         CHAR(7) NOT NULL DEFAULT '#888780',
  icon          TEXT NOT NULL DEFAULT 'dots',  -- tabler icon name
  sort_order    SMALLINT NOT NULL DEFAULT 100,
  is_income     BOOLEAN NOT NULL DEFAULT FALSE
);

-- ── merchant → category rules (checked before the LLM) ───────
-- Deterministic layer. Cheap, instant, and stops Ollama from
-- re-deciding the same merchant every single day.
CREATE TABLE IF NOT EXISTS rules (
  id            SERIAL PRIMARY KEY,
  pattern       TEXT NOT NULL,                 -- ILIKE pattern, e.g. '%maxima%'
  category_id   SMALLINT NOT NULL REFERENCES categories(id),
  priority      SMALLINT NOT NULL DEFAULT 100, -- lower wins
  hit_count     INTEGER NOT NULL DEFAULT 0,
  created_by    TEXT NOT NULL DEFAULT 'manual' -- manual | llm_promoted
);
CREATE INDEX IF NOT EXISTS rules_prio_idx ON rules(priority);

-- ── transactions ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
  id            TEXT PRIMARY KEY,              -- GoCardless transactionId (idempotency key)
  account_id    TEXT NOT NULL REFERENCES accounts(id),
  booked_on     DATE NOT NULL,
  amount        NUMERIC(12,2) NOT NULL,        -- signed: negative = outflow
  currency      CHAR(3) NOT NULL DEFAULT 'EUR',
  counterparty  TEXT,                          -- creditorName / debtorName
  description   TEXT,                          -- remittanceInformationUnstructured
  category_id   SMALLINT REFERENCES categories(id),
  categorized_by TEXT,                         -- rule | llm | manual | null
  confidence    NUMERIC(3,2),                  -- llm self-reported 0.00-1.00
  is_internal   BOOLEAN NOT NULL DEFAULT FALSE,-- own-account transfer, excluded from spend
  raw           JSONB,
  ingested_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS txn_booked_idx   ON transactions(booked_on DESC);
CREATE INDEX IF NOT EXISTS txn_cat_idx      ON transactions(category_id);
CREATE INDEX IF NOT EXISTS txn_month_idx    ON transactions(date_trunc('month', booked_on));
CREATE INDEX IF NOT EXISTS txn_uncat_idx    ON transactions(id) WHERE category_id IS NULL;

-- ── recurring / fixed monthly costs ──────────────────────────
CREATE TABLE IF NOT EXISTS recurring (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  amount        NUMERIC(10,2) NOT NULL,
  currency      CHAR(3) NOT NULL DEFAULT 'EUR',
  due_day       SMALLINT NOT NULL CHECK (due_day BETWEEN 1 AND 31),
  category_id   SMALLINT REFERENCES categories(id),
  match_pattern TEXT,                          -- ILIKE used to auto-mark as paid
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  notes         TEXT
);

-- ── reminders (bills, renewals, one-offs) ────────────────────
CREATE TABLE IF NOT EXISTS reminders (
  id            SERIAL PRIMARY KEY,
  label         TEXT NOT NULL,
  due_on        DATE NOT NULL,
  amount        NUMERIC(10,2),
  notify_days   SMALLINT NOT NULL DEFAULT 3,   -- ping N days before
  notified_at   TIMESTAMPTZ,
  done          BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS rem_due_idx ON reminders(due_on) WHERE NOT done;

-- ── sync audit log (debug the pipeline without guessing) ─────
CREATE TABLE IF NOT EXISTS sync_log (
  id            BIGSERIAL PRIMARY KEY,
  ran_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  account_id    TEXT,
  fetched       INTEGER NOT NULL DEFAULT 0,
  inserted      INTEGER NOT NULL DEFAULT 0,
  categorized   INTEGER NOT NULL DEFAULT 0,
  ok            BOOLEAN NOT NULL DEFAULT TRUE,
  error         TEXT
);

-- ============================================================
-- VIEWS · the dashboard reads only these, never raw tables
-- ============================================================

-- current-month spend per category vs budget
CREATE OR REPLACE VIEW v_month_by_category AS
SELECT
  c.id, c.name, c.color, c.icon, c.budget_month AS budget,
  COALESCE(SUM(-t.amount) FILTER (WHERE t.amount < 0), 0) AS spent,
  CASE WHEN c.budget_month > 0
       THEN ROUND(COALESCE(SUM(-t.amount) FILTER (WHERE t.amount < 0),0) / c.budget_month * 100)
       ELSE 0 END AS pct
FROM categories c
LEFT JOIN transactions t
  ON t.category_id = c.id
 AND NOT t.is_internal
 AND date_trunc('month', t.booked_on) = date_trunc('month', CURRENT_DATE)
WHERE NOT c.is_income
GROUP BY c.id, c.name, c.color, c.icon, c.budget_month, c.sort_order
ORDER BY c.sort_order, spent DESC;

-- headline numbers for the summary cards
CREATE OR REPLACE VIEW v_month_summary AS
SELECT
  to_char(CURRENT_DATE, 'Mon YYYY')                                    AS month,
  COALESCE(SUM(-amount) FILTER (WHERE amount < 0), 0)                  AS spent,
  COALESCE(SUM( amount) FILTER (WHERE amount > 0), 0)                  AS income,
  (SELECT COALESCE(SUM(balance),0) FROM accounts WHERE active)         AS balance,
  (SELECT COALESCE(SUM(budget_month),0) FROM categories
     WHERE NOT is_income)                                              AS budget_total,
  COUNT(*) FILTER (WHERE category_id IS NULL)                          AS uncategorized
FROM transactions
WHERE NOT is_internal
  AND date_trunc('month', booked_on) = date_trunc('month', CURRENT_DATE);

-- recent feed for the transactions panel
CREATE OR REPLACE VIEW v_recent_txn AS
SELECT
  t.id,
  to_char(t.booked_on, 'DD/MM') AS date,
  COALESCE(NULLIF(t.counterparty,''), t.description, 'unknown') AS descr,
  COALESCE(c.name, 'uncategorized') AS category,
  c.color,
  t.amount,
  t.categorized_by
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE NOT t.is_internal
ORDER BY t.booked_on DESC, t.ingested_at DESC
LIMIT 60;

-- recurring costs, auto-flagged paid if a matching txn landed this month
CREATE OR REPLACE VIEW v_recurring_status AS
SELECT
  r.id, r.name, r.amount, r.due_day, c.color,
  EXISTS (
    SELECT 1 FROM transactions t
    WHERE date_trunc('month', t.booked_on) = date_trunc('month', CURRENT_DATE)
      AND r.match_pattern IS NOT NULL
      AND (t.counterparty ILIKE r.match_pattern OR t.description ILIKE r.match_pattern)
  ) AS paid
FROM recurring r
LEFT JOIN categories c ON c.id = r.category_id
WHERE r.active
ORDER BY r.due_day;

-- reminders due soon
CREATE OR REPLACE VIEW v_reminders_open AS
SELECT id, label, due_on, amount,
       (due_on - CURRENT_DATE) AS days_left,
       (due_on - CURRENT_DATE) <= notify_days AS urgent
FROM reminders
WHERE NOT done
ORDER BY due_on;

-- ============================================================
-- SEED
-- ============================================================
INSERT INTO categories (name, budget_month, color, icon, sort_order, is_income) VALUES
  ('Housing',       800, '#534AB7', 'home',             10, FALSE),
  ('Food',          400, '#0F6E56', 'shopping-cart',    20, FALSE),
  ('Transport',     150, '#993C1D', 'car',              30, FALSE),
  ('Utilities',     100, '#3B6D11', 'bolt',             40, FALSE),
  ('Subscriptions',  80, '#993556', 'device-desktop',   50, FALSE),
  ('Health',         60, '#E24B4A', 'heart',            60, FALSE),
  ('Leisure',       100, '#EF9F27', 'device-gamepad',   70, FALSE),
  ('Kid',           150, '#2F7FA8', 'teddy-bear',       80, FALSE),
  ('Other',         200, '#888780', 'dots',             90, FALSE),
  ('Income',          0, '#0F6E56', 'trending-up',     100, TRUE)
ON CONFLICT (name) DO NOTHING;

-- starter rules: cheap wins so the LLM only sees genuinely new merchants
INSERT INTO rules (pattern, category_id, priority, created_by)
SELECT p, (SELECT id FROM categories WHERE name = cn), pr, 'manual'
FROM (VALUES
  ('%maxima%',    'Food', 10), ('%rimi%',     'Food', 10),
  ('%lidl%',      'Food', 10), ('%iki%',      'Food', 10),
  ('%norfa%',     'Food', 10), ('%barbora%',  'Food', 10),
  ('%bolt%',      'Transport', 10), ('%circle k%', 'Transport', 10),
  ('%viada%',     'Transport', 10), ('%orlen%',    'Transport', 10),
  ('%netflix%',   'Subscriptions', 10), ('%spotify%', 'Subscriptions', 10),
  ('%openai%',    'Subscriptions', 10), ('%anthropic%', 'Subscriptions', 10),
  ('%github%',    'Subscriptions', 10), ('%google%',  'Subscriptions', 20),
  ('%ignitis%',   'Utilities', 10), ('%telia%',    'Utilities', 10),
  ('%bite%',      'Utilities', 10), ('%tele2%',    'Utilities', 10),
  ('%benu%',      'Health', 10), ('%eurovaistine%', 'Health', 10),
  ('%atlyginim%', 'Income', 5),  ('%salary%',   'Income', 5)
) AS s(p, cn, pr)
ON CONFLICT DO NOTHING;
