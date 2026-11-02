import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { IOS_INPUTS, REQUIRED_CASE_IDS, fingerprint, hashIOSSource, hashBuild, validateEvidence, renderReport, fixtureHash, captureMetadataHash } from '../scripts/parity-evidence.mjs';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const reviewedLedger = JSON.parse(fs.readFileSync(path.join(project, 'docs/visual-parity/cases.json'), 'utf8'));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
// Every image and approval below is synthetic unit-test data in a disposable
// temporary directory. None is a product screenshot or a real visual receipt.
function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}
function unitPNG(seed) {
  const chunk = (type, bytes) => {
    const data = Buffer.concat([Buffer.from(type), bytes]);
    const size = Buffer.alloc(4); size.writeUInt32BE(bytes.length);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(data));
    return Buffer.concat([size, data, crc]);
  };
  const header = Buffer.alloc(13); header.writeUInt32BE(4); header.writeUInt32BE(8, 4); header[8] = 8; header[9] = 2;
  const pixels = Buffer.alloc(8 * (1 + 4 * 3));
  for (let row = 0; row < 8; row++) for (let col = 0; col < 12; col++) pixels[row * 13 + col + 1] = (seed + col + row) % 256;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}
function write(root, file, value) {
  fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
  fs.writeFileSync(path.join(root, file), value);
}
function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'milo-parity-unit-only-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const input of IOS_INPUTS) {
    if (input === 'project.yml') write(root, `apps/ios/${input}`, 'unit fixture project');
    else fs.mkdirSync(path.join(root, 'apps/ios', input), { recursive: true });
  }
  write(root, 'apps/ios/App/App.swift', '// Synthetic source; no actual app build.');
  write(root, 'apps/harmony/entry/src/main/ets/pages/Index.ets', '// Synthetic reference');
  write(root, 'apps/harmony/AppScope/app.json5', '{}');
  write(root, 'build/ios.app/Milo', 'synthetic binary bytes, not executable');
  write(root, 'build/reference.hap', 'synthetic HAP bytes, not an app');
  const harmonyManifest = { ...fingerprint(root, ['apps/harmony/entry/src/main', 'apps/harmony/AppScope']), build: { path: 'build/reference.hap', sha256: hashBuild(root, 'build/reference.hap') } };
  const iosManifest = { ...hashIOSSource(root), build: { path: 'build/ios.app', sha256: hashBuild(root, 'build/ios.app') } };
  for (const [platform, manifest] of [['harmony', harmonyManifest], ['ios', iosManifest]]) {
    const log = `SYNTHETIC UNIT TEST LOG — no real build\n${platform === 'ios' ? '** BUILD SUCCEEDED **' : 'BUILD SUCCESSFUL'}\n`;
    write(root, `logs/${platform}.log`, log);
    manifest.buildReceipt = { sourceHashBefore: manifest.sourceHash, sourceHashAfter: manifest.sourceHash,
      buildHash: manifest.build.sha256, command: ['synthetic-unit-build', platform], startedAt: '2026-09-26T01:00:00Z', finishedAt: '2026-09-26T01:01:00Z', exitCode: 0,
      log: { path: `logs/${platform}.log`, sha256: sha(log) } };
  }
  const ledger = structuredClone(reviewedLedger);
  let seed = 0;
  for (const item of ledger.cases) {
    for (const platform of ['harmony', 'ios']) {
      const provenance = platform === 'harmony' ? harmonyManifest : iosManifest;
      item[platform] = {
        caseId: item.id, fixtureHash: fixtureHash(ledger, item),
        sourceHash: provenance.sourceHash, buildHash: provenance.build.sha256,
        fixtureVersion: ledger.fixtureVersion, fixedTime: ledger.fixedTime, locale: ledger.locale, timezone: ledger.timezone,
        textSize: item.textSize, actualTextSetting: platform === 'ios' ? { category: item.textSize === 'default' ? 'large' : 'accessibility5', description: 'Synthetic unit-test setting' } : { scale: item.textSize === 'default' ? 1 : 2, defaultScale: 1, maxSupportedScale: 2, description: 'Synthetic unit-test setting' },
        capturedAt: '2026-09-26T02:00:00Z', device: { name: 'UNIT FIXTURE — not a device', osVersion: 'synthetic', viewport: { width: 4, height: 8 }, scale: 1 },
        images: item.checkpoints.map((checkpoint, index) => {
          const image = unitPNG(seed++);
          const relative = `images/${item.id}-${platform}-${index}.png`;
          write(root, relative, image);
          return { checkpoint, path: relative, sha256: sha(image), scrollOffset: index * 4,
            contentAnchor: `UNIT FIXTURE region ${index}`, visibleContentHeight: 8 };
        }),
      };
      if (item.checkpoints.includes('all-overflow-content')) item[platform].scrollGeometry = { totalContentHeight: 16, viewportHeight: 8, maxScrollOffset: 8, lastAnchor: 'UNIT FIXTURE region 2' };
    }
    item.review = {
      verdict: 'pass', reviewer: 'UNIT TEST ONLY — no real review', reviewedAt: '2026-09-26T03:00:00Z',
      caseId: item.id, fixtureHash: item.harmony.fixtureHash,
      sourceHashes: { harmony: harmonyManifest.sourceHash, ios: iosManifest.sourceHash },
      buildHashes: { harmony: harmonyManifest.build.sha256, ios: iosManifest.build.sha256 },
      captureHashes: Object.fromEntries(['harmony', 'ios'].map(name => [name, captureMetadataHash(item[name])])),
      imageHashes: Object.fromEntries(['harmony', 'ios'].map(name => [name, item[name].images.map(image => image.sha256)])), findings: [],
      ...Object.fromEntries(['fidelity', 'readability', 'actions', 'polish'].map(key => [key, { verdict: 'pass', notes: 'Synthetic validation fixture only; not a product judgement.' }])),
    };
  }
  return { ledger, harmonyManifest, iosManifest, harmonyRoot: root, iosRoot: root, evidenceRoot: root, root };
}
const validate = data => validateEvidence(data);
const failure = (data, pattern) => {
  const result = validate(data); assert.equal(result.passed, false); assert.match(result.errors.join('\n'), pattern);
};
function refreshCaptureReview(item) {
  item.review.captureHashes = Object.fromEntries(['harmony', 'ios'].map(name => [name, captureMetadataHash(item[name])]));
  item.review.imageHashes = Object.fromEntries(['harmony', 'ios'].map(name => [name, item[name].images.map(image => image.sha256)]));
}

