import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const html = readFileSync('index.html', 'utf8');
const blocks = [...html.matchAll(/<script\\b([^>]*)>([\\s\\S]*?)<\\/script>/gi)];
const moduleBlocks = blocks.filter(([, attributes]) =>
  /\\btype\\s*=\\s*["']module["']/i.test(attributes)
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
    console.error(`JavaScript module ${index + 1} has a syntax error:`);
    process.stderr.write(result.stderr || result.stdout || 'Unknown syntax-check error.\\n');
    process.exit(result.status || 1);
  }
}

console.log(`JavaScript syntax check passed (${moduleBlocks.length} inline module).`);
