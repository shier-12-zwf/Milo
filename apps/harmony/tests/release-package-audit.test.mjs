import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { archiveContentDigest, auditReleasePackage } from '../tools/audit-release-package.mjs';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const { ZipFile } = require(`${studio}/tools/hvigor/hvigor-ohos-plugin/node_modules/yazl`);
const token = 'synthetic-only-gateway-token-for-release-audit-test';

async function zip(entries) {
  const archive = new ZipFile();
  for (const [name, value] of Object.entries(entries)) archive.addBuffer(Buffer.from(value), name);
  const chunks = [];
  const result = new Promise((resolve, reject) => {
    archive.outputStream.on('data', (chunk) => chunks.push(chunk));
    archive.outputStream.on('end', () => resolve(Buffer.concat(chunks)));
    archive.outputStream.on('error', reject);
  });
  archive.end();
  return result;
}

async function app(extra = {}, debug = false, deviceTypes = ['phone']) {
  const manifest = { app: { bundleName: 'com.milo.echoes', versionName: '1.0.0', versionCode: 1000000, debug }, module: { name: 'entry', type: 'entry', deviceTypes } };
  const hap = await zip({ 'module.json': JSON.stringify(manifest), ...extra });
  return zip({ 'entry-default.hap': hap, 'pack.info': '{}' });
}

test('accepts release metadata without local secrets', async () => {
  const report = await auditReleasePackage(await app(), token);
  assert.equal(report.passed, true);
  assert.equal(report.knownTokenChecked, true);
  assert.equal(report.modules[0].debug, false);
  assert.equal(JSON.stringify(report).includes(token), false);
});

test('rejects credential resource even if token comparison is omitted', async () => {
  const report = await auditReleasePackage(await app({ 'resources/rawfile/gateway-credentials.local.json': '{}' }));
  assert.equal(report.passed, false);
  assert.equal(report.forbiddenFiles.length, 1);
});

test('rejects known token in compiled content without printing its value', async () => {
  const report = await auditReleasePackage(await app({ 'ets/modules.abc': `binary-prefix${token}binary-suffix` }), token);
  assert.equal(report.passed, false);
  assert.equal(report.knownTokenFiles.length, 1);
  assert.equal(JSON.stringify(report).includes(token), false);
});

test('rejects private signing material and debug manifests', async () => {
  const report = await auditReleasePackage(await app({ 'resources/rawfile/old.p12': 'fixture', 'resources/rawfile/key.txt': '-----BEGIN PRIVATE KEY-----' }, true));
  assert.equal(report.passed, false);
  assert.equal(report.forbiddenFiles.length, 1);
  assert.equal(report.privateKeyFiles.length, 1);
});

test('rejects an archive without an installable HAP', async () => {
  const report = await auditReleasePackage(await zip({ 'pack.info': '{}' }));
  assert.equal(report.passed, false);
});

test('rejects unsupported or missing device declarations in the built HAP', async () => {
  for (const types of [[], ['default'], ['phone', 'default']]) {
    const report = await auditReleasePackage(await app({}, false, types));
    assert.equal(report.passed, false);
  }
});

test('payload comparison ignores archive entry order but detects changed contents', async () => {
  const first = await archiveContentDigest(await zip({ 'a.txt': 'alpha', 'b.txt': 'beta' }));
  const reordered = await archiveContentDigest(await zip({ 'b.txt': 'beta', 'a.txt': 'alpha' }));
  const changed = await archiveContentDigest(await zip({ 'b.txt': 'changed', 'a.txt': 'alpha' }));
  assert.deepEqual(first, reordered);
  assert.notEqual(first.sha256, changed.sha256);
});