test('complete synthetic structure covers the reviewed minimum, including overflow and large text', t => {
  const data = fixture(t);
  assert.equal(REQUIRED_CASE_IDS.length, 53);
  const result = validate(data);
  assert.equal(result.passed, true, result.errors.join('\n'));
  assert.equal(result.passedCases, 53);
});

test('removing a required case or marking it optional cannot reduce acceptance scope', t => {
  const data = fixture(t);
  const removed = data.ledger.cases.pop();
  failure(data, /missing required case/);
  data.ledger.cases.push({ ...removed, required: false });
  failure(data, /cannot be removed/);
});

test('a missing paired checkpoint fails, and deleting its requirement also fails', t => {
  const data = fixture(t);
  const item = data.ledger.cases.find(row => row.id === 'account--local');
  item.ios.images = item.ios.images.filter(image => image.checkpoint !== 'all-overflow-content');
  failure(data, /missing checkpoint all-overflow-content/);
  item.checkpoints = ['top', 'bottom'];
  failure(data, /reviewed checkpoint removed/);
});

test('modified source, newly added reference source and changed build bytes are stale', t => {
  const data = fixture(t);
  write(data.root, 'apps/ios/App/New.swift', '// change');
  failure(data, /ios: stale source hash/);
  fs.unlinkSync(path.join(data.root, 'apps/ios/App/New.swift'));
  write(data.root, 'apps/harmony/entry/src/main/resources/dark/color.json', '{}');
  failure(data, /harmony: stale source hash/);
  fs.unlinkSync(path.join(data.root, 'apps/harmony/entry/src/main/resources/dark/color.json'));
  write(data.root, 'build/ios.app/Milo', 'modified binary');
  failure(data, /ios: build bytes changed/);
});

test('changed PNG bytes and a stale image review are both rejected', t => {
  const data = fixture(t);
  const item = data.ledger.cases[0];
  const image = item.ios.images[0];
  const changed = unitPNG(250);
  write(data.root, image.path, changed);
  failure(data, /image hash changed/);
  image.sha256 = sha(changed);
  failure(data, /capture metadata changed|reviewed images differ/);
});

