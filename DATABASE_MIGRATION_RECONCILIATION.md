# Database migration reconciliation

Last reviewed: 2026-11-22.

## Current production status (22 November 2026)

The live Supabase project reports **90 applied migration records**. The active `supabase/migrations/` directory on this branch contains **90 SQL files** after the seller order pagination migration was applied. A direct comparison of every 14-digit version and migration name reports **90 exact matches, zero missing versions, zero extra files, and zero duplicate version prefixes**.

The seven migration source files that were absent from the repository have been restored from the authoritative `statements[1]` values stored in production's `supabase_migrations.schema_migrations` table:

- `20261114121343_create_marketplace_ads_requests_and_rls.sql`
- `20261114121409_add_marketplace_ads_payment_review_stage.sql`
- `20261114121553_drop_marketplace_ads_old_insert_policy.sql`
- `20261114121600_require_active_product_for_marketplace_ads.sql`
- `20261114121725_drop_marketplace_ads_insert_policy_ambiguous_shop.sql`
- `20261114121726_scope_marketplace_ads_product_to_owned_shop.sql`
- `20261114135451_seed_marketplace_product_categories_and_require_category.sql`

Each recovered file was compared with the corresponding stored SQL statement. The SQL bodies match exactly; only a trailing newline was added where the stored statement did not include one. The seven records have no rollback statements in the production migration-history table. These files are source recovery only: **no migration SQL was executed and the live database was not changed by the source-recovery commit**.

The 87th migration, `20261115082931_disable_legacy_buyer_order_transfer.sql`, was subsequently applied to production after a successful encrypted database-backup workflow. It removes only the buyer INSERT and resubmission RLS policies on `order_payment_submissions`; the table contained zero rows at application time. The buyer historical-read policy and admin-only management policy remain. Post-apply verification confirmed both buyer write policies are absent, seller advertising payment policies remain, and the database migration history records the same version/name as the repository file.

Three repository-history corrections remain documented:

- The live voucher-budget migration version is `20261114141056`; its existing SQL file was named with the incorrect local version `20261114141000`. The filename is corrected without changing its SQL body. The live voucher-budget column and checkout function were inspected and found present.
- The live anonymous catalogue policy migration `20261114171623_separate_anon_public_read_policies_from_admin_helper` was recovered from draft PR #21 and added to the repository. It is already present in the live migration history; no SQL is applied by this commit.
- The local-only aggregate `20261114130000_create_marketplace_ads.sql` is moved to `supabase/migrations-archive/`. Production already has the marketplace-ads table and its later policy/payment columns; the active local aggregate is superseded by the seven smaller production migrations and must not be run.

**Important:** Migration history and source files now reconcile, but this does not authorize applying migrations. Before any future database deployment, create and verify a backup and test the proposed migration in an isolated non-production database. The live database was not changed during this repository reconciliation.


## 18 November 2026 — Android FCM token source recovery

A read-only comparison on 19 November found one migration-source gap: production had 88 applied records while main contained 87 migration files. The missing record was 20261118025532_android_fcm_device_tokens. Its original SQL statement was recovered from the production migration-history record and committed as the canonical file. It creates public.android_push_tokens with a unique FCM token, an auth.users foreign key with cascade deletion, a user index, and row-level security. The live catalog was checked separately: RLS is enabled, there are no client policies, and only service_role has table-level SELECT/INSERT/UPDATE/DELETE grants.

The deployed push-notifications Edge Function was version 22 and already implemented the Android token registration/removal actions plus Firebase HTTP v1 delivery. The repository copy did not contain those handlers even though the Android bridge called them. The deployed source has now been synchronized into supabase/functions/push-notifications/index.ts, and regression checks cover the migration, authenticated owner scoping, active-account guard, token validation, Android bridge, and server-side FCM sender.

No SQL was re-applied and no Edge Function was redeployed in this source-recovery change: both were already present in production. The Firebase service-account environment value was not inspected or exposed; actual FCM delivery remains dependent on that server-side configuration and has not been claimed as device-tested.

## 22 November 2026 — Public table privilege hardening

The 89th migration, `20261122053642_revoke_unneeded_public_table_maintenance_privileges`, was applied through the reviewed migration API after the PostgreSQL 17 regression workflow passed. It removes `TRUNCATE`, `REFERENCES`, `TRIGGER`, and `MAINTAIN` from `anon` and `authenticated` on all existing public tables, and removes those privileges from future public tables created by `postgres`. Ordinary `SELECT`, `INSERT`, `UPDATE`, and `DELETE` grants and all RLS policies remain unchanged. Post-apply verification found zero remaining extra grants, no matching default privileges for `postgres`, and RLS enabled on all 34 public tables. No row data, orders, payments, stock, or account status was changed.

