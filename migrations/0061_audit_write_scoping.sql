-- 0061: close the last `WITH CHECK (true)` — audit rows become
-- unforgeable by sessions. (Contract item 10; named by evaluation rounds
-- 4/5: any authenticated session could INSERT into ops_journal — forging
-- "machine actions" in Admin → Sync health — or into tf_rollup_history,
-- poisoning the trend lines the Success view reasons from.)
--
-- Same doctrine as 0060's pre-session stamps: the ONLY write path is a
-- fixed-shape SECURITY DEFINER function, and the shape IS the whitelist.
-- The two real writers:
--   * tf_rollup_history — the server's own hourly snapshot task, which
--     runs on a RAW pool connection (no GUCs); it now calls
--     app_record_rollup_snapshot().
--   * ops_journal — ops.py over the Bearer token path (api_ops_journal);
--     the handler now calls app_record_ops_journal(...).
-- The permissive INSERT policies are DROPPED and not replaced: with RLS
-- forced and no INSERT policy, a direct INSERT is denied outright for
-- sot_app. SELECT stays open on both BY DESIGN (the journal renders in
-- Admin → Sync health; history feeds every user's sparklines).

CREATE OR REPLACE FUNCTION public.app_record_rollup_snapshot()
 RETURNS integer
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH ins AS (
    INSERT INTO tf_rollup_history
      (problem_area_id, as_of, projects_total, projects_active,
       projects_blocked, projects_on_hold, projects_not_started,
       projects_done, tasks_open, tasks_overdue, tasks_total,
       tasks_done, wins_total)
    SELECT problem_area_id, CURRENT_DATE, projects_total, projects_active,
           projects_blocked, projects_on_hold, projects_not_started,
           projects_done, tasks_open, tasks_overdue, tasks_total,
           tasks_done, wins_total
      FROM app_tf_rollups()
    ON CONFLICT (problem_area_id, as_of) DO NOTHING
    RETURNING 1)
  SELECT count(*)::integer FROM ins;
$$;

CREATE OR REPLACE FUNCTION public.app_record_ops_journal(
  actor_in text, action_in text, why_in text, ok_in boolean, detail_in text)
 RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  INSERT INTO ops_journal (actor, action, why, ok, detail)
  VALUES (actor_in, action_in, why_in, ok_in, detail_in);
$$;

DROP POLICY IF EXISTS ops_journal_insert ON ops_journal;
DROP POLICY IF EXISTS history_insert ON tf_rollup_history;
