#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { REQUIRED_CASE_IDS, metadataHash, fixtureHash, checkProvenance, validateCapture,
  pngSize, contained, overflowIds } from './parity-evidence.mjs';

const check = (ok, message) => { if (!ok) throw Error(message); };
const text = value => typeof value === 'string' && value.trim().length > 0;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const date = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
const close = (a, b) => Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= 1;
const same = (a, b) => metadataHash(a) === metadataHash(b);
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
export const REFERENCE_URL = 'https://milo.huangtangai.top/app';
export const MOTION_CRITERIA = ['natural', 'blankTouch', 'controlTouch', 'moodSwitch', 'scrollInput', 'reduceMotion', 'inactiveResume'];
export const expectedCategory = id => id.endsWith('--large-text') ? 'accessibility-stress'
  : /^(login|account|ai-settings)--/.test(id) || ['chat--busy', 'detail--missing'].includes(id) ? 'native-only' : 'shared';

function artifact(root, item, label) {
  const file = contained(root, item?.path);
  check(fs.statSync(file).isFile(), `${label}: original artifact must be a file`);
  const bytes = fs.readFileSync(file);
  check(bytes.length > 0 && /^[a-f0-9]{64}$/.test(item.sha256 ?? '') && hash(bytes) === item.sha256, `${label}: artifact bytes/hash mismatch`);
  return { file, bytes };
}
function jsonArtifact(root, item, label) { return JSON.parse(artifact(root, item, label).bytes); }
// ImageIO is part of macOS/Xcode, already required by native verification.
// Decode into memory only: preserve browser originals and their hashes unchanged.
const JPEG_DECODER = String.raw`
import Foundation
import ImageIO
import CoreGraphics
func reject(_ reason: String) -> Never {
    FileHandle.standardError.write(Data(reason.utf8)); exit(1)
}
guard let file = CommandLine.arguments.last,
      let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) as String? == "public.jpeg",
      CGImageSourceGetCount(source) == 1,
      CGImageSourceGetStatus(source) == .statusComplete,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, Double(width) * Double(height) <= 64000000 else {
    reject("JPEG source incomplete or invalid")
}
let options = [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
      image.width == width, image.height == height,
      CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    reject("JPEG pixel decode failed")
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard context.data != nil, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
    reject("JPEG pixel decode incomplete")
}
print("{\"width\":\(width),\"height\":\(height)}")
`;
const decodedJPEGs = new Map();
function jpegSize(root, file, bytes) {
  check(bytes.length >= 4 && bytes.length <= 64 * 1024 * 1024
    && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes.at(-2) === 0xff && bytes.at(-1) === 0xd9,
  'Web JPEG is truncated or has invalid framing');
  const digest = hash(bytes);
  if (decodedJPEGs.has(digest)) return decodedJPEGs.get(digest);
  check(process.platform === 'darwin', 'Complete Web JPEG validation requires the macOS ImageIO decoder');
  const cache = path.join(root, '.artifacts/ios/image-validation-cache');
  fs.mkdirSync(cache, { recursive: true });
  const result = spawnSync('/usr/bin/xcrun', ['swift', '-module-cache-path', cache, '-e', JPEG_DECODER, file], {
    encoding: 'utf8', timeout: 30000, maxBuffer: 16384, env: { ...process.env, TMPDIR: cache },
  });
  check(!result.error && result.status === 0 && result.stderr.trim() === '',
    `Web JPEG full pixel decode failed: ${result.error?.message ?? result.stderr.trim()}`);
  const size = JSON.parse(result.stdout);
  check(Number.isInteger(size.width) && Number.isInteger(size.height) && size.width > 0 && size.height > 0, 'Web JPEG decoded dimensions missing');
  decodedJPEGs.set(digest, size);
  return size;
}
export function validateOriginalImage(root, item, device, label, { web = false } = {}) {
  const { file, bytes } = artifact(root, item, label);
  const jpeg = web && bytes[0] === 0xff && bytes[1] === 0xd8;
  const size = jpeg ? jpegSize(root, file, bytes) : pngSize(file);
  const { width, height } = device?.viewport ?? {};
  check([width, height, device?.scale].every(v => Number.isFinite(v) && v > 0), `${label}: measured viewport/scale missing`);
  check(size.width === Math.round(width * device.scale) && size.height === Math.round(height * device.scale),
    `${label}: ${jpeg ? 'JPEG' : 'PNG'} dimensions disagree with device`);
}

