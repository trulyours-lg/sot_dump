-- 0059: deletion propagation — absent rows get archived, rollups stop
-- counting them. (2026-09-15 final evaluation, THE architecture primary:
-- the sync was upsert-only, so a project/task deleted, archived or moved
-- out of a synced space in Anytype stayed in Postgres forever, inflating
-- app_tf_rollups() and — via the daily snapshot — tf_rollup_history,
-- permanently. The C-level number could only drift upward.)
--
-- Mechanism: the sync client now sends, per space, the FULL list of
-- project/task object ids it saw this cycle (including ids it withheld as
-- unminted — ids are opaque, no vault needed). The server archives synced
-- rows of that space that are absent from a NONEMPTY list; an empty list
-- means "old client or failed enumeration" and archives nothing. A row
-- that reappears is un-archived by the normal upsert (archived_at = NULL).
-- Archived ≠ deleted: history, wins and the row itself stay; list queries
-- and the rollups just stop counting it. Wins of archived projects still
-- count — they are recorded evidence, not live work.

ALTER TABLE projects ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE tasks    ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE OR REPLACE FUNCTION public.app_tf_rollups()
 RETURNS TABLE(problem_area_id uuid, projects_total bigint, projects_active bigint, projects_blocked bigint, projects_on_hold bigint, projects_not_started bigint, projects_done bigint, tasks_open bigint, tasks_overdue bigint, tasks_total bigint, tasks_done bigint, wins_total bigint, last_activity timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pa.id,
         count(p.id),
         count(p.id) FILTER (WHERE p.status = 'in_progress'),
         count(p.id) FILTER (WHERE p.status = 'blocked'),
         count(p.id) FILTER (WHERE p.status = 'on_hold'),
         count(p.id) FILTER (WHERE p.status = 'not_started'),
         count(p.id) FILTER (WHERE p.status = 'done'),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND p2.archived_at IS NULL AND t.archived_at IS NULL
             AND t.status NOT IN ('done', 'cancelled')),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND p2.archived_at IS NULL AND t.archived_at IS NULL
             AND t.status NOT IN ('done', 'cancelled')
             AND t.due_date < CURRENT_DATE),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND p2.archived_at IS NULL AND t.archived_at IS NULL
             AND t.status <> 'cancelled'),
         (SELECT count(*) FROM tasks t JOIN projects p2 ON p2.id = t.project_id
           WHERE p2.problem_area_id = pa.id
             AND p2.archived_at IS NULL AND t.archived_at IS NULL
             AND t.status = 'done'),
         -- wins of archived projects still count: recorded evidence.
         (SELECT count(*) FROM wins w JOIN projects p3 ON p3.id = w.project_id
           WHERE p3.problem_area_id = pa.id),
         max(p.updated_at)
    FROM problem_areas pa
    LEFT JOIN projects p ON p.problem_area_id = pa.id
                        AND p.archived_at IS NULL
   WHERE pa.owner_name IS NOT NULL
   GROUP BY pa.id;
$function$;