test('a rebuilt app needs review bound to its build, even if source and image bytes are unchanged', t => {
  const data = fixture(t);
  write(data.root, 'build/ios.app/Milo', 'new binary from a different build');
  data.iosManifest.build.sha256 = hashBuild(data.root, 'build/ios.app');
  data.iosManifest.buildReceipt.buildHash = data.iosManifest.build.sha256;
  for (const item of data.ledger.cases) item.ios.buildHash = data.iosManifest.build.sha256;
  failure(data, /review: ios build is stale/);
});

test('fixture data, text size, actual setting and stale review source are checked', t => {
  const data = fixture(t);
  const item = data.ledger.cases[0];
  const capture = structuredClone(item.ios);
  for (const [field, value, pattern] of [
    ['fixtureVersion', 'other', /fixture version/], ['fixedTime', '2020-01-01', /fixture time/],
    ['textSize', 'largest-accessibility', /text size/], ['actualTextSetting', '', /actual setting/],
  ]) {
    item.ios = { ...capture, [field]: value }; failure(data, pattern);
  }
  item.ios = capture;
  item.review.sourceHashes.ios = '0'.repeat(64);
  failure(data, /review: ios source is stale/);
});

test('overflow captures must be ordered, overlap and describe successive content', t => {
  const data = fixture(t);
  const item = data.ledger.cases.find(row => row.id === 'account--local');
  const originals = structuredClone(item.ios.images);
  item.ios.images[1].scrollOffset = 20;
  failure(data, /overflow order\/gap|image geometry/);
  item.ios.images = structuredClone(originals);
  item.ios.images[1].contentAnchor = item.ios.images[0].contentAnchor;
  failure(data, /overflow anchors/);
  item.ios.images = structuredClone(originals);
  delete item.ios.images[1].visibleContentHeight;
  failure(data, /visible content height/);
});

test('independent review must be complete, dated after capture and have no unresolved findings', t => {
  const data = fixture(t);
  const item = data.ledger.cases[0];
  const original = structuredClone(item.review);
  for (const changed of [null, { ...original, verdict: 'fail' }, { ...original, reviewer: '' },
    { ...original, reviewedAt: '2020-01-01' }, { ...original, findings: [{ status: 'open', notes: 'clipped button' }] },
    { ...original, polish: { verdict: 'pass', notes: '' } }]) {
    item.review = changed; assert.equal(validate(data).passed, false);
  }
});

test('path traversal, symlink escape and metadata that disagrees with PNG size fail', t => {
  const data = fixture(t);
  const item = data.ledger.cases[0];
  const image = item.ios.images[0];
  const original = image.path;
  image.path = '../outside.png'; failure(data, /path escapes/);
  image.path = original;
  item.ios.device.viewport.width = 400; failure(data, /PNG dimensions/);
  item.ios.device.viewport.width = 4;
  const external = path.join(path.dirname(data.root), `${path.basename(data.root)}-outside.png`);
  fs.writeFileSync(external, unitPNG(10)); t.after(() => fs.rmSync(external, { force: true }));
  fs.symlinkSync(external, path.join(data.root, 'escaped.png'));
  image.path = 'escaped.png'; failure(data, /symlink escapes/);
});

test('source hash ignores generated output while complete build hashing includes resource folders named build', t => {
  const data = fixture(t);
  const before = hashIOSSource(data.root).sourceHash;
  write(data.root, 'apps/ios/MiloCore/.build/output', 'generated output');
  assert.equal(hashIOSSource(data.root).sourceHash, before);
  write(data.root, 'apps/ios/Resources/asset.png', 'new product resource');
  assert.notEqual(hashIOSSource(data.root).sourceHash, before);
  const build = hashBuild(data.root, 'build/ios.app');
  write(data.root, 'build/ios.app/build/product-resource', 'runtime data');
  assert.notEqual(hashBuild(data.root, 'build/ios.app'), build);
});

test('pending report shows original links only when available and escapes untrusted content', t => {
  const data = fixture(t);
  data.ledger.cases[0].review.polish.notes = '<script>alert("bad")</script>';
  data.ledger.cases[1].harmony = null; data.ledger.cases[1].review = null;
  const html = renderReport({ ...data, result: validate(data), output: path.join(data.root, 'report.html') });
  assert.match(html, /验收尚未完成/);
  assert.match(html, /待采集原图/);
  assert.match(html, /打开原图/);
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /<script>/);
});

