-- 0054_success_profiles.sql
-- Success view (Lily 2026-09-09/10): the manager RANKS the dimensions of
-- success per scope — everything above their protect line is a real failure
-- when it slips, everything below is a declared trade-off ("something's got
-- to give"). SOT stores ONLY structure: a ranked closed vocabulary plus
-- numeric thresholds in fixed columns — no free text can enter this table by
-- shape, the same guarantee as the sync payload. The "why" prose stays in
-- Anytype. Apply to sot_research_2026.

BEGIN;

CREATE TABLE success_profiles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             text NOT NULL CHECK (kind IN ('company', 'domain', 'tf')),
  problem_area_id  uuid REFERENCES problem_areas(id) ON DELETE CASCADE,
  category_id      smallint REFERENCES categories(id) ON DELETE CASCADE,
  -- exactly one referent per kind
  CHECK ((kind = 'tf')      = (problem_area_id IS NOT NULL)),
  CHECK ((kind = 'domain')  = (category_id IS NOT NULL)),
  -- The ranking: dimensions in priority order, drawn from the closed set.
  dims_ranked      text[] NOT NULL
    CHECK (dims_ranked <@ ARRAY['timeliness','volume','blockers','coverage',
                                'focus','impact','money']::text[]
           AND cardinality(dims_ranked) BETWEEN 3 AND 7),
  -- Ranks 1..protect_count are PROTECTED; the rest are GIVEN.
  protect_count    int NOT NULL CHECK (protect_count BETWEEN 1 AND 6),
  -- Numeric thresholds, one fixed column per dimension (shape = guarantee).
  thr_overdue_pct    numeric NOT NULL DEFAULT 10  CHECK (thr_overdue_pct   BETWEEN 0 AND 100),
  thr_done_per_week  numeric NOT NULL DEFAULT 3   CHECK (thr_done_per_week >= 0),
  thr_blocker_days   int     NOT NULL DEFAULT 14  CHECK (thr_blocker_days  >= 0),
  thr_dark_days      int     NOT NULL DEFAULT 30  CHECK (thr_dark_days     >= 0),
  thr_wip            int     NOT NULL DEFAULT 6   CHECK (thr_wip           >= 0),
  thr_wins_quarter   int     NOT NULL DEFAULT 1   CHECK (thr_wins_quarter  >= 0),
  thr_budget_pct     numeric NOT NULL DEFAULT 100 CHECK (thr_budget_pct    >= 0),
  updated_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- One profile per scope.
CREATE UNIQUE INDEX success_profiles_company ON success_profiles (kind) WHERE kind = 'company';
CREATE UNIQUE INDEX success_profiles_domain  ON success_profiles (category_id) WHERE kind = 'domain';
CREATE UNIQUE INDEX success_profiles_tf      ON success_profiles (problem_area_id) WHERE kind = 'tf';

ALTER TABLE success_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE success_profiles FORCE ROW LEVEL SECURITY;

-- Read: everyone — the profile is counts/vocabulary, no names, and every
-- user is entitled to know what "success" means for what they can see.
CREATE POLICY success_select ON success_profiles FOR SELECT USING (true);
-- Write: admins/PMs anywhere; a TF's profile also by anyone holding that
-- TF's detail grant (the working definition of "the lead" until a lead role
-- exists). Company/domain profiles stay admin/PM-only.
CREATE POLICY success_modify ON success_profiles
  USING (app_is_admin() OR app_is_pm()
         OR (kind = 'tf' AND problem_area_id = ANY (app_detail_tfs())))
  WITH CHECK (app_is_admin() OR app_is_pm()
         OR (kind = 'tf' AND problem_area_id = ANY (app_detail_tfs())));

GRANT SELECT, INSERT, UPDATE, DELETE ON success_profiles TO sot_app;

COMMIT;
