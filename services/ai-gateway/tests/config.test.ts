import test from 'node:test';
import assert from 'node:assert/strict';
import { configFromEnv } from '../src/config.js';

test('AI defaults to paused and can start in production without secrets', () => {
  const config = configFromEnv({ NODE_ENV: 'production' });
  assert.equal(config.aiEnabled, false);
  assert.equal(config.apiKey, '');
  assert.equal(config.bearerToken, '');
});

test('pausing preserves configured keys for later recovery', () => {
  const config = configFromEnv({ AI_ENABLED: 'false', MINIMAX_API_KEY: 'fake-preserved-key', GATEWAY_BEARER_TOKEN: 'fake-preserved-token' });
  assert.equal(config.aiEnabled, false);
  assert.equal(config.apiKey, 'fake-preserved-key');
  assert.equal(config.bearerToken, 'fake-preserved-token');
});

test('restoring AI requires upstream and production caller credentials', () => {
  assert.throws(() => configFromEnv({ AI_ENABLED: 'true' }), /Missing MINIMAX_API_KEY/);
  assert.throws(() => configFromEnv({ AI_ENABLED: 'true', NODE_ENV: 'production', MINIMAX_API_KEY: 'fake-key' }), /GATEWAY_BEARER_TOKEN/);
  const config = configFromEnv({ AI_ENABLED: 'true', NODE_ENV: 'production', MINIMAX_API_KEY: 'fake-key', GATEWAY_BEARER_TOKEN: 'x'.repeat(32) });
  assert.equal(config.aiEnabled, true);
});

test('an invalid pause switch cannot accidentally enable AI', () => {
  assert.throws(() => configFromEnv({ AI_ENABLED: 'yes', MINIMAX_API_KEY: 'fake-key' }), /Invalid AI_ENABLED/);
});