test('CLI validation exits nonzero for the real pending ledger without creating a receipt', t => {
  const data = fixture(t);
  const casesFile = path.join(data.root, 'cases.json');
  fs.writeFileSync(casesFile, JSON.stringify(reviewedLedger));
  fs.writeFileSync(path.join(data.root, 'harmony-source.json'), JSON.stringify({ ...data.harmonyManifest, referenceRoot: data.root }));
  fs.writeFileSync(path.join(data.root, 'ios-source-build.json'), JSON.stringify(data.iosManifest));
  const run = spawnSync(process.execPath, [path.join(project, 'apps/ios/scripts/parity-evidence.mjs'), 'validate', '--root', data.root, '--cases', casesFile], { encoding: 'utf8' });
  assert.equal(run.status, 1);
  assert.equal(JSON.parse(run.stdout).passed, false);
  assert.equal(fs.existsSync(path.join(data.root, 'visual-review.json')), false);
});

test('new source cannot reuse an old build by refreshing only manifest/capture/review source hashes', t => {
  const data = fixture(t);
  write(data.root, 'apps/ios/App/App.swift', '// newly changed source, deliberately no new build');
  data.iosManifest.sourceHash = hashIOSSource(data.root).sourceHash;
  for (const item of data.ledger.cases) {
    item.ios.sourceHash = data.iosManifest.sourceHash;
    item.review.sourceHashes.ios = data.iosManifest.sourceHash;
    refreshCaptureReview(item);
  }
  failure(data, /build receipt is missing or belongs to different source/);
});

test('build receipts need successful results, ordered times and unchanged genuine-format logs', t => {
  const data = fixture(t);
  const original = structuredClone(data.iosManifest.buildReceipt);
  for (const changed of [null, { ...original, exitCode: 65 }, { ...original, command: [] },
    { ...original, startedAt: '2026-09-26T04:00:00Z' }, { ...original, buildHash: '0'.repeat(64) }]) {
    data.iosManifest.buildReceipt = changed; assert.equal(validate(data).passed, false);
  }
  data.iosManifest.buildReceipt = original;
  write(data.root, original.log.path, 'modified build log'); failure(data, /build log missing or changed/);
  const fake = 'exit zero but no native success output';
  write(data.root, original.log.path, fake); original.log.sha256 = sha(fake);
  failure(data, /build log lacks successful native build output/);
  const nativeTest = 'SYNTHETIC UNIT TEST native-test output\n** TEST SUCCEEDED **\n';
  write(data.root, original.log.path, nativeTest); original.log.sha256 = sha(nativeTest);
  const result = validate(data); assert.equal(result.passed, true, result.errors.join('\n'));
});

test('build-for-testing success is accepted but captures still must follow the prebuild completion', t => {
  const data = fixture(t), receipt = data.iosManifest.buildReceipt;
  const log = 'SYNTHETIC UNIT TEST prebuild output\n** TEST BUILD SUCCEEDED **\n';
  write(data.root, receipt.log.path, log);
  receipt.log.sha256 = sha(log);
  receipt.command = ['xcodebuild', 'build-for-testing', 'SYNTHETIC-UNIT-FIXTURE'];
  const result = validate(data); assert.equal(result.passed, true, result.errors.join('\n'));
  receipt.finishedAt = '2026-09-26T02:01:00Z';
  failure(data, /capture predates this build/);
});

test('a PNG header alone cannot pass even after all image and metadata hashes are refreshed', t => {
  const data = fixture(t), item = data.ledger.cases[0], image = item.ios.images[0];
  const truncated = fs.readFileSync(path.join(data.root, image.path)).subarray(0, 33);
  write(data.root, image.path, truncated); image.sha256 = sha(truncated); refreshCaptureReview(item);
  failure(data, /complete PNG|PNG.*truncated|PNG IEND/);
});

test('corrupt PNG chunks fail CRC even when recorded hashes agree with the corruption', t => {
  const data = fixture(t), item = data.ledger.cases[0], image = item.ios.images[0];
  const corrupt = fs.readFileSync(path.join(data.root, image.path)); corrupt[35] ^= 1;
  write(data.root, image.path, corrupt); image.sha256 = sha(corrupt); refreshCaptureReview(item);
  failure(data, /PNG chunk/);
});

