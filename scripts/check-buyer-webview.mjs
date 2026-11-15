import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const htmlPath = 'buyer/index.html';
const html = readFileSync(htmlPath, 'utf8');
const roles = [...html.matchAll(/data-entry-role="([^"]+)"/g)].map(match => match[1]);
if (new Set(roles).size !== 1 || roles[0] !== 'buyer') {
  throw new Error('Buyer web entry must expose buyer-only login and signup controls.');
}
if (html.includes('id="togglePartnerAccess"') ||
    !html.includes("if(role!=='buyer')") ||
    !html.includes("if(selectedEntryRole!=='buyer')")) {
  throw new Error('Buyer-only access guards are missing or partner entry is exposed.');
}

const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
const inlineScripts = scripts.filter(([, attrs]) => !/\bsrc\s*=/i.test(attrs));
if (inlineScripts.length === 0) throw new Error('No inline JavaScript found in buyer entry.');
for (let index = 0; index < inlineScripts.length; index += 1) {
  const result = spawnSync(process.execPath, ['--check', '--input-type=module'], {
    input: inlineScripts[index][2], encoding: 'utf8'
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout || '');
    throw new Error('Buyer inline JavaScript syntax check failed at block ' + (index + 1));
  }
}

for (const asset of [...html.matchAll(/(?:href|src)="(\.\.\/icons\/[^"]+)"/g)].map(match => match[1])) {
  if (!existsSync(resolve('buyer', asset))) throw new Error('Buyer asset missing: ' + asset);
}
for (const required of ['buyer/manifest.webmanifest','buyer/sw.js','buyer/syarat-ketentuan.html','buyer/kebijakan-privasi.html']) {
  if (!existsSync(required)) throw new Error('Required buyer web file missing: ' + required);
}
const manifest = JSON.parse(readFileSync('buyer/manifest.webmanifest', 'utf8'));
if (manifest.start_url !== './' || manifest.scope !== './') {
  throw new Error('Buyer PWA manifest must remain scoped to /buyer/.');
}
const sw = readFileSync('buyer/sw.js', 'utf8');
if (!sw.includes('pasar-hanakau-buyer-shell-v1') ||
    !sw.includes('self.clients.claim()') ||
    !sw.includes('caches.match("./")')) {
  throw new Error('Buyer service worker shell/cache behavior is incomplete.');
}
console.log('Buyer-only web entry, relative assets, PWA scope, and inline JavaScript verified.');