The 90th migration, `20261128023108_seller_order_keyset_pagination`, adds `public.seller_list_orders_page(...)` as an additive, read-only keyset-paginated RPC for the seller dashboard. The PostgreSQL 17 workflow verifies page boundaries, stable timestamp/UUID ordering, no duplicate or missing rows across pages, per-shop item filtering for multi-shop orders, active-seller checks, empty `search_path`, and grants (`authenticated` only; no `anon`). The RPC returns no buyer delivery address or GPS columns and leaves the legacy `seller_list_orders()` function unchanged. It was applied through the Supabase migration connector after the isolated database test passed. It changes no existing rows, orders, stock, payments, profiles, or Storage objects.

All 34 current public tables are owned by `postgres`. The separate default ACL owned by `supabase_admin` remains platform-managed because the migration executor is not a member of that superuser role; no current public table is owned by `supabase_admin`. No role membership or privilege escalation was attempted. The CI regression test simulates the non-superuser `postgres` migration owner and verifies existing and future `postgres`-owned tables.

## Historical baseline (14 November 2026)


## Canonical migration history

At the time of this historical reconciliation, the live Supabase project had **72 applied migration records**. The repository previously had 95 SQL files directly inside `supabase/migrations/`, with duplicate version prefixes and local prefixes that did not match the live 14-digit migration versions.

This reconciliation changes **filenames and locations only**; the SQL bodies of all files are preserved byte-for-byte:

- The 61 files from the 12 November reconciliation remain in `supabase/migrations/`; three additional forward migrations were added before 14 November, bringing the active set to 64.
- 34 historical files had already been archived in `supabase/migrations-archive/` at that time; the 15 November reconciliation adds one superseded aggregate migration to the archive.
- On 14 November, the 65th and 66th migrations were applied and committed: `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` and `20261114025139_fix_driver_application_review_trim_function.sql`. Six subsequent forward migrations brought the canonical and live history to 72 records: `20261114025617_harden_driver_delivery_status_role_and_null_validation.sql`, `20261114030034_support_multi_shop_order_commissions.sql`, `20261114030104_tighten_buyer_receipt_and_commission_review.sql`, `20261114030136_require_buyer_role_for_fee_actions.sql`, `20261114030338_report_commission_paid_at_payment_time.sql`, and `20261114032016_report_delivered_metrics_by_delivery_date.sql`.

The five historical filename equivalents are now canonicalized to the exact live migration names:

| Live version | Live migration name | Previous repository filename |
| --- | --- | --- |
| `20261111151328` | `require_buyer_receipt_before_delivery_fee_confirmation` | `202611110006_require_receipt_before_delivery_fee_confirmation.sql` |
| `20261111153148` | `require_buyer_receipt_before_delivery_fee_dispute` | `202611110009_require_receipt_before_delivery_fee_dispute.sql` |
| `20261111172816` | `restrict_push_webhook_token_lookup_to_service_role` | `202611110022_restrict_push_webhook_token_lookup.sql` |
| `20261111174121` | `fix_rating_insert_policy_qualification` | `202611120002_fix_rating_insert_policies.sql` |
| `20261112033138` | `protect_active_driver_documents_from_owner_deletion` | `202611120020_protect_active_driver_documents.sql` |

## 14 November forward migration

The live `driver_profiles_read_scoped` policy was already narrower than the older canonical policy from `20261111182828_consolidate_permissive_select_policies.sql`, but that production restriction was not represented by a later canonical migration. The 65th migration `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` records the restriction in migration history. The 66th migration `20261114025139_fix_driver_application_review_trim_function.sql` redefines the admin driver-application review RPC to use `pg_catalog.btrim` for both identity-document paths and to verify both files exist in the private Storage bucket before approval. It changes no existing application or driver records.

The policy permits a driver to read their own profile, an administrator to read profiles for dispatch, and a buyer or seller to read a driver's vehicle profile only when that driver is assigned to an order the current user is allowed to access. The check uses the active-account-aware `current_user_can_read_delivery_order(uuid)` helper. No driver, order, stock, payment, or Storage rows were changed.

