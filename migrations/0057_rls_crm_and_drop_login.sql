-- 0057: extend RLS to the two large guard-only CRM tables, and drop the
-- dead login machinery. Items 3 and 5 of the 2026-09-15 evaluation follow-up.
--
-- contacts (785 rows): read/written ONLY by CRM (crm.rs), CSM (csm.rs) and
-- the global-search CRM module (search.rs, inside `if can_crm`) — all
-- session paths whose flags are bound as GUCs per request. One policy
-- mirrors the contributions_crm pattern; app_is_admin() is included
-- explicitly because app_is_pm() is the raw is_pm flag, not require_pm's
-- (is_pm OR is_admin).
--
-- organizations (591 rows): SELECT stays open ON PURPOSE — names are river
-- codenames, and non-CRM readers exist (budget.rs vendor-contract join,
-- csm.rs, the Executive funder lens via org_tf_interests). Writes are
-- CRM-gated.
--
-- DELIBERATELY LEFT WITHOUT RLS (documented for tests/rls_regression.py):
--   api_tokens, pending_identities, user_network_identities, tf_access,
--   tf_submit_rights — read during identity/token resolution BEFORE the
--   session GUCs exist (auth.rs runs RESET ALL then looks identity up);
--   a restrictive policy there locks every user out.
--   categories, problem_areas, initiatives, legacy_pa_tf_map — taxonomy,
--   readable by every tier including rollup-only.
--   tf_snapshots, tf_finance, funding_summary, okr_*, attachments — parked
--   (inert since Step 6); sot_deploy_ledger — deploy tooling, no app path.
--
-- Dead login drop: v3 has NO LOGINS (identity comes from the connection),
-- but 0023's password machinery survived: user_secrets (5 bcrypt hashes),
-- login_failures, app_login_authenticate() SECURITY DEFINER and
-- app_admin_set_user_password() SECURITY DEFINER — all EXECUTE-granted to
-- sot_app. Live attack surface for a feature the system does not have.
-- The one caller (set_user_password in users.rs + its route) is removed in
-- the same commit; nothing in the SPA ever called it.

ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS contacts_crm ON contacts;
CREATE POLICY contacts_crm ON contacts
  USING (app_is_admin() OR app_is_pm() OR app_can_access_crm() OR app_can_access_csm())
  WITH CHECK (app_is_admin() OR app_is_pm() OR app_can_access_crm() OR app_can_access_csm());

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS organizations_select ON organizations;
DROP POLICY IF EXISTS organizations_insert ON organizations;
DROP POLICY IF EXISTS organizations_update ON organizations;
DROP POLICY IF EXISTS organizations_delete ON organizations;
CREATE POLICY organizations_select ON organizations FOR SELECT USING (true);
CREATE POLICY organizations_insert ON organizations FOR INSERT
  WITH CHECK (app_is_admin() OR app_is_pm() OR app_can_access_crm());
CREATE POLICY organizations_update ON organizations FOR UPDATE
  USING (app_is_admin() OR app_is_pm() OR app_can_access_crm())
  WITH CHECK (app_is_admin() OR app_is_pm() OR app_can_access_crm());
CREATE POLICY organizations_delete ON organizations FOR DELETE
  USING (app_is_admin() OR app_is_pm() OR app_can_access_crm());

-- vendor_contracts (0021_vendor_contracts, the numbering-collision file)
-- enabled RLS but never FORCEd it — the only such table. FORCE only affects
-- the table owner, but the invariant "every RLS table is forced" is what
-- tests/rls_regression.py asserts, so make it uniform.
ALTER TABLE vendor_contracts FORCE ROW LEVEL SECURITY;

DROP FUNCTION IF EXISTS app_login_authenticate(email_in text, password_in text);
DROP FUNCTION IF EXISTS app_login_lock_seconds(email_in text, window_seconds integer);
DROP FUNCTION IF EXISTS app_admin_set_user_password(target_user_id uuid, new_hash text);
DROP TABLE IF EXISTS login_failures;
DROP TABLE IF EXISTS user_secrets;
