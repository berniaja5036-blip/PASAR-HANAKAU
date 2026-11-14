import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const migrationDirectory = 'supabase/migrations';
const migrationFiles = readdirSync(migrationDirectory).filter(file => file.endsWith('.sql'));
function readMigration(name) {
  const matches = migrationFiles.filter(file => file.endsWith('_' + name + '.sql'));
  if (matches.length !== 1) {
    console.error('Expected exactly one canonical migration for ' + name + '; found ' + matches.length + '.');
    process.exit(1);
  }
  return readFileSync(migrationDirectory + '/' + matches[0], 'utf8');
}

const html = readFileSync('index.html', 'utf8');
const blocks = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
const moduleBlocks = blocks.filter(([, attributes]) =>
  /\btype\s*=\s*["']module["']/i.test(attributes)
);

if (moduleBlocks.length === 0) {
  console.error('No inline JavaScript module found in index.html.');
  process.exit(1);
}

for (let index = 0; index < moduleBlocks.length; index += 1) {
  const result = spawnSync(process.execPath, ['--check', '--input-type=module'], {
    input: moduleBlocks[index][2],
    encoding: 'utf8'
  });

  if (result.status !== 0) {
    console.error('JavaScript module ' + (index + 1) + ' has a syntax error:');
    process.stderr.write(result.stderr || result.stdout || 'Unknown syntax-check error.\n');
    process.exit(result.status || 1);
  }
}


const checkoutFunction = readFileSync('supabase/functions/checkout-with-delivery/index.ts', 'utf8');
if (!checkoutFunction.includes('"Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io"') ||
    checkoutFunction.includes('"Access-Control-Allow-Origin": "*"')) {
  console.error('Checkout Edge Function must restrict CORS to the Pasar Hanakau site.');
  process.exit(1);
}

const pushFunction = readFileSync('supabase/functions/push-notifications/index.ts', 'utf8');
if (!pushFunction.includes('select("role,account_status")') ||
    !pushFunction.includes('profile.account_status !== "active"') ||
    !pushFunction.includes('userProfile?.account_status !== "active"') ||
    !pushFunction.includes('recipientProfile?.account_status !== "active"')) {
  console.error('Push registration, key management, and delivery must reject non-active accounts.');
  process.exit(1);
}


const routeDistanceFunction = readFileSync('supabase/functions/route-distance/index.ts', 'utf8');
const adminFunction = readFileSync('supabase/functions/admin-account-management/index.ts', 'utf8');
const expectedOrigin = '"Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io"';
for (const [name, source] of [
  ['route-distance', routeDistanceFunction],
  ['checkout-with-delivery', checkoutFunction],
  ['push-notifications', pushFunction],
  ['admin-account-management', adminFunction]
]) {
  if (!source.includes(expectedOrigin) || source.includes('"Access-Control-Allow-Origin": "*"')) {
    console.error(name + ' Edge Function must restrict CORS to the Pasar Hanakau site.');
    process.exit(1);
  }
}
if (!checkoutFunction.includes('userClient.auth.getUser()')) {
  console.error('Checkout must validate the caller session before processing.');
  process.exit(1);
}
if (!pushFunction.includes('client.auth.getUser(authToken)') ||
    !pushFunction.includes('supplied !== expectedWebhookToken')) {
  console.error('Push endpoint must validate user sessions and webhook secrets.');
  process.exit(1);
}
if (!adminFunction.includes('caller.auth.getUser(token)') ||
    !adminFunction.includes('adminProfile?.role !== "admin"') ||
    !adminFunction.includes('adminProfile.account_status !== "active"')) {
  console.error('Admin account management must validate session, admin role, and active account status.');
  process.exit(1);
}
if (!checkoutFunction.includes('select("role,account_status")') ||
    !checkoutFunction.includes('profile.account_status !== "active"')) {
  console.error('Checkout must reject non-active buyer accounts before service-role operations.');
  process.exit(1);
}


const activeRlsMigration = readMigration('require_active_account_for_authenticated_rls');
const activeStorageMigration = readMigration('require_active_account_for_storage_access');
const appSource = readFileSync('index.html', 'utf8');
if (!appSource.includes("if(profile.account_status!=='active')")) {
  console.error('The client must fail closed for every non-active account state.');
  process.exit(1);
}
if (!activeRlsMigration.includes('public.current_user_is_active()') ||
    !activeRlsMigration.includes('as restrictive for all to authenticated') ||
    !activeRlsMigration.includes('active_account_read_self')) {
  console.error('Authenticated table access must be restricted to active accounts while allowing self-status lookup.');
  process.exit(1);
}
if (!activeStorageMigration.includes('create policy active_account_required on storage.objects') ||
    !activeStorageMigration.includes('as restrictive')) {
  console.error('Authenticated Storage access must be restricted to active accounts.');
  process.exit(1);
}


const activeRpcMigration = readMigration('enforce_active_status_in_sensitive_definer_rpcs');
for (const rpc of [
  'buyer_confirm_delivery_fee',
  'buyer_confirm_order_received',
  'buyer_report_delivery_fee_dispute',
  'buyer_request_order_cancellation',
  'driver_confirm_delivery_fee',
  'driver_update_delivery_status'
]) {
  if (!activeRpcMigration.includes("'" + rpc + "'")) {
    console.error('Sensitive RPC missing active-account protection: ' + rpc);
    process.exit(1);
  }
}
if (!activeRpcMigration.includes('public.current_user_is_active()') ||
    !activeRpcMigration.includes("account_status=''active''")) {
  console.error('Sensitive RPC migration must also protect service-role checkout for active buyers.');
  process.exit(1);
}


const activeHelperMigration = readMigration('require_active_account_for_security_helpers');
for (const helper of [
  'can_upload_product_image',
  'current_user_can_read_delivery_order',
  'current_user_is_assigned_driver'
]) {
  if (!activeHelperMigration.includes("'" + helper + "'") ||
      !activeHelperMigration.includes('public.current_user_is_active() and exists')) {
    console.error('Exposed security helper missing active-account check: ' + helper);
    process.exit(1);
  }
}

const anonymousWriteMigration = readMigration('revoke_anon_public_table_writes');
if (!anonymousWriteMigration.includes('revoke insert, update, delete on table') ||
    !anonymousWriteMigration.includes('from anon')) {
  console.error('Anonymous users must not receive direct write privileges on public application tables.');
  process.exit(1);
}

const routeFunction = readFileSync('supabase/functions/route-distance/index.ts', 'utf8');
if (!routeFunction.includes('userClient.auth.getUser()') ||
    !routeFunction.includes('profile?.account_status !== "active"')) {
  console.error('Route distance must reject invalid sessions and non-active accounts.');
  process.exit(1);
}

const commissionPeriodMigration = readMigration('fix_commission_period_to_wib');
if (!commissionPeriodMigration.includes("pg_catalog.now() at time zone 'Asia/Jakarta'")) {
  console.error('Seller commission periods must use Asia/Jakarta local time.');
  process.exit(1);
}

const statisticsTimezoneMigration = readMigration('fix_admin_statistics_wib_date_grouping');
if (!statisticsTimezoneMigration.includes("o.created_at at time zone 'Asia/Jakarta'") ||
    !statisticsTimezoneMigration.includes("p_from at time zone 'Asia/Jakarta'") ||
    statisticsTimezoneMigration.includes("greatest(p_from,now()-interval '30 days')")) {
  console.error('Admin daily statistics and commission-paid dates must use the selected WIB date range.');
  process.exit(1);
}

const appSourceForDriverChecks = readFileSync('index.html', 'utf8');
if (!appSourceForDriverChecks.includes("application?.status==='approved'&&!!application.ktp_image_path&&!!application.face_image_path") ||
    !appSourceForDriverChecks.includes("!availability?.eligible||busyElsewhere")) {
  console.error('Admin driver assignment must exclude drivers without approved KTP and face-document paths.');
  process.exit(1);
}

const notificationPrivilegesMigration = readMigration('restrict_notifications_to_read_only_clients');
if (!notificationPrivilegesMigration.includes('revoke update on table public.notifications from authenticated') ||
    !notificationPrivilegesMigration.includes('drop policy if exists notifications_update_own')) {
  console.error('Client notification records must remain read-only.');
  process.exit(1);
}

if (!appSourceForDriverChecks.includes('accepted_terms_version:"2026-11-12"')) {
  console.error('Signup must record the current legal consent version.');
  process.exit(1);
}
const termsVersionMigration = readMigration('align_signup_terms_version_20261112');
if (!termsVersionMigration.includes("v_terms_version <> '2026-11-12'")) {
  console.error('The database signup trigger must require the current legal consent version.');
  process.exit(1);
}

const productRatingMigration = readMigration('202611120034_add_public_rating_summaries');
if (!productRatingMigration.includes('get_public_product_review_summaries') ||
    !productRatingMigration.includes('get_public_driver_rating_summaries') ||
    !productRatingMigration.includes("set search_path = ''") ||
    !productRatingMigration.includes('cardinality(p_product_ids) <= 100') ||
    !productRatingMigration.includes('cardinality(p_driver_ids) <= 100')) {
  console.error('Public rating summaries must expose aggregate-only data with bounded input arrays and a fixed search_path.');
  process.exit(1);
}
if (!appSourceForDriverChecks.includes("get_public_product_review_summaries") ||
    !appSourceForDriverChecks.includes("get_public_driver_rating_summaries") ||
    !appSourceForDriverChecks.includes('Belum ada ulasan') ||
    !appSourceForDriverChecks.includes('Belum ada penilaian')) {
  console.error('Catalog and assigned-driver UI must display public aggregate rating summaries.');
  process.exit(1);
}

const ratingAccessMigration = readMigration('202611120035_limit_rating_summaries_to_signed_in_users');
if (!ratingAccessMigration.includes('from anon') ||
    !ratingAccessMigration.includes('get_public_product_review_summaries') ||
    !ratingAccessMigration.includes('get_public_driver_rating_summaries')) {
  console.error('Rating summary functions must not be executable by anonymous users.');
  process.exit(1);
}


const driverAssignmentGuardMigration = readMigration('guard_driver_assignment_active_profile');
if (!driverAssignmentGuardMigration.includes("p.role = 'driver'") ||
    !driverAssignmentGuardMigration.includes("p.account_status = 'active'") ||
    !driverAssignmentGuardMigration.includes('for update')) {
  console.error('Driver assignment must lock and verify an active driver profile before assigning work.');
  process.exit(1);
}


const driverAssignmentTrimMigration = readMigration('fix_driver_assignment_document_trim');
if (!driverAssignmentTrimMigration.includes('nullif(pg_catalog.btrim') ||
    driverAssignmentTrimMigration.includes('nullif(pg_catalog.trim(')) {
  console.error('Driver document validation must use the valid pg_catalog.btrim function.');
  process.exit(1);
}


const checkoutAttemptMigration = readMigration('checkout_request_idempotency');
const checkoutRetryPreflightMigration = readMigration('checkout_idempotency_retry_preflight');
const checkoutInProgressMigration = readMigration('checkout_idempotency_in_progress_response');
if (!checkoutFunction.includes('get_checkout_idempotent_result_secure') ||
    !checkoutFunction.includes('checkout_cart_idempotent_secure') ||
    !checkoutFunction.includes('idempotency_key') ||
    checkoutFunction.includes('rpc("checkout_cart_secure"')) {
  console.error('Checkout Edge Function must use the protected idempotent server RPC path only.');
  process.exit(1);
}
if (!checkoutAttemptMigration.includes('primary key (buyer_id, idempotency_key)') ||
    !checkoutAttemptMigration.includes('on conflict (buyer_id, idempotency_key) do nothing') ||
    !checkoutAttemptMigration.includes('for update') ||
    !checkoutAttemptMigration.includes('to service_role') ||
    !checkoutAttemptMigration.includes('from public, anon, authenticated, service_role')) {
  console.error('Checkout idempotency must be unique per buyer, serialized, and inaccessible to client roles.');
  process.exit(1);
}
if (!checkoutRetryPreflightMigration.includes("auth.role(), '') <> 'service_role'") ||
    !checkoutRetryPreflightMigration.includes('to service_role') ||
    !checkoutInProgressMigration.includes('_checkout_in_progress')) {
  console.error('Checkout retry preflight must remain service-role-only and detect an in-progress attempt.');
  process.exit(1);
}
if (!appSourceForDriverChecks.includes('async function getCheckoutIdempotencyKey(payload)') ||
    !appSourceForDriverChecks.includes('function checkoutAttemptStorageKey(){return activeBuyerId?') ||
    !appSourceForDriverChecks.includes('idempotency_key:idempotencyKey') ||
    !appSourceForDriverChecks.includes('clearCheckoutIdempotencyKey();')) {
  console.error('Buyer checkout must persist a per-account retry key and clear it only after success.');
  process.exit(1);
}

const adminCancellationMigration = readMigration('restore_stock_on_admin_order_cancellation');
if (!adminCancellationMigration.includes('public.is_admin()') ||
    !adminCancellationMigration.includes('for update') ||
    !adminCancellationMigration.includes("v_current_status = 'pending'") ||
    !adminCancellationMigration.includes("v_current_status = 'confirmed'") ||
    !adminCancellationMigration.includes('set stock = p.stock + item_totals.quantity') ||
    !adminCancellationMigration.includes("status = 'failed'")) {
  console.error('Admin cancellation must enforce status transitions and restore reserved stock atomically.');
  process.exit(1);
}

const driverAssignmentMigration = readMigration('fix_driver_assignment_document_trim');
if (!driverAssignmentMigration.includes('public.is_admin()') ||
    !driverAssignmentMigration.includes("p.role = 'driver'") ||
    !driverAssignmentMigration.includes("p.account_status = 'active'") ||
    !driverAssignmentMigration.includes("dp.approval_status = 'approved'") ||
    !driverAssignmentMigration.includes("so.bucket_id = 'driver-private-documents'") ||
    !driverAssignmentMigration.includes("v_order_status <> 'ready_for_pickup'") ||
    !driverAssignmentMigration.includes("d.status in ('assigned','picked_up')")) {
  console.error('Admin dispatch must require an active, approved, documented, and available driver.');
  process.exit(1);
}

const driverProfileScopeMigration = readMigration('scope_driver_profile_visibility_to_related_orders');
const driverProfilePolicy = driverProfileScopeMigration.match(/create policy driver_profiles_read_scoped[\s\S]*?using\s*\(([\s\S]*?)^\);/im);
if (!driverProfilePolicy ||
    !driverProfilePolicy[1].includes('id = (select auth.uid())') ||
    !driverProfilePolicy[1].includes('(select public.is_admin())') ||
    !driverProfilePolicy[1].includes('d.driver_id = driver_profiles.id') ||
    !driverProfilePolicy[1].includes('public.current_user_can_read_delivery_order(d.order_id)')) {
  console.error('Driver profile reads must be limited to the driver, admin, and users who can access an associated order.');
  process.exit(1);
}

const driverReviewTrimMigration = readMigration('fix_driver_application_review_trim_function');
if (!driverReviewTrimMigration.includes('create or replace function public.admin_review_driver_application') ||
    !driverReviewTrimMigration.includes('pg_catalog.btrim(v_app.ktp_image_path)') ||
    !driverReviewTrimMigration.includes('pg_catalog.btrim(v_app.face_image_path)') ||
    !driverReviewTrimMigration.includes("so.bucket_id = 'driver-private-documents'") ||
    driverReviewTrimMigration.includes('pg_catalog.trim(')) {
  console.error('Driver application approval must safely trim and verify both stored identity-document paths.');
  process.exit(1);
}

console.log('JavaScript syntax and marketplace security regression checks passed (' + moduleBlocks.length + ' inline module).');
