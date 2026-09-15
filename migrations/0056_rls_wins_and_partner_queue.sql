-- 0056: two RLS repairs found by the 2026-09-15 external-evaluation dry run.
--
-- (1) wins: RLS is OFF on the live DB (relrowsecurity=false, FORCE still
--     set, zero policies) — a state NO migration in 0001..0055 produces:
--     0013 ENABLEd RLS with wins_select USING(true) + wins_modify
--     USING(app_is_pm()), 0021 FORCEd it; something disabled it by hand,
--     outside the ledger. The app still assumes the 0013 policies exist
--     (wins.rs: "non-PM writes get rejected at the DB"), so create/update
--     wins are currently ungated. Re-enable and recreate the policies.
--     SELECT stays USING(true) on purpose — "wins stay open as evidence"
--     (0029-era decision). modify widens app_is_pm() to include admins,
--     matching the Rust require_pm (is_pm OR is_admin) so the two walls
--     agree.
--
-- (2) partner_edit_queue: the UPDATE policy was USING(true) WITH CHECK
--     (true). 0040's comment justified it with "the token path binds no
--     flags" — stale: server.rs bind_partner_admin() has bound
--     app.is_admin='true' on the partner drain connection since the
--     feature shipped, and it already refuses non-admin tokens. Scope the
--     policy to admins; the daemon's ack keeps working, browser sessions
--     without admin can no longer rewrite pending partner edits.

ALTER TABLE wins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS wins_select ON wins;
DROP POLICY IF EXISTS wins_modify ON wins;
CREATE POLICY wins_select ON wins FOR SELECT USING (true);
CREATE POLICY wins_modify ON wins FOR ALL
  USING (app_is_pm() OR app_is_admin())
  WITH CHECK (app_is_pm() OR app_is_admin());

DROP POLICY IF EXISTS partner_edit_queue_update ON partner_edit_queue;
CREATE POLICY partner_edit_queue_update ON partner_edit_queue
  FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
