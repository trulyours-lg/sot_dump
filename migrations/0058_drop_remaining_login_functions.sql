-- 0058: drop the five REMAINING login-era SECURITY DEFINER functions.
--
-- Found by the 2026-09-15 Fable re-evaluation, one pass after 0057 dropped
-- the three obvious ones (authenticate / admin_set / lock_seconds): the
-- 0023 password work also installed these five, all SECURITY DEFINER, all
-- still EXECUTE-granted to sot_app, none referenced by any code, and every
-- one now broken anyway — they read user_secrets / login_failures, which
-- 0057 removed. Lesson recorded: when killing a feature's DB surface,
-- enumerate by pg_proc pattern, not from memory of what the migration
-- added.

DROP FUNCTION IF EXISTS app_bcrypt_matches(password_in text, hash_in text);
DROP FUNCTION IF EXISTS app_change_own_password(old_password text, new_hash text);
DROP FUNCTION IF EXISTS app_set_own_password(new_hash text);
DROP FUNCTION IF EXISTS app_record_login_failure(email_in text, max_failures integer, window_seconds integer);
DROP FUNCTION IF EXISTS app_clear_login_failures(email_in text);
