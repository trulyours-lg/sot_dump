-- 0052_tf_rollup_history.sql
-- Portfolio analytics phase C (Lily, 2026-09-09): SOT only ever knew "now" —
-- rollups compute live, snapshots were retired in v3 Step 6. This table gives
-- rollups a memory: the SERVER snapshots its own app_tf_rollups() output once
-- a day (a background task in server.rs — no human, no cron, works the same
-- on the laptop task and the VM's sot.service). Counts only, same
-- anonymization boundary as the live function, hence the open SELECT policy:
-- any authenticated user may see the trend, exactly like the live rollups.
-- Apply to sot_research_2026.

BEGIN;

CREATE TABLE tf_rollup_history (
  problem_area_id      uuid NOT NULL REFERENCES problem_areas(id) ON DELETE CASCADE,
  as_of                date NOT NULL,
  projects_total       bigint NOT NULL,
  projects_active      bigint NOT NULL,
  projects_blocked     bigint NOT NULL,
  projects_on_hold     bigint NOT NULL,
  projects_not_started bigint NOT NULL,
  projects_done        bigint NOT NULL,
  tasks_open           bigint NOT NULL,
  tasks_overdue        bigint NOT NULL,
  tasks_total          bigint NOT NULL,
  tasks_done           bigint NOT NULL,
  wins_total           bigint NOT NULL,
  captured_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (problem_area_id, as_of)
);

ALTER TABLE tf_rollup_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE tf_rollup_history FORCE ROW LEVEL SECURITY;

-- Counts only: readable by every session (matches app_tf_rollups access).
CREATE POLICY history_select ON tf_rollup_history
  FOR SELECT USING (true);
-- Written only by the server's own snapshot job; the row content is the
-- output of app_tf_rollups(), so an extra write gate buys nothing.
CREATE POLICY history_insert ON tf_rollup_history
  FOR INSERT WITH CHECK (true);

GRANT SELECT, INSERT ON tf_rollup_history TO sot_app;

COMMIT;
