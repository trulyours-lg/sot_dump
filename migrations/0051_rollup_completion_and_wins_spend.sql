-- 0051_rollup_completion_and_wins_spend.sql
-- Portfolio analytics phase A/D (Lily picked features 1+8, 2026-09-09):
-- 1. app_tf_rollups() gains tasks_total + tasks_done so every user — rollup-
--    only included — can see a TF-level completion %. Same anonymization
--    boundary as 0033: counts and dates only.
-- 2. app_tf_wins_spend(): the LibreChat connector's tool 7 (wins vs spend per
--    TF) as an in-app counts-only channel. Spend = disbursements linked to a
--    project in the TF; the NULL problem_area_id row carries the money with
--    NO project link, so the UI can say honestly how many dollars are
--    unattributed instead of hiding them. Amounts are aggregates, not rows —
--    no payee, no memo, nothing a rollup user shouldn't see.
-- Apply to sot_research_2026.

BEGIN;

-- Return shape changes, so CREATE OR REPLACE is not enough.
DROP FUNCTION IF EXISTS app_tf_rollups();

CREATE FUNCTION app_tf_rollups()
RETURNS TABLE (
  problem_area_id      uuid,
  projects_total       bigint,
  projects_active      bigint,
  projects_blocked     bigint,
  projects_on_hold     bigint,
  projects_not_started bigint,
  projects_done        bigint,
  tasks_open           bigint,
  tasks_overdue        bigint,
  tasks_total          bigint,
  tasks_done           bigint,
  wins_total           bigint,
  last_activity        timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pa.id,
         count(p.id),
         count(p.id) FILTER (WHERE p.status = 'in_progress'),
         count(p.id) FILTER (WHERE p.status = 'blocked'),
         count(p.id) FILTER (WHERE p.status = 'on_hold'),
         count(p.id) FILTER (WHERE p.status = 'not_started'),
         count(p.id) FILTER (WHERE p.status = 'done'),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND t.status NOT IN ('done', 'cancelled')),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND t.status NOT IN ('done', 'cancelled')
             AND t.due_date < CURRENT_DATE),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND t.status <> 'cancelled'),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND t.status = 'done'),
         (SELECT count(*) FROM wins w JOIN projects p3 ON p3.id = w.project_id
           WHERE p3.problem_area_id = pa.id),
         max(p.updated_at)
    FROM problem_areas pa
    LEFT JOIN projects p ON p.problem_area_id = pa.id
   WHERE pa.owner_name IS NOT NULL
   GROUP BY pa.id;
$$;

REVOKE ALL ON FUNCTION app_tf_rollups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_tf_rollups() TO sot_app;

-- Wins vs spend per TF. One row per TF plus one row with problem_area_id NULL
-- for disbursements that carry no project link (today: all of them).
CREATE OR REPLACE FUNCTION app_tf_wins_spend()
RETURNS TABLE (
  problem_area_id uuid,
  projects_total  bigint,
  projects_done   bigint,
  wins_total      bigint,
  spend_total     numeric,
  disbursements   bigint
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pa.id,
         (SELECT count(*) FROM projects p WHERE p.problem_area_id = pa.id),
         (SELECT count(*) FROM projects p WHERE p.problem_area_id = pa.id
            AND p.status = 'done'),
         (SELECT count(*) FROM wins w JOIN projects p ON p.id = w.project_id
           WHERE p.problem_area_id = pa.id),
         COALESCE((SELECT sum(d.amount) FROM disbursements d
                    JOIN projects p ON p.id = d.project_id
                   WHERE p.problem_area_id = pa.id), 0),
         (SELECT count(*) FROM disbursements d
            JOIN projects p ON p.id = d.project_id
           WHERE p.problem_area_id = pa.id)
    FROM problem_areas pa
   WHERE pa.owner_name IS NOT NULL
  UNION ALL
  SELECT NULL,
         0, 0, 0,
         COALESCE(sum(d.amount), 0),
         count(*)
    FROM disbursements d
   WHERE d.project_id IS NULL;
$$;

REVOKE ALL ON FUNCTION app_tf_wins_spend() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_tf_wins_spend() TO sot_app;

COMMIT;