function runReceipt(root, ref, provenance, suite) {
  const result = jsonArtifact(root, ref, `${suite} receipt`);
  const receipt = result.verificationReceipt;
  check(result.sourceHash === provenance.sourceHash && result.build?.sha256 === provenance.buildHash,
    `${suite}: run source/build stale`);
  check(receipt?.sourceHashBefore === provenance.sourceHash && receipt.sourceHashAfter === provenance.sourceHash
    && receipt.buildHash === provenance.buildHash && receipt.exitCode === 0, `${suite}: successful source-bound execution missing`);
  check(date(receipt.startedAt) && date(receipt.finishedAt) && Date.parse(receipt.startedAt) >= Date.parse(provenance.builtAt)
    && Date.parse(receipt.finishedAt) >= Date.parse(receipt.startedAt), `${suite}: execution dates invalid`);
  check(Array.isArray(receipt.command) && receipt.command.includes('test-without-building')
    && receipt.command.some(arg => arg === `-only-testing:MiloUITests/${suite}`), `${suite}: wrong test execution`);
  const log = artifact(root, receipt.log, `${suite} test log`).bytes.toString('utf8');
  check(/\*\* TEST SUCCEEDED \*\*/.test(log) && !/\b(?:BUILD|TEST) FAILED\b|\*\* TEST EXECUTE FAILED \*\*/.test(log), `${suite}: test output is not successful`);
  return receipt;
}
function withinRun(capturedAt, run, label) {
  check(date(capturedAt) && Date.parse(capturedAt) >= Date.parse(run.startedAt)
    && Date.parse(capturedAt) <= Date.parse(run.finishedAt), `${label}: capture outside recorded execution`);
}
function contract(ledger, row) {
  check(row?.required === true, 'original fixture remains required');
  check(row.route === row.id.split('--')[0] && row.state === row.id.split('--')[1], 'fixture route/state changed');
  check(row.textSize === (row.id.endsWith('--large-text') ? 'largest-accessibility' : 'default'), 'fixture text-size requirement changed');
  const minimum = overflowIds.has(row.id) || row.id.endsWith('--large-text') ? ['top', 'all-overflow-content', 'bottom'] : ['visible-state'];
  check(Array.isArray(row.checkpoints) && minimum.every(c => row.checkpoints.includes(c)), 'required continuous coverage removed');
  check(date(ledger.fixedTime) && text(ledger.fixtureVersion) && text(ledger.locale) && text(ledger.timezone), 'original fixture settings missing');
}

