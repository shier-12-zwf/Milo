#!/usr/bin/env node
/**
 * Pre-flight checks before the manual device walkthrough. Run from the
 * repository root:
 *
 *   node scripts/device-checklist.mjs [gateway-url]
 *
 * It:
 *   1. Prints the release-checklist.md sections as a printable run sheet
 *   2. Pings the gateway /health (when a URL is given)
 *   3. Confirms the unsigned HAP was built and lives where DevEco expects
 *   4. Reports the file size so you can verify a signed re-build later
 *
 * Exit code 0 = ready for device; non-zero = fix the listed issue first.
 */
import { readFileSync, existsSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const gatewayUrl = process.argv[2] ?? '';

function ok(label, detail = '') {
  process.stdout.write(`  ✅ ${label}${detail ? '  ·  ' + detail : ''}\n`);
}
function warn(label, detail = '') {
  process.stdout.write(`  ⚠️  ${label}${detail ? '  ·  ' + detail : ''}\n`);
}
function fail(label, detail = '') {
  process.stdout.write(`  ❌ ${label}${detail ? '  ·  ' + detail : ''}\n`);
  process.exitCode = 1;
}

console.log('\n┌─ MILO · pre-flight checks ───────────────────────────────────────┐\n');

if (gatewayUrl) {
  console.log(`· Probing gateway: ${gatewayUrl}/health`);
  try {
    const res = await fetch(`${gatewayUrl}/health`);
    if (res.ok) {
      const body = await res.json();
      if (body && body.ok === true) {
        ok('gateway /health', `requestId=${body.requestId ?? '<none>'}`);
      } else {
        fail('gateway /health', `unexpected body: ${JSON.stringify(body)}`);
      }
    } else {
      fail('gateway /health', `HTTP ${res.status}`);
    }
  } catch (error) {
    fail('gateway /health', String(error.message ?? error));
  }
} else {
  warn('gateway not probed', 'pass the URL as the first argument to check it');
}

console.log('\n· Locating the unsigned HAP');
const unsignedPath = resolve(root, 'apps/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap');
if (existsSync(unsignedPath)) {
  const size = statSync(unsignedPath).size;
  ok('unsigned HAP exists', `${unsignedPath} · ${(size / 1024 / 1024).toFixed(2)} MB`);
} else {
  warn('unsigned HAP missing', `build with: cd apps/harmony && ./hvigorw assembleHap`);
}

console.log('\n· Locating signing material (optional)');
for (const candidate of ['milo.p12', 'milo-harmony.p12']) {
  const p = resolve(root, 'apps/harmony', candidate);
  if (existsSync(p)) {
    ok(`p12 candidate: ${candidate}`, p);
  }
}

console.log('\n· Reviewer run sheet (release-checklist.md)\n');
const checklistPath = resolve(root, 'docs/compliance/release-checklist.md');
if (existsSync(checklistPath)) {
  const raw = readFileSync(checklistPath, 'utf8');
  const lines = raw.split('\n');
  let printing = false;
  for (const line of lines) {
    if (line.startsWith('# ') && !line.startsWith('## ')) printing = false;
    if (line.startsWith('## ') && /^\d+\./.test(line.slice(3))) printing = true;
    if (printing && line.startsWith('- [')) {
      process.stdout.write(`  ${line}\n`);
    }
  }
} else {
  fail('release-checklist.md missing', checklistPath);
}

console.log('\n└──────────────────────────────────────────────────────────────────┘\n');
console.log(`Next: open DevEco Studio → File → Open → ${resolve(root, 'apps/harmony')}\n`);