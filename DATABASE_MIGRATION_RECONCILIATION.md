# Database migration reconciliation

Last reconciled: 2026-11-12.

The live Supabase project reports 59 applied migrations. The repository contains 90 SQL migration files, including the original baseline and follow-up repair files. After removing the numeric filename prefixes, every applied database migration has a corresponding repository migration or a documented naming equivalent below.

## Naming equivalents

| Applied Supabase migration name | Repository file |
| --- | --- |
| `require_buyer_receipt_before_delivery_fee_confirmation` | `supabase/migrations/202611110006_require_receipt_before_delivery_fee_confirmation.sql` |
| `require_buyer_receipt_before_delivery_fee_dispute` | `supabase/migrations/202611110009_require_receipt_before_delivery_fee_dispute.sql` |
| `restrict_push_webhook_token_lookup_to_service_role` | `supabase/migrations/202611110022_restrict_push_webhook_token_lookup.sql` |
| `fix_rating_insert_policy_qualification` | `supabase/migrations/202611120002_fix_rating_insert_policies.sql` |
| `protect_active_driver_documents_from_owner_deletion` | `supabase/migrations/202611120020_protect_active_driver_documents.sql` |

## Checkout rollout history

The two initial checkout migrations were missing from the repository and have now been mirrored:

- `202611110001_secure_server_side_delivery_checkout.sql`
- `202611110002_restore_legacy_checkout_until_secure_checkout_rollout.sql`

The next migration, `202611110003_revoke_legacy_checkout_rpc.sql`, removes browser execution rights from the temporary legacy checkout RPC. The secure checkout RPC remains service-role-only. The mirrored secure checkout definition includes the current active-buyer validation.

## Safety note

This document records source-history reconciliation only. The live database already has these migrations applied. Do not manually replay these files against the current production database. Never apply all repository SQL files as a batch: the repository also retains historical baselines, repairs, and alternative migration paths.
