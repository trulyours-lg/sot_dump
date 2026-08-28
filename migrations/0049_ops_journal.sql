-- 0049: ops_journal — what the machine did beside Anytype, and why.
--
-- ops.py (anytype_sync) executes the Sync-health playbook procedures
-- (daemon restarts, mints, sync.yml rebuilds). On the Corporate box the
-- admin is not there to watch it, so every action is reported here over the
-- token-authed ingest door and shown in Admin -> Sync health. Rows carry
-- action names, findings, and result summaries - never entity names or
-- free content from either system.
--
-- Applied to sot_research_2026 (the only live DB) on 2026-08-27.

CREATE TABLE IF NOT EXISTS ops_journal (
  id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  at     timestamptz NOT NULL DEFAULT now(),
  actor  text NOT NULL DEFAULT 'ops.py',
  action text NOT NULL,
  why    text NOT NULL,
  ok     boolean NOT NULL,
  detail text
);

CREATE INDEX IF NOT EXISTS ops_journal_at_idx ON ops_journal (at DESC);

ALTER TABLE ops_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_journal FORCE ROW LEVEL SECURITY;

-- Reads are admin-gated at the command layer; writes only enter through the
-- Bearer-token ingest endpoint. Table-level policies stay permissive - this
-- is an audit trail, not row-scoped data.
DROP POLICY IF EXISTS ops_journal_select ON ops_journal;
CREATE POLICY ops_journal_select ON ops_journal FOR SELECT USING (true);
DROP POLICY IF EXISTS ops_journal_insert ON ops_journal;
CREATE POLICY ops_journal_insert ON ops_journal FOR INSERT WITH CHECK (true);

GRANT SELECT, INSERT ON ops_journal TO sot_app;
