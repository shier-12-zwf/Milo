import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const template = readFileSync(new URL('../deploy/native-api-nginx.conf', import.meta.url), 'utf8');

function locationBody(header: string): string {
  const start = template.indexOf(header);
  assert.notEqual(start, -1, `Missing managed API location: ${header}`);
  const end = template.indexOf('\n    }', start);
  assert.notEqual(end, -1, 'The managed location must have a closing brace.');
  return template.slice(start + header.length, end);
}

test('native API redeployment keeps recall requests statically paused before any upstream proxy', () => {
  const body = locationBody('    location ~ ^/v1/recall/(open|respond|diary)$ {');
  // Require an unconditional return, not a commented instruction or a conditional branch.
  const paused = /^        return 503 '([^']+)';$/m.exec(body);
  assert.ok(paused, 'The public proxy must reject old installed clients while AI is paused.');
  const response = JSON.parse(paused[1]);
  assert.equal(response.code, 'AI_DISABLED');
  assert.equal(response.retryable, false);
  assert.ok(typeof response.message === 'string' && response.message.length > 0);
  const upstream = body.indexOf('proxy_pass');
  assert.ok(upstream === -1 || paused.index < upstream, 'The pause must precede upstream forwarding.');
  assert.doesNotMatch(body, /^\s*(?:rewrite|try_files|error_page|include)\s/m, 'No location redirect may bypass the static pause.');
  assert.doesNotMatch(template, /^\s*error_page\s+[^;]*\b503\b/m, 'Do not remap the pause response to another handler.');
});

test('native API health reports the product pause without depending on the stopped gateway', () => {
  const body = locationBody('    location = /health {');
  const health = /^        return 200 '([^']+)';$/m.exec(body);
  assert.ok(health, 'Paused health must be served directly by the public proxy.');
  assert.deepEqual(JSON.parse(health[1]), { ok: true, aiEnabled: false, aiStatus: 'paused' });
  assert.doesNotMatch(body, /^\s*(?:proxy_pass|fastcgi_pass|uwsgi_pass|rewrite|try_files|include)\s/m);
});