test('copying another case capture/review fails and relabelled duplicate pictures require disclosed source-action review', t => {
  const data = fixture(t), original = data.ledger.cases[0], target = data.ledger.cases[1];
  for (const key of ['harmony', 'ios', 'review']) target[key] = structuredClone(original[key]);
  failure(data, /capture belongs to another case/);
  const targetFixture = fixtureHash(data.ledger, target);
  for (const name of ['harmony', 'ios']) { target[name].caseId = target.id; target[name].fixtureHash = targetFixture; }
  target.review.caseId = target.id; target.review.fixtureHash = targetFixture; refreshCaptureReview(target);
  failure(data, /duplicate image needs an explicit source-action/);
  target.review.findings = ['harmony', 'ios'].map(platform => ({ status: 'accepted-deviation', platform, sourcePlatform: platform,
    sourceCaseId: original.id, sha256: target[platform].images[0].sha256, sourceAction: 'UNIT TEST deliberate reference-action reuse', notes: 'Synthetic test of explicit source-action exception, not real product acceptance.' }));
  const result = validate(data); assert.equal(result.passed, true, result.errors.join('\n'));
});

test('changing global fixture data invalidates captures and their review despite an unchanged version label', t => {
  const data = fixture(t); data.ledger.syntheticNote = '完全不同内容';
  failure(data, /fixture data hash mismatch/);
});

test('three almost identical offsets cannot claim to reach the end of a measured long page', t => {
  const data = fixture(t), item = data.ledger.cases.find(row => row.id === 'diary--long');
  item.ios.images.forEach((image, index) => { image.scrollOffset = index; });
  refreshCaptureReview(item);
  failure(data, /bottom image does not reach the measured end/);
});

test('changing scroll extent, last anchor or any capture metadata also invalidates the prior review', t => {
  const data = fixture(t), item = data.ledger.cases.find(row => row.id === 'diary--long');
  item.ios.images.forEach((image, index) => { image.scrollOffset = index; });
  item.ios.scrollGeometry.totalContentHeight = 10; item.ios.scrollGeometry.maxScrollOffset = 2;
  failure(data, /capture metadata changed/);
  refreshCaptureReview(item);
  item.ios.scrollGeometry.lastAnchor = 'unseen final paragraph';
  failure(data, /bottom image does not reach the measured end\/last anchor/);
});

test('measured no-overflow pages use one real full-content picture, including maximum text cases', t => {
  const data = fixture(t), item = data.ledger.cases.find(row => row.id === 'timeline--populated--large-text');
  for (const platform of ['harmony', 'ios']) {
    const capture = item[platform], image = capture.images[0];
    image.checkpoint = 'full-content'; image.coversCheckpoints = [...item.checkpoints];
    capture.images = [image]; capture.scrollGeometry = { totalContentHeight: 6, viewportHeight: 8, maxScrollOffset: 0, lastAnchor: image.contentAnchor };
  }
  refreshCaptureReview(item);
  const result = validate(data); assert.equal(result.passed, true, result.errors.join('\n'));
  item.ios.scrollGeometry.totalContentHeight = 12;
  failure(data, /max scroll offset disagrees with measured content extent/);
});

test('a nonempty default label or wrong actual category/scale cannot claim maximum text coverage', t => {
  const data = fixture(t), item = data.ledger.cases.find(row => row.id === 'timeline--populated--large-text');
  for (const setting of ['default', { category: 'large', description: 'Nonempty but wrong' }, { category: 'UICTContentSizeCategoryL' }, { category: 'accessibility4' }]) {
    item.ios.actualTextSetting = setting; refreshCaptureReview(item);
    failure(data, /actual setting must record|actual text category contradicts/);
  }
  item.ios.actualTextSetting = { category: 'UICTContentSizeCategoryAccessibilityXXXL', description: 'Synthetic UIKit maximum alias' };
  for (const setting of [{ scale: 1, defaultScale: 1, maxSupportedScale: 2 }, { scale: 2, defaultScale: 1 }, { scale: 1, defaultScale: 1, maxSupportedScale: 1 }]) {
    item.harmony.actualTextSetting = setting; refreshCaptureReview(item);
    failure(data, /text scales are required|actual text scale contradicts/);
  }
  item.harmony.actualTextSetting = { scale: 2, defaultScale: 1, maxSupportedScale: 2, description: 'Synthetic measured maximum' };
  refreshCaptureReview(item);
  const result = validate(data); assert.equal(result.passed, true, result.errors.join('\n'));
  const defaultItem = data.ledger.cases[0];
  defaultItem.ios.actualTextSetting = { category: 'accessibility5' }; refreshCaptureReview(defaultItem);
  failure(data, /actual text category contradicts required default/);
});
