-- 0060: the authorization fabric becomes DB-DERIVED instead of
-- self-asserted, and gains write policies. (2026-09-15 final evaluation,
-- THE security primary: every RLS policy trusted app.is_admin /
-- app.can_* / app.detail_tfs — strings the application set about itself;
-- the DB never derived a grant from tf_access, and the five control
-- tables had open writes for the shared sot_app role.)
--
-- After this migration the database trusts exactly ONE GUC: app.user_id.
-- Every flag helper and the TF list derive from users / tf_access /
-- tf_submit_rights via STABLE SECURITY DEFINER lookups (owner postgres,
-- so they read those tables regardless of RLS). Setting app.is_admin or
-- app.detail_tfs by hand now does NOTHING. The server keeps binding only
-- app.user_id (sessions AND token paths — code ships with this file).
-- Old binaries that still bind the retired GUCs are harmless: the values
-- are ignored, and they also bind app.user_id, so the deploy window
-- (migration applied, restart pending) stays functional.
--
-- Helper semantics preserved exactly: an unbound/unknown/inactive user
-- yields false / empty — fail closed, same as an unbound GUC before.
-- detail_tfs = tf_access ∪ tf_submit_rights for the user: sessions get
-- their personal grants, the sync token keeps writing under RLS through
-- its submit rights, one derivation for both paths.

CREATE OR REPLACE FUNCTION public.app_is_admin() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.is_admin FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_is_pm() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.is_pm FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_can_access_crm() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_access_crm FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_can_access_csm() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_access_csm FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_can_triage_intake() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_triage_intake FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_can_access_partners() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_access_partners FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_can_edit_projects() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_edit_projects FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

-- exec flag, needed to move app_tf_wins_spend's gate in-DB (below).
CREATE OR REPLACE FUNCTION public.app_can_access_exec() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT u.can_access_exec FROM users u
                        WHERE u.id = app_user_id() AND u.active), false); $$;

CREATE OR REPLACE FUNCTION public.app_detail_tfs() RETURNS uuid[]
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM users u
                            WHERE u.id = app_user_id() AND u.active)
    THEN COALESCE((SELECT array_agg(DISTINCT s.pa) FROM (
           SELECT problem_area_id AS pa FROM tf_access
            WHERE user_id = app_user_id()
           UNION
           SELECT problem_area_id FROM tf_submit_rights
            WHERE user_id = app_user_id()) s), ARRAY[]::uuid[])
    ELSE ARRAY[]::uuid[] END;
$$;
-- app_can_see_pa() is unchanged — it composes the helpers above.

-- ── The second RLS bypass gets its gate IN the function ────────────────
-- app_tf_wins_spend() returns per-TF dollar totals from CRM-gated
-- disbursements; until now the only gate was an if-statement in Rust
-- (rollups.rs). Ungated callers now get zero rows. The Rust check stays
-- as the outer wall (defense in depth, and a friendlier error).
CREATE OR REPLACE FUNCTION public.app_tf_wins_spend()
 RETURNS TABLE(problem_area_id uuid, projects_total bigint, projects_done bigint, wins_total bigint, spend_total numeric, disbursements bigint)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  WITH gate AS (SELECT (app_is_admin() OR app_can_access_exec()) AS ok)
  SELECT pa.id,
         (SELECT count(*) FROM projects p WHERE p.problem_area_id = pa.id
            AND p.archived_at IS NULL),
         (SELECT count(*) FROM projects p WHERE p.problem_area_id = pa.id
            AND p.archived_at IS NULL AND p.status = 'done'),
         (SELECT count(*) FROM wins w JOIN projects p ON p.id = w.project_id
           WHERE p.problem_area_id = pa.id),
         COALESCE((SELECT sum(d.amount) FROM disbursements d
                    JOIN projects p ON p.id = d.project_id
                   WHERE p.problem_area_id = pa.id), 0),
         (SELECT count(*) FROM disbursements d
            JOIN projects p ON p.id = d.project_id
           WHERE p.problem_area_id = pa.id)
    FROM problem_areas pa, gate
   WHERE gate.ok AND pa.owner_name IS NOT NULL
  UNION ALL
  SELECT NULL, 0, 0, 0,
         COALESCE(sum(d.amount), 0), count(*)
    FROM disbursements d
   WHERE d.project_id IS NULL
  -- HAVING, not WHERE: an ungated aggregate still emits one zero-row;
  -- HAVING removes it so ungated callers get exactly nothing.
  HAVING (SELECT ok FROM gate);
