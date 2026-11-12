# Database migration reconciliation

Last reconciled: 2026-11-12.

## Canonical migration history

The live Supabase project has **61 applied migration records**. The repository previously had 95 SQL files directly inside `supabase/migrations/`, with duplicate version prefixes and local prefixes that did not match the live 14-digit migration versions.

This reconciliation changes **filenames and locations only**; the SQL bodies of all files are preserved byte-for-byte:

- 61 files are retained in `supabase/migrations/` and renamed to exactly match the live database's `version_name.sql` records.
- 34 files are moved unchanged to `supabase/migrations-archive/`, outside the Supabase CLI migration scan directory.
- No migration is applied to the production database by this reconciliation.

The five historical filename equivalents are now canonicalized to the exact live migration names:

| Live version | Live migration name | Previous repository filename |
| --- | --- | --- |
| `20261111151328` | `require_buyer_receipt_before_delivery_fee_confirmation` | `202611110006_require_receipt_before_delivery_fee_confirmation.sql` |
| `20261111153148` | `require_buyer_receipt_before_delivery_fee_dispute` | `202611110009_require_receipt_before_delivery_fee_dispute.sql` |
| `20261111172816` | `restrict_push_webhook_token_lookup_to_service_role` | `202611110022_restrict_push_webhook_token_lookup.sql` |
| `20261111174121` | `fix_rating_insert_policy_qualification` | `202611120002_fix_rating_insert_policies.sql` |
| `20261112033138` | `protect_active_driver_documents_from_owner_deletion` | `202611120020_protect_active_driver_documents.sql` |

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

- Live migration history was read using the Supabase migration-list endpoint: 61 records.
- Every live version/name pair has exactly one canonical repository file after this reconciliation.
- The canonical directory has unique 14-digit version prefixes and no duplicate versions.
- The five archived-but-applied SQL effects were checked in the live catalog: helper ACLs and `search_path`, profile column grants, rating-summary function definitions, and product/shop status grants plus guard triggers.
- The two old bootstrap table names were confirmed absent from the current public schema.
- No production schema, user, order, stock, payment, or Storage data was changed.
