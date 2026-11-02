#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const yauzl = require(`${studio}/tools/hvigor/hvigor-ohos-plugin/node_modules/@eggjs/yauzl`);
const MAX_ENTRY_BYTES = 64 * 1024 * 1024;
const MAX_TOTAL_BYTES = 256 * 1024 * 1024;
const forbiddenPath = /(?:^|\/)(?:gateway-credentials\.local\.json|\.env(?:\.[^/]*)?|build-profile\.json5|\.signing|\.release-private)(?:\/|$)|\.(?:p12|jks|keystore)$/i;
const privateKeyMarker = /-----BEGIN (?:RSA |EC |ENCRYPTED |OPENSSH )?PRIVATE KEY-----/;

async function entriesOf(buffer) {
  return await new Promise((resolveEntries, reject) => {
    yauzl.fromBuffer(buffer, { lazyEntries: true, strictFileNames: true }, (error, archive) => {
      if (error) return reject(new Error('Invalid release archive.'));
      const entries = [];
      let total = 0;
      archive.on('error', () => reject(new Error('Could not read release archive.')));
      archive.on('end', () => resolveEntries(entries));
      archive.on('entry', (entry) => {
        if (entries.length >= 5000 || entry.uncompressedSize > MAX_ENTRY_BYTES ||
            (total += entry.uncompressedSize) > MAX_TOTAL_BYTES) {
          archive.close();
          return reject(new Error('Release archive exceeds inspection limits.'));
        }
        if (entry.fileName.endsWith('/')) return archive.readEntry();
        archive.openReadStream(entry, (streamError, stream) => {
          if (streamError) return reject(new Error('Could not inspect archive entry.'));
          const chunks = [];
          stream.on('data', (chunk) => chunks.push(chunk));
          stream.on('error', () => reject(new Error('Could not inspect archive content.')));
          stream.on('end', () => {
            entries.push({ name: entry.fileName, data: Buffer.concat(chunks) });
            archive.readEntry();
          });
        });
      });
      archive.readEntry();
    });
  });
}

/** Compare packaged payloads independently of ZIP timestamps and signing blocks. */
export async function archiveContentDigest(buffer) {
  const entries = await entriesOf(buffer);
  entries.sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
  const digest = createHash('sha256');
  for (const entry of entries) {
    digest.update(entry.name);
    digest.update('\0');
    digest.update(createHash('sha256').update(entry.data).digest());
  }
  return { files: entries.length, sha256: digest.digest('hex') };
}

/** Read-only content audit. Signing/profile verification is a separate SDK step. */
export async function auditReleasePackage(buffer, knownToken = '') {
  if (buffer.length > MAX_TOTAL_BYTES) throw new Error('Release archive exceeds inspection limits.');
  const report = {
    sha256: createHash('sha256').update(buffer).digest('hex'),
    bytes: buffer.length,
    inspectedEntries: 0,
    knownTokenChecked: knownToken.length >= 32,
    forbiddenFiles: [],
    privateKeyFiles: [],
    knownTokenFiles: [],
    modules: [],
  };
  const outer = await entriesOf(buffer);
  const inspect = (entries, prefix) => {
    for (const entry of entries) {
      const name = `${prefix}${entry.name}`;
      report.inspectedEntries++;
      if (forbiddenPath.test(entry.name)) report.forbiddenFiles.push(name);
      if (privateKeyMarker.test(entry.data.toString('utf8'))) report.privateKeyFiles.push(name);
      if (report.knownTokenChecked && entry.data.includes(Buffer.from(knownToken))) report.knownTokenFiles.push(name);
    }
  };
  inspect(outer, '');
  for (const entry of outer) {
    if (!entry.name.endsWith('.hap')) continue;
    const inner = await entriesOf(entry.data);
    inspect(inner, `${entry.name}/`);
    const manifest = inner.find((item) => item.name === 'module.json');
    if (!manifest) throw new Error('Packaged HAP is missing its manifest.');
    let parsed;
    try { parsed = JSON.parse(manifest.data.toString('utf8')); }
    catch { throw new Error('Packaged HAP manifest is not valid JSON.'); }
    report.modules.push({
      file: entry.name,
      bundleName: parsed.app?.bundleName,
      versionName: parsed.app?.versionName,
      versionCode: parsed.app?.versionCode,
      debug: parsed.app?.debug,
      moduleName: parsed.module?.name,
      moduleType: parsed.module?.type,
      deviceTypes: parsed.module?.deviceTypes || [],
      permissions: (parsed.module?.requestPermissions || []).map((item) => item.name),
    });
  }
  report.passed = report.modules.length > 0 &&
    report.modules.every((item) => item.bundleName === 'com.milo.echoes' && item.debug === false && item.moduleType === 'entry' &&
      item.deviceTypes.length > 0 && item.deviceTypes.every((type) => ['phone', 'tablet', 'tv', 'wearable', '2in1', 'car'].includes(type))) &&
    report.forbiddenFiles.length === 0 && report.privateKeyFiles.length === 0 && report.knownTokenFiles.length === 0;
  return report;
}

async function main(args) {
  if (args.length === 1 && args[0] === '--help') {
    console.log('Usage: node tools/audit-release-package.mjs --app /path/signed.app [--credential-backup /path/gateway-credentials.local.json]');
    console.log('Reads archives in memory. Reports filenames/metadata only, never credential values. Signature/profile verification is separate.');
    return;
  }
  if (![2, 4].includes(args.length) || args[0] !== '--app' ||
      (args.length === 4 && args[2] !== '--credential-backup')) throw new Error('Invalid audit arguments. Use --help.');
  let token = '';
  if (args.length === 4) {
    let credential;
    try { credential = JSON.parse(readFileSync(resolve(args[3]), 'utf8')); }
    catch { throw new Error('Could not read credential backup for comparison.'); }
    if (typeof credential.gatewayBearerToken !== 'string' || credential.gatewayBearerToken.length < 32) {
      throw new Error('Credential backup is not valid for comparison.');
    }
    token = credential.gatewayBearerToken;
  }
  const report = await auditReleasePackage(readFileSync(resolve(args[1])), token);
  console.log(JSON.stringify(report, null, 2));
  if (!report.passed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(() => {
    // Do not print raw parser/file errors, which may contain file contents.
    console.error('Release package audit failed. Check the supplied paths and archive format.');
    process.exitCode = 1;
  });
}
