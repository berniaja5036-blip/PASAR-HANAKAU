# Multi-role foundation migration — draft

Status: **draft only; not applied to Supabase production**.

## Purpose

Add `public.profile_roles` as an additive, multi-role assignment table while keeping `profiles.role` unchanged for legacy compatibility. This first migration does not replace the existing authorization helper or modify operational RLS policies; those changes belong in a later, fully tested migration.

## Backfill rules

- Every non-admin profile receives an active buyer role.
- Existing admin profiles receive an active admin role.
- Seller roles are active only when the latest seller application is approved and an approved shop exists; pending/rejected applications are represented as pending/rejected.
- Driver roles are active only when the latest driver application is approved and `driver_profiles.approval_status='approved'`; pending/rejected applications are represented as pending/rejected.
- Historical driver document-path gaps do not silently revoke an already approved driver role. Existing delivery-assignment RPCs continue enforcing the private KTP/face object checks.
- Account-wide suspension remains governed by `profiles.account_status`; the new role status can later be used for role-specific suspension.

## Compatibility

- Existing `profiles.role` is not changed.
- Existing RPCs and RLS continue using their current helper during this additive phase.
- New user profiles automatically receive buyer role rows.
- Seller/driver application status triggers maintain pending/active/rejected role rows after application changes.
- Authenticated clients may SELECT only their own roles; admins may SELECT all roles. Authenticated users receive no INSERT/UPDATE/DELETE grant. Anon receives no access. Demoting a legacy primary admin role also suspends the corresponding admin role row, preventing stale admin access.
- The new `current_user_has_active_role(text)` helper is read-only and checks both role status and account status.

## Test strategy

The GitHub Actions workflow uses an isolated PostgreSQL 17 service. It verifies migration syntax, backfill, multi-role accounts, pending/rejected applications, profile/application triggers, RLS visibility, suspended-account behavior, and absence of client write grants.

This is not a substitute for the later Supabase integration tests. No production SQL has been executed by this draft.

## Read-only production preflight (15 November 2026)

- Current profiles: 1 admin, 3 buyer-primary, 1 seller-primary, and 2 driver-primary; all profiles are active.
- Seller-primary accounts without an approved seller application and approved shop: 0.
- Driver-primary accounts without an approved driver application and approved driver profile: 0.
- Pending driver applications: 1; the draft maps this to a pending driver role while preserving the buyer role.
- One already-approved driver application has empty KTP/face path fields even though its driver profile and application are approved. The draft deliberately preserves the existing approved driver role instead of silently revoking it. Existing delivery-assignment logic still requires the private document objects before assigning new work; this data anomaly needs an admin follow-up.
- An encrypted production database backup was completed and verified before this draft was started. No production schema or data was changed.
