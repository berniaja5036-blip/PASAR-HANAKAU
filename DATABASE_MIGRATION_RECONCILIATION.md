# Database migration reconciliation

Last reconciled: 2026-11-14.

## Canonical migration history

The live Supabase project has **66 applied migration records**. The repository previously had 95 SQL files directly inside `supabase/migrations/`, with duplicate version prefixes and local prefixes that did not match the live 14-digit migration versions.

This reconciliation changes **filenames and locations only**; the SQL bodies of all files are preserved byte-for-byte:

- The 61 files from the 12 November reconciliation remain in `supabase/migrations/`; three additional forward migrations were added before 14 November, bringing the active set to 64.
- 34 historical files remain unchanged in `supabase/migrations-archive/`, outside the Supabase CLI migration scan directory.
- On 14 November, two forward migrations were applied and committed: the 65th `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` and the 66th `20261114025139_fix_driver_application_review_trim_function.sql`.

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

## Archived files

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
- The new forward migration changes only the `driver_profiles_read_scoped` SELECT policy; no user, order, stock, payment, or Storage data was changed.
