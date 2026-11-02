import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { validateReceipt, awaitReceipt } from './await-review.mjs';

const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function fixture(t) {
  const directory = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'milo-visual-review-')));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const evidenceDirectory = path.join(directory, 'evidence');
  fs.mkdirSync(evidenceDirectory);
  const bundle = 'ui-test-current.xcresult';
  fs.mkdirSync(path.join(evidenceDirectory, bundle));
  const screenshots = ['light.png', 'dark.png'].map(file => {
    fs.writeFileSync(path.join(evidenceDirectory, file), file);
    return { path: file, sha256: digest(file) };
  });
  const context = { runId: '123', headSha: 'a'.repeat(40), evidenceDirectory, ui: { sourceHash: 'b'.repeat(64), bundle: path.join(evidenceDirectory, bundle) } };
  const receipt = {
    version: 1, runId: context.runId, headSha: context.headSha, sourceHash: context.ui.sourceHash,
    bundle, reviewer: 'independent reviewer', reviewedAt: '2026-09-26T01:00:00Z', verdict: 'pass', screenshots,
    checks: { keyboardReachable: true, longChineseText: true, accessibilityText: true, lightAppearance: true, darkAppearance: true },
  };
  return { directory, context, receipt };
}

test('a review for this exact run maps verified screenshots and bundle to current absolute paths', t => {
  const { context, receipt } = fixture(t);
  const result = validateReceipt(receipt, context);
  assert.equal(result.bundle, context.ui.bundle);
  assert.equal(result.runId, '123');
  assert.deepEqual(result.screenshots, receipt.screenshots.map(item => path.join(context.evidenceDirectory, item.path)));
});

test('another run, source revision, source hash, or result bundle cannot reuse a receipt', t => {
  const { context, receipt } = fixture(t);
  for (const [field, value] of [['runId', '122'], ['headSha', 'c'.repeat(40)], ['sourceHash', 'd'.repeat(64)], ['bundle', 'old.xcresult']]) {
    assert.throws(() => validateReceipt({ ...receipt, [field]: value }, context));
  }
});

test('missing review assertions or actual approval are rejected', t => {
  const { context, receipt } = fixture(t);
  for (const change of [{ verdict: 'fail' }, { reviewer: '' }, { reviewedAt: 'never' }, { checks: {} }, { screenshots: [] }]) {
    assert.throws(() => validateReceipt({ ...receipt, ...change }, context));
  }
});

test('changed screenshot bytes, repeated images, path traversal and symlink escape are rejected', t => {
  const { directory, context, receipt } = fixture(t);
  const screenshot = receipt.screenshots[0];
  assert.throws(() => validateReceipt({ ...receipt, screenshots: [{ ...screenshot, sha256: 'f'.repeat(64) }, receipt.screenshots[1]] }, context));
  assert.throws(() => validateReceipt({ ...receipt, screenshots: [screenshot, screenshot] }, context));
  const external = path.join(directory, 'outside.png');
  fs.writeFileSync(external, 'outside');
  fs.symlinkSync(external, path.join(context.evidenceDirectory, 'escaped.png'));
  for (const file of ['../outside.png', external, 'escaped.png']) {
    assert.throws(() => validateReceipt({ ...receipt, screenshots: [{ path: file, sha256: digest('outside') }, receipt.screenshots[1]] }, context));
  }
});

test('bounded polling waits through stale and malformed receipts then accepts the real review', async () => {
  let time = 0, calls = 0;
  const result = await awaitReceipt({
    timeoutMs: 100, intervalMs: 10, now: () => time, sleep: async ms => { time += ms; }, report: () => {},
    readReceipt: async () => { calls++; if (calls === 1) throw new Error('missing'); return calls === 2 ? 'stale' : 'reviewed'; },
    acceptReceipt: value => { if (value !== 'reviewed') throw new Error('wrong run'); return { verdict: 'pass' }; },
  });
  assert.deepEqual(result, { verdict: 'pass' });
  assert.equal(calls, 3);
});

test('an unavailable or rejected review times out without writing or fabricating approval', async () => {
  let time = 0;
  const result = await awaitReceipt({
    timeoutMs: 25, intervalMs: 10, now: () => time, sleep: async ms => { time += ms; }, report: () => {},
    readReceipt: async () => { throw new Error('HTTP 404'); }, acceptReceipt: () => assert.fail('must not approve missing evidence'),
  });
  assert.equal(result, null);
  assert.equal(time, 25);
});

test('polling refuses an unbounded wait or a response arriving after the deadline', async () => {
  await assert.rejects(awaitReceipt({ timeoutMs: 600001 }));
  let time = 0;
  const result = await awaitReceipt({
    timeoutMs: 10, now: () => time, report: () => {},
    readReceipt: async () => { time = 11; return { verdict: 'pass' }; }, acceptReceipt: () => assert.fail('too late'),
  });
  assert.equal(result, null);
});
