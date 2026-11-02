import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { resolveSigningFile, loadSigningConfigs, applySigningConfigs } = require('../tools/local-signing.cjs');
const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

test('committed Harmony profile has no signing material', () => {
  const profile = readFileSync(join(projectRoot, 'build-profile.json5'), 'utf8');
  assert.doesNotMatch(profile, /signingConfigs|signingConfig|keyPassword|storePassword|certpath|\.p12|\.p7b|\/Users\//);
  const ignore = readFileSync(join(projectRoot, '.gitignore'), 'utf8');
  assert.match(ignore, /signing-configs\.local\.json/);
  const hook = readFileSync(join(projectRoot, 'hvigorfile.ts'), 'utf8');
  assert.match(hook, /local-signing\.cjs/);
  assert.match(hook, /afterNodeEvaluate/);
  assert.match(hook, /MILO_HARMONY_SIGNING_FILE|resolveSigningFile/);
});

test('a missing signing file leaves the build unsigned', () => {
  const dir = mkdtempSync(join(tmpdir(), 'milo-sign-'));
  try {
    assert.equal(loadSigningConfigs(resolveSigningFile(dir, {})), undefined);
    const custom = join(dir, 'custom-signing.json');
    assert.equal(resolveSigningFile(dir, { MILO_HARMONY_SIGNING_FILE: custom }), custom);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('local signing configs attach per product and reject an empty file', () => {
  const dir = mkdtempSync(join(tmpdir(), 'milo-sign-'));
  try {
    const file = join(dir, 'signing-configs.local.json');
    writeFileSync(file, JSON.stringify({
      signingConfigs: [
        { name: 'default', material: { storeFile: '/tmp/debug.p12' } },
        { name: 'release', material: { storeFile: '/tmp/release.p12' } },
      ],
    }));
    const configs = loadSigningConfigs(resolveSigningFile(dir, {}));
    const profile = {
      app: {
        products: [{ name: 'default' }, { name: 'release' }, { name: 'extra' }],
      },
    };
    applySigningConfigs(profile, configs);
    assert.equal(profile.app.products[0].signingConfig, 'default');
    assert.equal(profile.app.products[1].signingConfig, 'release');
    assert.equal(profile.app.products[2].signingConfig, 'default');
    assert.equal(profile.app.signingConfigs.length, 2);
    writeFileSync(file, '{"signingConfigs":[]}');
    assert.throws(() => loadSigningConfigs(file), /non-empty/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