## 14 November follow-up migrations (67–72)\n\nThe 67th migration hardens driver delivery status updates with active-driver role, ownership, transition, and null validation. The 68th records commission entries per shop for multi-shop orders. The 69th tightens buyer receipt confirmation and admin commission-payment review. The 70th requires the buyer role for delivery-fee confirmation and dispute actions. The 71st groups paid commission by payment-review time. The 72nd corrects marketplace reporting so delivered-order counts, delivered sales, discounts, and delivery fees are grouped by the actual `delivered` status-history timestamp; order creation counts remain grouped by order creation time. The reporting function remains admin-only, retains the 366-day range limit, uses Asia/Jakarta day grouping, and changes no transactional rows.\n\n## Archived files

The 34 archived files are preserved unchanged:

- 27 legacy numbered migrations (`001`–`025`, including the duplicate `003` files) from the earlier schema lineage.
- Two earlier bootstrap files (`202611060001_initial_schema.sql` and `202611060002_moderation_guard.sql`). Their old `stores`, `role_memberships`, and related table model is not present in the current production schema.
- Five SQL files whose effects are already present in production but which are not recorded as separate migration-history rows: trigger-function permission hardening, profile write-column restrictions, active-account guards on rating-summary RPCs, and admin-only product/shop status update privileges. These were verified against the live catalog before archival.

The archive directory is for historical reference only. Do not copy archived files back into `supabase/migrations/` or execute them against production.

## Safe operating procedure

1. Before any database deployment, run `supabase migration list --remote` with the intended project linked/selected explicitly.
2. Confirm that all existing local and remote versions match and that there are **zero unexpected pending migrations**.
3. Create future migrations with `supabase migration new <descriptive_name>`; keep the generated unique timestamp and filename.
4. Apply each new migration once, through the reviewed migration workflow. Do not manually apply SQL and leave its migration file untracked.
5. Never run all SQL files as a batch, and never edit `supabase_migrations.schema_migrations` manually to hide drift.

Supabase CLI v3 changed database commands to target the local stack by default; use explicit `--remote` for a remote migration-list check and review the CLI v3 migration guide before changing automation.

## Verification performed (14 November historical baseline)

- Live migration history was read using the Supabase migration-list endpoint: 66 records, including `20261114024945_scope_driver_profile_visibility_to_related_orders` and `20261114025139_fix_driver_application_review_trim_function`.
- Every live version/name pair has exactly one canonical repository file after this reconciliation.
- The canonical directory has unique 14-digit version prefixes and no duplicate versions.
- The five archived-but-applied SQL effects were checked in the live catalog: helper ACLs and `search_path`, profile column grants, rating-summary function definitions, and product/shop status grants plus guard triggers.
- The two old bootstrap table names were confirmed absent from the current public schema.
- The 65th migration changes only the `driver_profiles_read_scoped` SELECT policy; no user, order, stock, payment, or Storage data was changed. The 72nd migration only replaces the admin statistics function; it does not modify transactional rows.

## Canonical migration history

The live Supabase project has **72 applied migration records**. The repository previously had 95 SQL files directly inside `supabase/migrations/`, with duplicate version prefixes and local prefixes that did not match the live 14-digit migration versions.

This reconciliation changes **filenames and locations only**; the SQL bodies of all files are preserved byte-for-byte:

- The 61 files from the 12 November reconciliation remain in `supabase/migrations/`; three additional forward migrations were added before 14 November, bringing the active set to 64.
- 34 historical files remain unchanged in `supabase/migrations-archive/`, outside the Supabase CLI migration scan directory.
- On 14 November, the 65th and 66th migrations were applied and committed: `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` and `20261114025139_fix_driver_application_review_trim_function.sql`. Six subsequent forward migrations brought the canonical and live history to 72 records: `20261114025617_harden_driver_delivery_status_role_and_null_validation.sql`, `20261114030034_support_multi_shop_order_commissions.sql`, `20261114030104_tighten_buyer_receipt_and_commission_review.sql`, `20261114030136_require_buyer_role_for_fee_actions.sql`, `20261114030338_report_commission_paid_at_payment_time.sql`, and `20261114032016_report_delivered_metrics_by_delivery_date.sql`.

The five historical filename equivalents are now canonicalized to the exact live migration names:

