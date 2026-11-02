import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath, pathToFileURL } from 'node:url';
const patchModule = process.env.WEB_GATE_PATCH_MODULE;
const moduleURL = patchModule ? pathToFileURL(path.resolve(patchModule)) : new URL('../scripts/web-parity-gate.mjs', import.meta.url);
const { validateWebEvidence, caseBindings, expectedCategory, MOTION_CRITERIA, REFERENCE_URL, validateOriginalImage } = await import(moduleURL);
const { IOS_INPUTS, REQUIRED_CASE_IDS, hashIOSSource, hashBuild, metadataHash, fixtureHash, overflowIds } = await import(new URL('./parity-evidence.mjs', moduleURL));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
// Synthetic test data only: generated images, fake binary and reviewer identities.
// Never product evidence. Test scratch space remains inside this project.
const scratch = path.resolve(process.env.WEB_GATE_TEST_SCRATCH ?? '.artifacts/ios/web-gate-unit-tests');
fs.mkdirSync(scratch, { recursive: true });
function png(seed) {
  const chunk = (type, bytes) => {
    const body = Buffer.concat([Buffer.from(type), bytes]);
    let crc = 0xffffffff;
    for (const byte of body) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
    const length = Buffer.alloc(4), checksum = Buffer.alloc(4);
    length.writeUInt32BE(bytes.length); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([length, body, checksum]);
  };
  const header = Buffer.alloc(13); header.writeUInt32BE(390); header.writeUInt32BE(844, 4); header[8] = 8; header[9] = 2;
  const data = Buffer.alloc(844 * (1 + 390 * 3)); data.writeUInt32BE(seed, 1);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(data)), chunk('IEND', Buffer.alloc(0))]);
}
function setup(t) {
  const root = fs.mkdtempSync(path.join(scratch, 'synthetic-only-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  let seed = 0;
  const write = (file, content) => {
    const bytes = Buffer.isBuffer(content) || typeof content === 'string' ? content : JSON.stringify(content);
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); fs.writeFileSync(path.join(root, file), bytes);
    return { path: file, sha256: sha(bytes) };
  };
  for (const input of IOS_INPUTS) {
    if (input === 'project.yml') write('apps/ios/project.yml', 'SYNTHETIC TEST SOURCE');
    else fs.mkdirSync(path.join(root, 'apps/ios', input), { recursive: true });
  }
  write('apps/ios/App/Test.swift', '// SYNTHETIC'); write('build/Milo.app/Milo', 'SYNTHETIC BINARY');
  const source = hashIOSSource(root).sourceHash, build = hashBuild(root, 'build/Milo.app');
  const iosManifest = { version: 1, sourceHash: source, build: { path: 'build/Milo.app', sha256: build },
    buildReceipt: { sourceHashBefore: source, sourceHashAfter: source, buildHash: build, exitCode: 0,
      command: ['SYNTHETIC BUILD'], startedAt: '2026-09-29T01:00:00Z', finishedAt: '2026-09-29T01:01:00Z',
      log: write('build.log', 'SYNTHETIC UNIT LOG\n** BUILD SUCCEEDED **') } };
  const run = suite => write(`${suite}.json`, { ...iosManifest, verificationReceipt: {
    ...iosManifest.buildReceipt, command: ['xcodebuild', `-only-testing:MiloUITests/${suite}`, 'test-without-building'],
    startedAt: '2026-09-29T02:00:00Z', finishedAt: '2026-09-29T02:10:00Z',
    log: write(`${suite}.log`, 'SYNTHETIC UNIT LOG\n** TEST SUCCEEDED **') } });
  const captureRun = run('ParityCaptureTests'), motionRun = run('GalaxyMotionTests');
  const device = { name: 'SYNTHETIC UNIT', osVersion: 'fake', viewport: { width: 390, height: 844 }, scale: 1 };
  const fixture = { version: 1, fixtureVersion: 'unit-v1', fixedTime: '2026-09-29T09:41:00+08:00', locale: 'zh_CN', timezone: 'Asia/Shanghai',
    cases: REQUIRED_CASE_IDS.map(id => ({ id, route: id.split('--')[0], state: id.split('--')[1], required: true,
      textSize: id.endsWith('--large-text') ? 'largest-accessibility' : 'default',
      checkpoints: overflowIds.has(id) || id.endsWith('--large-text') ? ['top', 'all-overflow-content', 'bottom'] : ['visible-state'] })) };
  const ledger = { version: 2, referenceURL: REFERENCE_URL, viewport: device.viewport, implementationAuthors: ['unit-implementer'], cases: [] };
  const originalImage = prefix => write(`${prefix}-${++seed}.png`, png(seed));
  function native(row) {
    const capture = { caseId: row.id, fixtureHash: fixtureHash(fixture, row), sourceHash: source, buildHash: build,
      fixtureVersion: fixture.fixtureVersion, fixedTime: fixture.fixedTime, locale: fixture.locale, timezone: fixture.timezone,
      textSize: row.textSize, actualTextSetting: { category: row.textSize === 'default' ? 'large' : 'accessibility5' },
      authoredBy: 'unit-collector', runReceipt: captureRun, device, capturedAt: '2026-09-29T02:02:00Z' };
    const region = id => ({ id, scrollGeometry: { totalContentHeight: 1000, viewportHeight: 500, maxScrollOffset: 500, lastAnchor: `${id}-bottom` },
      images: [0, 250, 500].map((offset, index) => ({ ...originalImage(`${row.id}-${id}`),
        checkpoint: ['top', 'all-overflow-content', 'bottom'][index], contentAnchor: index === 2 ? `${id}-bottom` : `${id}-${index}`,
        scrollOffset: offset, visibleContentHeight: 500,
        accessibility: write(`${row.id}-${id}-${index}.txt`, `SYNTHETIC Other identifier: 'parity-root', value: ${capture.actualTextSetting.category}\nScrollView`),
        geometry: write(`${row.id}-${id}-${index}.json`, { region: id, probe: `parity-scroll-${id}`, scrollOffset: offset,
          totalContentHeight: 1000, viewportHeight: 500, maxScrollOffset: 500, visibleFrame: { x: 0, y: 100, width: 390, height: 500 },
          raw: { frameX: 0, frameY: 100, frameWidth: 390, frameHeight: 500, contentWidth: 390, contentHeight: 1000, offsetY: offset, insetTop: 0 } }) })) });
    const page = region('page'); delete page.id;
    Object.assign(capture, page);
    if (row.id.startsWith('now-note--keyboard-long')) capture.regions = [region('editor')];
    return capture;
  }
  function web(prefix, caseId, frames) {
    const capturedAt = '2026-09-29T02:03:00Z';
    const images = frames ?? [{ ...originalImage(prefix), scrollOffset: 0, visibleContentHeight: 844,
      geometry: write(`${prefix}-web-geometry.json`, { scrollTop: 0, scrollHeight: 844, clientHeight: 844 }) }];
    const provenance = write(`${prefix}-browser.json`, { url: REFERENCE_URL, capturedAt, authoredBy: 'unit-browser', device,
      browser: { name: 'SYNTHETIC', version: 'UNIT' }, actions: [
        { type: 'navigate', url: REFERENCE_URL, at: '2026-09-29T02:00:00Z' },
        ...images.map(i => ({ type: 'screenshot', at: capturedAt, sha256: i.sha256, caseId, criterion: prefix }))] });
    return { caseId, url: REFERENCE_URL, capturedAt, authoredBy: 'unit-browser', device, images, provenance };
  }
  function reviewRef(prefix, bindings, criteria, authorId = 'unit-independent-reviewer') {
    const artifact = write(`${prefix}-review.json`, { authorId, reviewedAt: '2026-09-29T03:00:00Z', verdict: 'pass', bindings,
      findings: [], criteria: Object.fromEntries(criteria.map(k => [k, { verdict: 'pass', notes: 'SYNTHETIC TEST JUDGMENT, not a real review' }])) });
    const authorRecord = write(`${prefix}-author.json`, { authorId, role: 'independent-reviewer', reviewArtifactSha256: artifact.sha256 });
    return { artifact, authorRecord };
  }
  for (const row of fixture.cases) {
    const item = { id: row.id, category: expectedCategory(row.id), status: 'passed', ios: native(row), web: null };
    if (item.category === 'shared') item.web = web(row.id, row.id);
    item.review = reviewRef(row.id, caseBindings(item, row, fixture), ['fidelity', 'readability', 'actions', 'polish']);
    ledger.cases.push(item);
  }
  const motion = { version: 2, sourceHash: source, buildHash: build, runReceipt: motionRun, criteria: {} };
  for (const criterion of MOTION_CRITERIA) {
    const frames = platform => Array.from({ length: criterion === 'natural' ? 3 : 2 }, (_, i) => ({ ...originalImage(`${criterion}-${platform}`),
      capturedAt: `2026-09-29T02:02:0${i}Z`, ...(platform === 'ios' ? { clock: write(`${criterion}-${i}-clock.json`,
        { time: criterion === 'reduceMotion' ? 0 : i, renderReady: 1, active: 0, inactiveDuration: criterion === 'inactiveResume' ? i * 2.5 : 0 }) } : {}) }));
    const ios = { authoredBy: 'unit-collector', device, frames: frames('ios') };
    const item = { ios };
    if (MOTION_CRITERIA.indexOf(criterion) < 5) {
      const sequence = frames('web'); item.web = { ...web(criterion, undefined, sequence), frames: sequence }; delete item.web.images;
    }
    motion.criteria[criterion] = item;
  }
  motion.review = reviewRef('motion', { motion: metadataHash(motion) }, MOTION_CRITERIA);
  return { root, ledger, fixture, iosManifest, motion, write, reviewRef };
}
const fail = (data, pattern) => { const result = validateWebEvidence(data); assert.equal(result.passed, false); assert.match(result.errors.join('\n'), pattern); };
const firstShared = data => data.ledger.cases.find(r => r.category === 'shared');
function rebind(data, row) { row.review = data.reviewRef(row.id, caseBindings(row, data.fixture.cases.find(r => r.id === row.id), data.fixture), ['fidelity', 'readability', 'actions', 'polish']); }

test('synthetic complete 53-state structure passes without representing product approval', t => {
  const data = setup(t), result = validateWebEvidence(data); assert.equal(result.passed, true, result.errors.join('\n')); assert.equal(result.passedCases, 53);
});
const cases = [
  ['missing state', d => d.ledger.cases.pop(), /exact 53/],
  ['extra state', d => d.ledger.cases.push({ ...d.ledger.cases[0], id: 'extra' }), /exact 53/],
  ['shared reclassified native', d => firstShared(d).category = 'native-only', /category changed/],
  ['required checkpoints removed', d => d.fixture.cases.find(r => r.id === 'diary--long').checkpoints = ['visible-state'], /continuous coverage removed/],
  ['stale source', d => d.write('apps/ios/App/New.swift', '// changed'), /stale source/],
  ['changed built app', d => d.write('build/Milo.app/Milo', 'changed'), /build bytes changed/],
  ['missing build receipt', d => delete d.iosManifest.buildReceipt, /build receipt/],
  ['arbitrary text as image even with updated hashes', d => { const r = d.ledger.cases[0]; r.ios.images[0] = { ...r.ios.images[0], ...d.write(r.ios.images[0].path, 'not PNG') }; rebind(d, r); }, /complete PNG/],
  ['declared PNG dimensions lie', d => d.ledger.cases[0].ios.device = { ...d.ledger.cases[0].ios.device, scale: 2 }, /PNG dimensions/],
  ['large-text downgraded', d => d.ledger.cases.at(-1).ios.actualTextSetting.category = 'large', /actual text category/],
  ['raw AX setting contradicts declared DynamicType', d => { const s = d.ledger.cases.at(-1).ios.images[0]; s.accessibility = d.write(s.accessibility.path, "Other identifier: 'parity-root', value: large\naccessibility5 elsewhere"); }, /actual DynamicType/],
  ['removed original geometry', d => delete d.ledger.cases[0].ios.images[0].geometry, /omitted original geometry/],
  ['forged normalized offset', d => { const r = d.ledger.cases[0], shot = r.ios.images[1]; const g = JSON.parse(fs.readFileSync(path.join(d.root, shot.geometry.path))); g.raw.offsetY = 20; shot.geometry = d.write(shot.geometry.path, g); rebind(d, r); }, /contradicts raw geometry/],
  ['coverage gap', d => d.ledger.cases[0].ios.images[1].scrollOffset = 490, /overlap/],
  ['missing nested editor', d => delete d.ledger.cases.find(r => r.id === 'now-note--keyboard-long').ios.regions, /nested editor/],
  ['missing run receipt', d => delete d.ledger.cases[0].ios.runReceipt, /relative/],
  ['arbitrary review text', d => d.ledger.cases[0].review.artifact = d.write('bad-review.txt', 'passed'), /Unexpected token|JSON/],
  ['review stale after capture metadata change', d => d.ledger.cases[0].ios.device.name = 'different observed device', /bound metadata stale/],
  ['reviewer is implementer', d => { const r = d.ledger.cases[0]; r.review = d.reviewRef(r.id, caseBindings(r, d.fixture.cases[0], d.fixture), ['fidelity', 'readability', 'actions', 'polish'], 'unit-implementer'); }, /self-authored/],
  ['missing independent author record', d => delete d.ledger.cases[0].review.authorRecord, /relative/],
  ['missing actual external capture', d => firstShared(d).web = null, /Web capture belongs/],
  ['Web provenance URL mismatch', d => firstShared(d).web.url = 'http://localhost/app', /external Web/],
  ['Web PNG is arbitrary text', d => { const r = firstShared(d); r.web.images[0] = { ...r.web.images[0], ...d.write(r.web.images[0].path, 'bad') }; rebind(d, r); }, /complete PNG/],
  ['Web review stale after provenance update', d => { const r = firstShared(d), p = JSON.parse(fs.readFileSync(path.join(d.root, r.web.provenance.path))); p.browser.version = 'changed'; r.web.provenance = d.write(r.web.provenance.path, p); }, /bound metadata stale/],
  ['Web content not fully inspected', d => { const r = firstShared(d), shot = r.web.images[0]; shot.geometry = d.write(shot.geometry.path, { scrollTop: 0, clientHeight: 844, scrollHeight: 1600 }); rebind(d, r); }, /reach bottom/],
  ['motion missing criterion', d => delete d.motion.criteria.scrollInput, /seven temporal/],
  ['motion stale build', d => d.motion.buildHash = '0'.repeat(64), /motion source\/build/],
  ['motion static sequence', d => { const frames = d.motion.criteria.natural.ios.frames; frames[1] = { ...frames[1], path: frames[0].path, sha256: frames[0].sha256 }; }, /repeats static/],
  ['motion reviewer not bound', d => d.motion.criteria.controlTouch.ios.device.name = 'changed', /bound metadata stale/],
  ['reduced-motion clock still running', d => { const f = d.motion.criteria.reduceMotion.ios.frames[1]; f.clock = d.write(f.clock.path, { time: 1, active: 1, renderReady: 1 }); }, /reduced motion remains active/],
  ['motion original clock missing', d => delete d.motion.criteria.blankTouch.ios.frames[0].clock, /relative/],
];
for (const [name, mutate, pattern] of cases) test(name, t => { const data = setup(t); mutate(data); fail(data, pattern); });

test('actual Web detail action may reference native confirmation only with an image-bound deviation', t => {
  const d = setup(t), r = d.ledger.cases.find(r => r.id === 'detail--delete-confirmation');
  r.web.sourceCaseId = 'detail--now';
  const record = JSON.parse(fs.readFileSync(path.join(d.root, r.web.provenance.path)));
  record.actions.filter(a => a.type === 'screenshot').forEach(a => a.caseId = 'detail--now');
  r.web.fixtureDifferences = [{ field: 'displayed-date', webValue: '2026-09-29', iosValue: '2026-09-26' }];
  record.fixtureDifferences = r.web.fixtureDifferences;
  r.web.provenance = d.write(r.web.provenance.path, record);
  rebind(d, r);
  fail(d, /source-action deviation/);
  const revise = findings => {
    const review = JSON.parse(fs.readFileSync(path.join(d.root, r.review.artifact.path)));
    review.findings = findings; r.review.artifact = d.write(r.review.artifact.path, review);
    r.review.authorRecord = d.write(r.review.authorRecord.path, { authorId: review.authorId, role: 'independent-reviewer', reviewArtifactSha256: r.review.artifact.sha256 });
  };
  const source = { status: 'accepted-deviation', sourceCaseId: 'detail--now', sourcePlatform: 'web', platform: 'web', sha256: r.web.images[0].sha256,
    sourceAction: 'SYNTHETIC: observed detail action, not a fabricated Web modal', notes: 'SYNTHETIC difference review' };
  revise([source]); fail(d, /fixture\/date difference/);
  revise([source, { status: 'accepted-deviation', kind: 'fixture-difference', ...r.web.fixtureDifferences[0],
    imageHashes: r.web.images.map(i => i.sha256), notes: 'SYNTHETIC: real Web date retained, native fixture date unchanged' }]);
  const result = validateWebEvidence(d); assert.equal(result.passed, true, result.errors.join('\n'));
});

// Synthetic 390×844 grayscale JPEG, encoded once for decoder tests; not a product capture.
const JPEG_UNIT = Buffer.from('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCANMAYYBAREA/8QAFQABAQAAAAAAAAAAAAAAAAAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAA/AIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//Z', 'base64');

function jpegFixture(t, bytes = JPEG_UNIT) {
  const root = fs.mkdtempSync(path.join(scratch, 'jpeg-unit-only-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = 'original.jpg'; fs.writeFileSync(path.join(root, file), bytes);
  return { root, item: { path: file, sha256: sha(bytes) }, device: { viewport: { width: 390, height: 844 }, scale: 1 } };
}
test('a genuine Web JPEG original passes without converting or changing its bytes', t => {
  const data = jpegFixture(t), before = fs.readFileSync(path.join(data.root, data.item.path));
  validateOriginalImage(data.root, data.item, data.device, 'Web unit', { web: true });
  assert.deepEqual(fs.readFileSync(path.join(data.root, data.item.path)), before);
});
test('genuine browser JPEG participates in the full 53-state gate and bound review', t => {
  const data = setup(t), row = firstShared(data), shot = row.web.images[0];
  const artifact = data.write('actual-format-unit.jpg', JPEG_UNIT);
  row.web.images[0] = { ...shot, ...artifact };
  const record = JSON.parse(fs.readFileSync(path.join(data.root, row.web.provenance.path)));
  record.actions.filter(a => a.type === 'screenshot').forEach(a => a.sha256 = artifact.sha256);
  row.web.provenance = data.write(row.web.provenance.path, record); rebind(data, row);
  const result = validateWebEvidence(data); assert.equal(result.passed, true, result.errors.join('\n'));
});
test('Web format follows original bytes even when the original filename said PNG', t => {
  const data = jpegFixture(t);
  fs.renameSync(path.join(data.root, data.item.path), path.join(data.root, 'misnamed.png'));
  data.item.path = 'misnamed.png';
  validateOriginalImage(data.root, data.item, data.device, 'Web unit', { web: true });
});
test('native image verification still refuses JPEG originals', t => {
  const data = jpegFixture(t);
  assert.throws(() => validateOriginalImage(data.root, data.item, data.device, 'native'), /complete PNG/);
});
test('Web JPEG hash mismatch is rejected before decode', t => {
  const data = jpegFixture(t); data.item.sha256 = '0'.repeat(64);
  assert.throws(() => validateOriginalImage(data.root, data.item, data.device, 'Web', { web: true }), /hash mismatch/);
});
test('Web JPEG recorded dimensions must match decoded pixels', t => {
  const data = jpegFixture(t); data.device.scale = 2;
  assert.throws(() => validateOriginalImage(data.root, data.item, data.device, 'Web', { web: true }), /JPEG dimensions/);
});
for (const [name, bytes] of [
  ['missing end marker', JPEG_UNIT.subarray(0, -2)],
  ['only JPEG magic surrounding text', Buffer.concat([Buffer.from([255,216]), Buffer.from('not an image'), Buffer.from([255,217])])],
  ['truncated scan with a forged end marker', Buffer.concat([JPEG_UNIT.subarray(0, Math.floor(JPEG_UNIT.length / 2)), Buffer.from([255,217])])],
]) test('reject Web JPEG: ' + name, t => {
  const data = jpegFixture(t, bytes);
  assert.throws(() => validateOriginalImage(data.root, data.item, data.device, 'Web', { web: true }), /JPEG.*(?:truncated|invalid|decode failed)/);
});