// Compare normalized coverage against unedited XCTest geometry attachments.
// Raw values are not a replacement for PNG review; both are bound below.
function geometry(root, shot, capture, region) {
  const raw = jsonArtifact(root, shot.geometry, 'original geometry');
  const r = raw.raw, f = raw.visibleFrame;
  check(raw.region === region && text(raw.probe), 'wrong original geometry region/probe');
  check(r && f && [r.contentHeight, r.contentWidth, r.offsetY, r.frameX, r.frameY, r.frameWidth, r.frameHeight,
    f.x, f.y, f.width, f.height].every(Number.isFinite), 'original raw geometry incomplete');
  check(f.width > 0 && f.height > 0 && f.x >= 0 && f.y >= 0
    && f.x + f.width <= capture.device.viewport.width + 1 && f.y + f.height <= capture.device.viewport.height + 1,
  'geometry leaves screenshot viewport');
  check(f.x >= r.frameX - 1 && f.y >= r.frameY - 1 && f.x + f.width <= r.frameX + r.frameWidth + 1
    && f.y + f.height <= r.frameY + r.frameHeight + 1, 'visible geometry exceeds raw scroll frame');
  check(r.contentWidth <= f.width + 1, 'horizontal content clipped');
  const topInset = Math.max(0, r.insetTop ?? 0);
  const offset = Math.max(0, r.offsetY + topInset + f.y - r.frameY - (r.isUIKitTextView === 1 ? topInset : 0));
  check(close(raw.scrollOffset, offset) && close(shot.scrollOffset, offset), 'normalized offset contradicts raw geometry');
  check(close(raw.totalContentHeight, r.contentHeight) && close(raw.viewportHeight, f.height)
    && close(raw.maxScrollOffset, Math.max(0, r.contentHeight - f.height)), 'raw scroll extent inconsistent');
  check(close(shot.visibleContentHeight, f.height) && close(capture.scrollGeometry?.totalContentHeight, r.contentHeight)
    && close(capture.scrollGeometry?.viewportHeight, f.height) && close(capture.scrollGeometry?.maxScrollOffset, raw.maxScrollOffset),
  'coverage metadata contradicts original geometry');
}
function nativeCapture(root, capture, row, fixture, provenance) {
  check(text(capture?.authoredBy), 'native capture author missing');
  const run = runReceipt(root, capture.runReceipt, provenance, 'ParityCaptureTests');
  withinRun(capture.capturedAt, run, row.id);
  const hashes = [];
  const regions = [{ ...capture, id: 'page' }, ...(capture.regions ?? []).map(r => ({ ...capture, ...r, regions: undefined }))];
  check(new Set(regions.map(r => r.id)).size === regions.length && regions.every(r => ['page', 'editor'].includes(r.id)), 'duplicate/unknown scroll region');
  if (row.id.startsWith('now-note--keyboard-long')) check(regions.some(r => r.id === 'editor'), 'nested editor coverage missing');
  for (const region of regions) {
    const required = region.scrollGeometry ? { ...row, checkpoints: ['top', 'all-overflow-content', 'bottom'] } : row;
    hashes.push(...validateCapture(region, 'ios', required, fixture, provenance, root, { fixtureItem: row }));
    for (const shot of region.images) {
      const tree = artifact(root, shot.accessibility, 'original accessibility tree').bytes.toString('utf8');
      const rootLine = tree.split('\n').find(line => /identifier: ['"]parity-root['"]/.test(line));
      const observed = rootLine?.match(/\bvalue:\s*['"]?(large|accessibility5)['"]?(?:,|\s|$)/)?.[1];
      check(observed === (row.textSize === 'default' ? 'large' : 'accessibility5'), 'original actual DynamicType observation missing or contradictory');
      if (shot.geometry) geometry(root, shot, region, region.id);
      else {
        check(!region.scrollGeometry, 'measured page omitted original geometry');
        const modal = row.id.includes('confirmation') && /Alert/.test(tree);
        check(modal || !/ScrollView/.test(tree), 'scrollable page lacks original measured coverage');
      }
    }

  }
  return hashes;
}

function webProvenance(root, capture, expectedURL, viewport) {
  check(capture?.url === expectedURL && date(capture.capturedAt) && text(capture.authoredBy), 'actual external Web capture missing');
  check(same(capture.device?.viewport, viewport), 'Web viewport differs from agreed reference');
  const record = jsonArtifact(root, capture.provenance, 'browser provenance');
  check(record.url === capture.url && record.capturedAt === capture.capturedAt && record.authoredBy === capture.authoredBy
    && same(record.device, capture.device) && text(record.browser?.name) && text(record.browser?.version), 'browser provenance identity/viewport/time differs');
  check(Array.isArray(record.actions) && record.actions.some(a => a.type === 'navigate' && a.url === expectedURL)
    && record.actions.every(a => text(a.type) && date(a.at) && Date.parse(a.at) <= Date.parse(capture.capturedAt)), 'actual dated browser action trace missing');
  return record;
}
function webCapture(root, capture, id, ledger) {
  check(capture?.caseId === id, 'Web capture belongs to another state');
  const record = webProvenance(root, capture, ledger.referenceURL, ledger.viewport);
  const sourceCaseId = capture.sourceCaseId ?? id;
  check(sourceCaseId === id || (id === 'detail--delete-confirmation' && ['detail--now', 'detail--past'].includes(sourceCaseId)),
    'unreviewed Web source-state substitution');
  check(same(record.fixtureDifferences ?? [], capture.fixtureDifferences ?? []), 'browser fixture-difference observation changed');
  check(Array.isArray(capture.images) && capture.images.length > 0, 'Web original screenshots missing');
  check(new Set(capture.images.map(s => s.sha256)).size === capture.images.length, 'Web continuous coverage reuses identical images');
  for (const shot of capture.images) {
    validateOriginalImage(root, shot, capture.device, 'Web screenshot', { web: true });
    check(record.actions.some(a => a.type === 'screenshot' && a.sha256 === shot.sha256 && a.caseId === sourceCaseId), 'Web screenshot not bound to browser observation');
  }
  let previous;
  for (const shot of capture.images) {
    const g = jsonArtifact(root, shot.geometry, 'original browser geometry');
    check([g.scrollTop, g.scrollHeight, g.clientHeight].every(Number.isFinite)
      && g.clientHeight > 0 && g.clientHeight <= capture.device.viewport.height && g.scrollHeight >= g.clientHeight,
    'browser scroll measurements missing');
    check(close(shot.scrollOffset, g.scrollTop) && close(shot.visibleContentHeight, g.clientHeight), 'browser capture/geometry disagree');
    if (!previous) check(g.scrollTop <= 1, 'browser coverage does not start at top');
    else check(close(g.scrollHeight, previous.scrollHeight) && close(g.clientHeight, previous.clientHeight)
      && g.scrollTop > previous.scrollTop && g.scrollTop - previous.scrollTop <= previous.clientHeight * 0.9 + 1,
    'browser coverage is discontinuous');
    previous = g;
  }
  check(close(previous.scrollTop, Math.max(0, previous.scrollHeight - previous.clientHeight)), 'browser coverage does not reach bottom');
  return capture.images.map(s => s.sha256);
}
function review(root, refs, binding, authors, earliest, requiredCriteria) {
  const item = jsonArtifact(root, refs?.artifact, 'independent review');
  const author = jsonArtifact(root, refs.authorRecord, 'review author record');
  check(text(item.authorId) && !authors.includes(item.authorId) && author.authorId === item.authorId
    && author.role === 'independent-reviewer' && author.reviewArtifactSha256 === refs.artifact.sha256,
  'review independence/author record missing or self-authored');
  check(item.verdict === 'pass' && same(item.bindings, binding), 'review verdict/bound metadata stale');
  check(date(item.reviewedAt) && Date.parse(item.reviewedAt) >= earliest, 'review predates inspected evidence');
  for (const name of requiredCriteria) check(item.criteria?.[name]?.verdict === 'pass' && text(item.criteria[name].notes), `review: ${name} lacks a concrete judgment`);
  check(Array.isArray(item.findings) && item.findings.every(f => ['resolved', 'accepted-deviation'].includes(f.status) && text(f.notes)), 'review has unresolved findings');
  return item;
}
export function caseBindings(row, fixtureRow, fixture) {
  return { caseId: row.id, category: row.category, fixtureHash: fixtureHash(fixture, fixtureRow),
    ios: metadataHash(row.ios), web: row.web ? metadataHash(row.web) : null };
}
function motionCapture(root, capture, provenance, run, name, platform, ledger) {
  check(text(capture?.authoredBy) && Array.isArray(capture.frames) && capture.frames.length >= (name === 'natural' ? 3 : 2), `${platform} ${name}: temporal sequence missing`);
  const web = platform === 'web' ? webProvenance(root, capture, ledger.referenceURL, ledger.viewport) : null;
  const clocks = [];
  for (const [index, frame] of capture.frames.entries()) {
    validateOriginalImage(root, frame, capture.device, `${platform} ${name} frame`, { web: platform === 'web' });
    check(date(frame.capturedAt) && (index === 0 || Date.parse(frame.capturedAt) > Date.parse(capture.frames[index - 1].capturedAt)), 'temporal frame dates missing/unordered');
    if (platform === 'ios') {
      withinRun(frame.capturedAt, run, name);
      const clock = jsonArtifact(root, frame.clock, 'original native animation clock');
      check(Number.isFinite(clock.time) && clock.renderReady === 1, 'motion renderer/clock missing');
      clocks.push(clock);
    } else check(web.actions.some(a => a.type === 'screenshot' && a.sha256 === frame.sha256 && a.criterion === name), 'Web motion frame not bound to browser observation');
  }
  if (name === 'natural') {
    check(new Set(capture.frames.map(f => f.sha256)).size >= 3, 'natural motion repeats static images');
    if (platform === 'ios') check(clocks.at(-1).time - clocks[0].time >= 1, 'native motion clock did not advance');
  }
  if (platform === 'ios' && name === 'reduceMotion') check(clocks.every(c => c.time === clocks[0].time && c.active === 0), 'reduced motion remains active');
  if (platform === 'ios' && name === 'inactiveResume') check(clocks.at(-1).inactiveDuration > (clocks[0].inactiveDuration ?? 0), 'inactive pause not observed');
}
export function validateWebEvidence({ root, ledger, fixture, iosManifest, motion }) {
  const errors = [], rows = [];
  const attempt = (label, fn) => { try { return fn(); } catch (e) { errors.push(`${label}: ${e.message}`); } };
  const provenance = attempt('iOS build', () => checkProvenance(iosManifest, root, 'ios'));
  attempt('manifest', () => {
    check(ledger?.version === 2 && ledger.referenceURL === REFERENCE_URL, 'Web evidence version/reference mismatch');
    check(same(ledger.viewport, { width: 390, height: 844 }), 'agreed Web reference viewport changed');
    check(Array.isArray(ledger.implementationAuthors) && ledger.implementationAuthors.length > 0 && ledger.implementationAuthors.every(text), 'implementation author identities missing');
    for (const list of [ledger.cases, fixture?.cases]) {
      check(Array.isArray(list) && list.length === REQUIRED_CASE_IDS.length && new Set(list.map(r => r.id)).size === REQUIRED_CASE_IDS.length
        && REQUIRED_CASE_IDS.every(id => list.some(r => r.id === id)), 'exact 53 required states missing/duplicated');
    }
  });
  const originals = new Map();
  for (const row of Array.isArray(ledger?.cases) ? ledger.cases : []) {
    const before = errors.length;
    attempt(row.id, () => {
      const fixtureRow = fixture.cases.find(r => r.id === row.id);
      contract(fixture, fixtureRow);
      check(row.category === expectedCategory(row.id), 'required case category changed');
      check(row.status === 'passed', 'case is not accepted');
      const hashes = { ios: nativeCapture(root, row.ios, fixtureRow, fixture, provenance) };
      if (row.category === 'shared') hashes.web = webCapture(root, row.web, row.id, ledger);
      else check(row.web == null, 'native/accessibility case must not claim fictitious Web equivalence');
      const authors = [...ledger.implementationAuthors, row.ios.authoredBy, row.web?.authoredBy].filter(Boolean);
      const inspected = review(root, row.review, caseBindings(row, fixtureRow, fixture), authors,
        Math.max(Date.parse(row.ios.capturedAt), row.web ? Date.parse(row.web.capturedAt) : 0),
        ['fidelity', 'readability', 'actions', 'polish']);
      if (row.web?.sourceCaseId && row.web.sourceCaseId !== row.id) {
        for (const sha256 of hashes.web) check(inspected.findings.some(f => f.status === 'accepted-deviation'
          && f.sourceCaseId === row.web.sourceCaseId && f.sourcePlatform === 'web' && f.platform === 'web'
          && f.sha256 === sha256 && text(f.sourceAction)), 'Web reference affordance needs an explicit image-bound source-action deviation');
      }
      for (const difference of row.web?.fixtureDifferences ?? []) {
        check(text(difference.field) && text(difference.webValue) && text(difference.iosValue), 'Web fixture difference incomplete');
        check(inspected.findings.some(f => f.status === 'accepted-deviation' && f.kind === 'fixture-difference'
          && f.field === difference.field && f.webValue === difference.webValue && f.iosValue === difference.iosValue
          && same(f.imageHashes, hashes.web)), 'actual Web fixture/date difference requires image-bound review');
      }
      for (const [platform, list] of Object.entries(hashes)) for (const sha256 of list) {
        const old = originals.get(sha256);
        if (old) check(inspected.findings.some(f => f.status === 'accepted-deviation' && f.sha256 === sha256
          && f.sourceCaseId === old.caseId && f.sourcePlatform === old.platform && f.platform === platform && text(f.sourceAction)), 'reused original needs explicit source-action review');
        else originals.set(sha256, { caseId: row.id, platform });
      }
    });
    rows.push({ id: row.id, passed: before === errors.length });
  }
  attempt('motion', () => {
    check(motion?.version === 2 && motion.sourceHash === provenance?.sourceHash && motion.buildHash === provenance?.buildHash, 'motion source/build stale or missing');
    const run = runReceipt(root, motion.runReceipt, provenance, 'GalaxyMotionTests');
    check(same(Object.keys(motion.criteria ?? {}).sort(), [...MOTION_CRITERIA].sort()), 'all seven temporal criteria required');
    const authors = [...ledger.implementationAuthors];
    let latest = 0;
    for (const name of MOTION_CRITERIA) {
      const criterion = motion.criteria[name];
      for (const platform of ['ios', ...(MOTION_CRITERIA.indexOf(name) < 5 ? ['web'] : [])]) {
        const capture = criterion[platform];
        motionCapture(root, capture, provenance, run, name, platform, ledger);
        authors.push(capture.authoredBy);
        latest = Math.max(latest, capture.capturedAt ? Date.parse(capture.capturedAt) : 0,
          ...capture.frames.map(f => Date.parse(f.capturedAt)));
      }
    }
    const { review: refs, ...evidence } = motion;
    review(root, refs, { motion: metadataHash(evidence) }, authors, latest, MOTION_CRITERIA);
  });
  return { version: 2, passed: errors.length === 0, requiredMinimum: 53, total: rows.length,
    passedCases: rows.filter(r => r.passed).length, cases: rows, errors };
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
  try {
    const result = validateWebEvidence({ root, ledger: read(path.join(root, 'docs/visual-parity/web-cases.json')),
      fixture: read(path.join(root, 'docs/visual-parity/cases.json')), iosManifest: read(path.join(root, 'docs/visual-parity/ios-source-build.json')),
      motion: read(path.join(root, 'docs/visual-parity/web-native-motion-review.json')) });
    console.log(JSON.stringify(result, null, 2));
    if (!result.passed) process.exitCode = 78;
  } catch (error) { console.error(`BLOCKED: ${error.message}`); process.exitCode = 78; }
}