| Live version | Live migration name | Previous repository filename |
| --- | --- | --- |
| `20261111151328` | `require_buyer_receipt_before_delivery_fee_confirmation` | `202611110006_require_receipt_before_delivery_fee_confirmation.sql` |
| `20261111153148` | `require_buyer_receipt_before_delivery_fee_dispute` | `202611110009_require_receipt_before_delivery_fee_dispute.sql` |
| `20261111172816` | `restrict_push_webhook_token_lookup_to_service_role` | `202611110022_restrict_push_webhook_token_lookup.sql` |
| `20261111174121` | `fix_rating_insert_policy_qualification` | `202611120002_fix_rating_insert_policies.sql` |
| `20261112033138` | `protect_active_driver_documents_from_owner_deletion` | `202611120020_protect_active_driver_documents.sql` |

## 14 November forward migration

The live `driver_profiles_read_scoped` policy was already narrower than the older canonical policy from `20261111182828_consolidate_permissive_select_policies.sql`, but that production restriction was not represented by a later canonical migration. The 65th migration `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` records the restriction in migration history. The 66th migration `20261114025139_fix_driver_application_review_trim_function.sql` redefines the admin driver-application review RPC to use `pg_catalog.btrim` for both identity-document paths and to verify both files exist in the private Storage bucket before approval. It changes no existing application or driver records.

The policy permits a driver to read their own profile, an administrator to read profiles for dispatch, and a buyer or seller to read a driver's vehicle profile only when that driver is assigned to an order the current user is allowed to access. The check uses the active-account-aware `current_user_can_read_delivery_order(uuid)` helper. No driver, order, stock, payment, or Storage rows were changed.

## 14 November follow-up migrations (67–72)\n\nThe 67th migration hardens driver delivery status updates with active-driver role, ownership, transition, and null validation. The 68th records commission entries per shop for multi-shop orders. The 69th tightens buyer receipt confirmation and admin commission-payment review. The 70th requires the buyer role for delivery-fee confirmation and dispute actions. The 71st groups paid commission by payment-review time. The 72nd corrects marketplace reporting so delivered-order counts, delivered sales, discounts, and delivery fees are grouped by the actual `delivered` status-history timestamp; order creation counts remain grouped by order creation time. The reporting function remains admin-only, retains the 366-day range limit, uses Asia/Jakarta day grouping, and changes no transactional rows.\n\n## Archived files

The 34 archived files are preserved unchanged:

- 27 legacy numbered migrations (`001`–`025`, including the duplicate `003` files) from the earlier schema lineage.
- Two earlier bootstrap files (`202611060001_initial_schema.sql` and `202611060002_moderation_guard.sql`). Their old `stores`, `role_memberships`, and related table model is not present in the current production schema.
- Five SQL files whose effects are already present in production but which are not recorded as separate migration-history rows: trigger-function permission hardening, profile write-column restrictions, active-account guards on rating-summary RPCs, and admin-only product/shop status update privileges. These were verified against the live catalog before archival.

The archive directory is for historical reference only. Do not copy archived files back into `supabase/migrations/` or execute them against production.

## Safe operating procedure

1. Before any database deployment, run `supabase migration list --remote` with the intended project linked/selected explicitly.
2. Confirm that all existing local and remote versions match and that there are **zero unexpected pending migrations**.
3. Create future migrations with `supabase migration new <descriptive_name>`; keep the generated unique timestamp and filename.
4. Apply each new migration once, through the reviewed migration workflow. Do not manually apply SQL and leave its migration file untracked.
5. Never run all SQL files as a batch, and never edit `supabase_migrations.schema_migrations` manually to hide drift.

Supabase CLI v3 changed database commands to target the local stack by default; use explicit `--remote` for a remote migration-list check and review the CLI v3 migration guide before changing automation.

## Verification performed

- Live migration history was read using the Supabase migration-list endpoint: 66 records, including `20261114024945_scope_driver_profile_visibility_to_related_orders` and `20261114025139_fix_driver_application_review_trim_function`.
- Every live version/name pair has exactly one canonical repository file after this reconciliation.
- The canonical directory has unique 14-digit version prefixes and no duplicate versions.
- The five archived-but-applied SQL effects were checked in the live catalog: helper ACLs and `search_path`, profile column grants, rating-summary function definitions, and product/shop status grants plus guard triggers.
- The two old bootstrap table names were confirmed absent from the current public schema.
- The 65th migration changes only the `driver_profiles_read_scoped` SELECT policy; no user, order, stock, payment, or Storage data was changed. The 72nd migration only replaces the admin statistics function; it does not modify transactional rows.
