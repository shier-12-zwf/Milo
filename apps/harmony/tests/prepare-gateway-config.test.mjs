import assert from 'node:assert/strict';
import { chmodSync, existsSync, lstatSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { gatewayCredentialFromEnv, writeGatewayCredential } from '../tools/prepare-gateway-config.mjs';

const credential = { schemaVersion: 1, gatewayBaseUrl: 'https://example.test', gatewayBearerToken: 'test-only-not-a-real-credential' };

test('binds the token to the filed root domain, ignoring a different subdomain and provider key', () => {
  const token = 'test-only-gateway-token-for-local-checks';
  const parsed = gatewayCredentialFromEnv([
    `GATEWAY_BEARER_TOKEN=${token}`,
    'GATEWAY_BASE_URL=https://api.milomood.xyz',
    'MINIMAX_API_KEY=must-never-be-copied',
  ].join('\n'));
  assert.deepEqual(parsed, {
    schemaVersion: 1,
    gatewayBaseUrl: 'https://milomood.xyz',
    gatewayBearerToken: token,
  });
  assert.notEqual(parsed.gatewayBaseUrl, 'https://api.milomood.xyz');
});

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'milo-credential-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return { output: join(directory, 'gateway.json'), target: join(directory, 'target.json') };
}

test('creates a private regular credential resource', (t) => {
  const { output } = fixture(t);
  writeGatewayCredential(output, credential);
  assert.deepEqual(JSON.parse(readFileSync(output, 'utf8')), credential);
  assert.equal(statSync(output).mode & 0o777, 0o600);
});

test('replaces an existing regular resource and tightens its mode', (t) => {
  const { output } = fixture(t);
  writeFileSync(output, 'old content'.repeat(100));
  chmodSync(output, 0o644);
  writeGatewayCredential(output, credential);
  assert.deepEqual(JSON.parse(readFileSync(output, 'utf8')), credential);
  assert.equal(statSync(output).mode & 0o777, 0o600);
});

test('refuses a valid symbolic link without altering its target or permissions', (t) => {
  const { output, target } = fixture(t);
  writeFileSync(target, 'original');
  chmodSync(target, 0o640);
  symlinkSync(target, output);
  assert.throws(() => writeGatewayCredential(output, credential), /Refusing to overwrite/);
  assert.equal(readFileSync(target, 'utf8'), 'original');
  assert.equal(statSync(target).mode & 0o777, 0o640);
  assert.equal(lstatSync(output).isSymbolicLink(), true);
});

test('refuses a dangling symbolic link without creating its target', (t) => {
  const { output, target } = fixture(t);
  symlinkSync(target, output);
  assert.equal(existsSync(output), false);
  assert.throws(() => writeGatewayCredential(output, credential), /Refusing to overwrite/);
  assert.equal(existsSync(target), false);
  assert.equal(lstatSync(output).isSymbolicLink(), true);
});
