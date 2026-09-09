-- 0053_projects_effort.sql
-- Portfolio analytics phase E (Lily, 2026-09-09): "where do our efforts fall"
-- needs a weight, not a count. Leads set an "Effort" select property (S/M/L)
-- on the project in Anytype; the sync carries it here. Closed vocabulary — a
-- letter can't leak a name, so the sync payload shape stays the OpSec
-- guarantee. NULL = not sized yet (every project today).
-- Apply to sot_research_2026.

BEGIN;

ALTER TABLE projects
  ADD COLUMN effort text CHECK (effort IN ('S', 'M', 'L'));

COMMENT ON COLUMN projects.effort IS
  'T-shirt effort size authored in Anytype (property "Effort": S/M/L); synced, not edited in SOT';

COMMIT;
