-- 0055: allow 'effort' through the write-back queue's field whitelist.
--
-- 0053 gave projects an effort column (Anytype "Effort" select, S/M/L) and
-- the sync pulls it; 2026-09-14 Lily asked for the project drawer to edit it
-- too. Same intent-only path as status/priority (0039): SOT queues, the
-- daemon compare-and-sets in Anytype, the next pull confirms. The CHECK is
-- the guarantee that free text can never be queued — 'effort' is a closed
-- S/M/L vocabulary on both sides, so widening it keeps that property.
--
-- The constraint carries the name Postgres generated for 0039's anonymous
-- CHECK (verified on the live DB before authoring).
ALTER TABLE anytype_edit_queue
  DROP CONSTRAINT anytype_edit_queue_field_check;
ALTER TABLE anytype_edit_queue
  ADD CONSTRAINT anytype_edit_queue_field_check
  CHECK (field IN ('status','priority','startDate','dueDate','plannedBudget','effort'));