$function$;

-- ── Write policies on the authorization fabric ─────────────────────────
-- SELECT stays open on all five: they are read during identity/token
-- resolution BEFORE app.user_id is bound (auth.rs: RESET ALL, then look
-- the identity up) — that justification covers READS ONLY. Writes:
--   * tf_access / tf_submit_rights / user_network_identities — admin only
--     (granting, binding, revoking are Admin-screen actions).
--   * pending_identities — writes admin only; the pre-session queueing of
--     an unknown device (fail-closed enrollment) goes through
--     app_queue_pending_identity() below, so even the INSERT path is a
--     fixed shape rather than an open policy.
--   * api_tokens — admin only; the pre-session last_used_at stamp moves
--     into app_touch_api_token() below.
--   * user_network_identities — admin only; the pre-session last_seen_at
--     stamp moves into app_touch_identity() below.
-- The three SECURITY DEFINER stamps write exactly one fixed column set
-- each — that shape is the guarantee, same doctrine as the ingest structs.

CREATE OR REPLACE FUNCTION public.app_touch_api_token(token_id uuid)
 RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ UPDATE api_tokens SET last_used_at = now() WHERE id = token_id; $$;

CREATE OR REPLACE FUNCTION public.app_touch_identity(identity_id uuid)
 RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ UPDATE user_network_identities SET last_seen_at = now()
       WHERE id = identity_id; $$;

CREATE OR REPLACE FUNCTION public.app_queue_pending_identity(value_in text, kind_in text)
 RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ INSERT INTO pending_identities (value, kind) VALUES (value_in, kind_in)
       ON CONFLICT (value) DO UPDATE SET last_seen = now(); $$;

ALTER TABLE tf_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE tf_access FORCE ROW LEVEL SECURITY;
CREATE POLICY tf_access_select ON tf_access FOR SELECT USING (true);
CREATE POLICY tf_access_insert ON tf_access FOR INSERT WITH CHECK (app_is_admin());
CREATE POLICY tf_access_update ON tf_access FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
CREATE POLICY tf_access_delete ON tf_access FOR DELETE USING (app_is_admin());

ALTER TABLE tf_submit_rights ENABLE ROW LEVEL SECURITY;
ALTER TABLE tf_submit_rights FORCE ROW LEVEL SECURITY;
CREATE POLICY tf_submit_rights_select ON tf_submit_rights FOR SELECT USING (true);
CREATE POLICY tf_submit_rights_insert ON tf_submit_rights FOR INSERT WITH CHECK (app_is_admin());
CREATE POLICY tf_submit_rights_update ON tf_submit_rights FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
CREATE POLICY tf_submit_rights_delete ON tf_submit_rights FOR DELETE USING (app_is_admin());

ALTER TABLE user_network_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_network_identities FORCE ROW LEVEL SECURITY;
CREATE POLICY uni_select ON user_network_identities FOR SELECT USING (true);
CREATE POLICY uni_insert ON user_network_identities FOR INSERT WITH CHECK (app_is_admin());
CREATE POLICY uni_update ON user_network_identities FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
CREATE POLICY uni_delete ON user_network_identities FOR DELETE USING (app_is_admin());

ALTER TABLE pending_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_identities FORCE ROW LEVEL SECURITY;
CREATE POLICY pend_select ON pending_identities FOR SELECT USING (true);
CREATE POLICY pend_insert ON pending_identities FOR INSERT WITH CHECK (app_is_admin());
CREATE POLICY pend_update ON pending_identities FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
CREATE POLICY pend_delete ON pending_identities FOR DELETE USING (app_is_admin());

ALTER TABLE api_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_tokens FORCE ROW LEVEL SECURITY;
CREATE POLICY api_tokens_select ON api_tokens FOR SELECT USING (true);
CREATE POLICY api_tokens_insert ON api_tokens FOR INSERT WITH CHECK (app_is_admin());
CREATE POLICY api_tokens_update ON api_tokens FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
CREATE POLICY api_tokens_delete ON api_tokens FOR DELETE USING (app_is_admin());
