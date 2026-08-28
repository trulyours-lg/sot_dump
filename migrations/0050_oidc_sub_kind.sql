-- 0050: admit 'oidc_sub' as an identity kind.
--
-- The kx-71 deployment rejected proxy-header identity (their errata,
-- 2026-08-28); the accepted architecture is an in-app OIDC client (sot-c
-- 8a4bab0, sot-app/src-tauri/src/oidc.rs). A signed-in browser resolves as
-- identity kind 'oidc_sub' carrying the Zitadel subject, through the same
-- user_network_identities / pending_identities machinery as every earlier
-- kind. Both tables were created in 0029 with
-- CHECK (kind IN ('mtls_fp','vpn_ip')), so the enrollment-queue insert
-- failed live on first OIDC sign-in (pending_identities_kind_check) and the
-- Admin -> Devices bind would have failed next. Widen both.
--
-- Apply to sot_research_2026 only (the sole live DB).

ALTER TABLE user_network_identities
  DROP CONSTRAINT user_network_identities_kind_check;
ALTER TABLE user_network_identities
  ADD CONSTRAINT user_network_identities_kind_check
  CHECK (kind IN ('mtls_fp', 'vpn_ip', 'oidc_sub'));

ALTER TABLE pending_identities
  DROP CONSTRAINT pending_identities_kind_check;
ALTER TABLE pending_identities
  ADD CONSTRAINT pending_identities_kind_check
  CHECK (kind IN ('mtls_fp', 'vpn_ip', 'oidc_sub'));
