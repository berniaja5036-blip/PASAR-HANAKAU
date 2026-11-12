import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

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
    !pushFunction.includes('userProfile?.account_status !== "active"')) {
  console.error('Push actions and key management must reject non-active accounts.');
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


const activeRlsMigration = readFileSync('supabase/migrations/202611120025_require_active_account_for_authenticated_rls.sql', 'utf8');
const activeStorageMigration = readFileSync('supabase/migrations/202611120026_require_active_account_for_storage_access.sql', 'utf8');
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

console.log('JavaScript syntax check passed (' + moduleBlocks.length + ' inline module).');
