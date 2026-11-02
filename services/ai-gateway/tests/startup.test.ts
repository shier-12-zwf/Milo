import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';

test('production entry stays running, serves health and shuts down cleanly', async () => {
  const probe = createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = (probe.address() as { port: number }).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  const child = spawn(process.execPath, ['--import', 'tsx/esm', 'src/main.ts'], {
    env: { ...process.env, NODE_ENV: 'production', PORT: String(port), HOST: '127.0.0.1',
      AI_ENABLED: 'true', MINIMAX_API_KEY: 'fake-test-key', GATEWAY_BEARER_TOKEN: 'x'.repeat(32) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exited = once(child, 'exit');
  try {
    let healthy = false;
    for (let attempt = 0; attempt < 60 && child.exitCode === null; attempt++) {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/health`);
        healthy = response.ok && (await response.json()).ok;
        if (healthy) break;
      } catch { /* Wait for the socket to open. */ }
      await delay(50);
    }
    assert.equal(healthy, true, 'entry must start an HTTP listener');
    child.kill('SIGTERM');
    const [code] = await exited;
    assert.equal(code, 0);
  } finally {
    if (child.exitCode === null) child.kill('SIGKILL');
  }
});

test('paused production entry starts without any key and serves an explicit disabled response', async () => {
  const probe = createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = (probe.address() as { port: number }).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  const child = spawn(process.execPath, ['--import', 'tsx/esm', 'src/main.ts'], {
    env: { ...process.env, NODE_ENV: 'production', PORT: String(port), HOST: '127.0.0.1',
      AI_ENABLED: 'false', MINIMAX_API_KEY: '', GATEWAY_BEARER_TOKEN: '' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exited = once(child, 'exit');
  try {
    let health: { ok: boolean; aiEnabled: boolean; aiStatus: string } | undefined;
    for (let attempt = 0; attempt < 60 && child.exitCode === null; attempt++) {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/health`);
        if (response.ok) { health = await response.json(); break; }
      } catch { /* Wait for the socket to open. */ }
      await delay(50);
    }
    assert.equal(health?.ok, true);
    assert.equal(health?.aiEnabled, false);
    assert.equal(health?.aiStatus, 'paused');
    const response = await fetch(`http://127.0.0.1:${port}/v1/recall/open`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{legacy-invalid-json',
    });
    assert.equal(response.status, 503);
    assert.equal((await response.json()).code, 'AI_DISABLED');
    child.kill('SIGTERM');
    const [code] = await exited;
    assert.equal(code, 0);
  } finally {
    if (child.exitCode === null) child.kill('SIGKILL');
  }
});
