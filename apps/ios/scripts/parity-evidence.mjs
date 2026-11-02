#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath, pathToFileURL } from 'node:url';

const script = fileURLToPath(import.meta.url);
const project = path.resolve(path.dirname(script), '../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const hashPattern = /^[a-f0-9]{64}$/;
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
};
export const metadataHash = value => sha(JSON.stringify(canonical(value)));
export const captureMetadataHash = capture => metadataHash(capture);
export function fixtureHash(ledger, item) {
  const omit = (value, keys) => Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key)));
  return metadataHash({ fixture: omit(ledger, ['cases', 'referenceManifest', 'captureContract']), case: omit(item, ['harmony', 'ios', 'review', 'status']) });
}
const ignored = new Set(['.build', '.swiftpm', 'xcuserdata', 'DerivedData', 'build', 'node_modules', '.DS_Store']);
export const SOURCE_ALGORITHM = 'sha256(JSON.stringify(sorted relative-path -> sha256(file bytes) map)); UTF-8; slash paths';
export const IOS_INPUTS = ['App', 'MiloCore', 'UITests', 'Resources', 'project.yml', 'Milo.xcodeproj', 'scripts', 'tests'];
// This reviewed minimum is separate from the mutable evidence ledger. Removing a
// required row cannot turn incomplete capture into a passing result.
export const REQUIRED_CASE_IDS = [
  'login--email', 'login--password', 'login--code', 'login--reset', 'login--error',
  'home--mood-calm', 'home--mood-joyful', 'home--mood-low', 'home--words-empty', 'home--words-three',
  'classify--default', 'now-note--empty', 'now-note--written', 'now-note--keyboard-long',
  'past-time--empty', 'past-time--preset', 'past-time--custom',
  'chat--opening', 'chat--conversation', 'chat--offline', 'chat--keyboard', 'chat--busy',
  'diary--enabled', 'diary--disabled', 'diary--editing', 'diary--long',
  'timeline--empty', 'timeline--populated', 'detail--now', 'detail--past',
  'detail--transcript-expanded', 'detail--missing', 'detail--delete-confirmation',
  'card--planet-letter', 'card--orbit-theatre', 'account--local', 'account--remote',
  'account--password-form', 'account--export', 'account--delete-confirmation',
  'ai-settings--hosted', 'ai-settings--personal', 'ai-settings--missing-config',
  'ai-settings--consent', 'ai-settings--connection-error',
  'home--words-three--large-text', 'now-note--keyboard-long--large-text',
  'chat--conversation--large-text', 'diary--long--large-text', 'timeline--populated--large-text',
  'detail--transcript-expanded--large-text', 'account--local--large-text', 'ai-settings--personal--large-text',
];
const overflowIds = new Set(['now-note--keyboard-long', 'chat--conversation', 'chat--keyboard', 'diary--long',
  'detail--past', 'detail--transcript-expanded', 'account--local', 'account--remote',
  'account--password-form', 'account--export', 'ai-settings--hosted', 'ai-settings--personal']);

function contained(root, relative) {
  assert(nonempty(relative) && !path.isAbsolute(relative), 'Artifact path must be relative');
  const base = fs.realpathSync(root);
  const absolute = path.resolve(base, relative);
  assert(absolute.startsWith(base + path.sep), 'Artifact path escapes its root');
  const real = fs.realpathSync(absolute);
  assert(real.startsWith(base + path.sep), 'Artifact symlink escapes its root');
  return real;
}

export function fingerprint(root, inputs, { ignoreGenerated = true } = {}) {
  const base = fs.realpathSync(root);
  const files = {};
  const visit = relative => {
    const absolute = path.join(base, relative);
    assert(!fs.lstatSync(absolute).isSymbolicLink(), `Source/build symlinks are unsupported: ${relative}`);
    if (fs.statSync(absolute).isDirectory()) {
      for (const name of fs.readdirSync(absolute).sort()) if (!ignoreGenerated || !ignored.has(name)) visit(path.join(relative, name));
    } else {
      assert(fs.statSync(absolute).isFile(), `Not a regular file: ${relative}`);
      files[relative.split(path.sep).join('/')] = sha(fs.readFileSync(absolute));
    }
  };
  for (const input of inputs) visit(input);
  const sorted = Object.fromEntries(Object.entries(files).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
  return { version: 1, algorithm: SOURCE_ALGORITHM, sourceHash: sha(JSON.stringify(sorted)), files: sorted };
}

export function hashIOSSource(root = project) {
  return fingerprint(root, IOS_INPUTS.map(input => `apps/ios/${input}`));
}

export function hashBuild(root, relative) {
  const target = contained(root, relative);
  if (fs.statSync(target).isFile()) return sha(fs.readFileSync(target));
  assert(fs.statSync(target).isDirectory(), 'Build must be a file or directory');
  // Bundle paths are relative to the bundle itself, so a relocated unchanged app
  // retains its build identity. All files, including resources, are fingerprinted.
  const names = fs.readdirSync(target).sort();
  return fingerprint(target, names, { ignoreGenerated: false }).sourceHash;
}

function checkProvenance(manifest, root, platform) {
  assert(manifest?.version === 1 && hashPattern.test(manifest.sourceHash ?? ''), `${platform}: source provenance missing`);
  const current = platform === 'ios' ? hashIOSSource(root) : fingerprint(root, ['apps/harmony/entry/src/main', 'apps/harmony/AppScope']);
  assert(manifest.sourceHash === current.sourceHash, `${platform}: stale source hash`);
  if (platform === 'harmony') assert(JSON.stringify(manifest.files) === JSON.stringify(current.files), 'harmony: source file manifest is incomplete or stale');
  assert(hashPattern.test(manifest.build?.sha256 ?? ''), `${platform}: build hash missing`);
  assert(hashBuild(root, manifest.build.path) === manifest.build.sha256, `${platform}: build bytes changed`);
  const receipt = manifest.buildReceipt;
  assert(receipt && receipt.sourceHashBefore === current.sourceHash && receipt.sourceHashAfter === current.sourceHash, `${platform}: build receipt is missing or belongs to different source`);
  assert(receipt.buildHash === manifest.build.sha256 && receipt.exitCode === 0, `${platform}: build receipt result/hash mismatch`);
  assert(nonempty(receipt.command) || (Array.isArray(receipt.command) && receipt.command.length > 0 && receipt.command.every(nonempty)), `${platform}: build command missing`);
  const started = Date.parse(receipt.startedAt), finished = Date.parse(receipt.finishedAt);
  assert(Number.isFinite(started) && Number.isFinite(finished) && started <= finished, `${platform}: build receipt timestamps invalid`);
  const log = contained(root, receipt.log?.path);
  assert(fs.statSync(log).isFile(), `${platform}: build log must be a file`);
  const bytes = fs.readFileSync(log);
  assert(bytes.length > 0 && hashPattern.test(receipt.log.sha256 ?? '') && sha(bytes) === receipt.log.sha256, `${platform}: build log missing or changed`);
  const text = bytes.toString('utf8');
  const success = platform === 'ios' ? /\*\* (?:TEST BUILD|BUILD|TEST) SUCCEEDED \*\*/ : /\bBUILD SUCCESSFUL\b/;
  assert(success.test(text) && !/\b(?:BUILD|TEST) FAILED\b/.test(text), `${platform}: build log lacks successful native build output`);
  return { sourceHash: current.sourceHash, buildHash: manifest.build.sha256, builtAt: receipt.finishedAt };
}

const crcTable = Uint32Array.from({ length: 256 }, (_, initial) => {
  let value = initial;
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  return value >>> 0;
});
function crc32(bytes) {
  let value = 0xffffffff;
  for (let index = 0; index < bytes.length; index++) value = (value >>> 8) ^ crcTable[(value ^ bytes[index]) & 0xff];
  return (value ^ 0xffffffff) >>> 0;
}

function pngSize(file) {
  const bytes = fs.readFileSync(file);
  assert(bytes.length >= 57 && bytes.length <= 64 * 1024 * 1024 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), 'Capture must be a complete PNG');
  let offset = 8, header, ended = false, sawData = false, dataEnded = false, palette = false;
  const compressed = [];
  while (offset < bytes.length) {
    assert(offset + 12 <= bytes.length, 'PNG chunk is truncated');
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    assert(/^[A-Za-z]{4}$/.test(type) && offset + 12 + length <= bytes.length, 'PNG chunk length/type invalid');
    const body = bytes.subarray(offset + 8, offset + 8 + length);
    assert(crc32(bytes.subarray(offset + 4, offset + 8 + length)) === bytes.readUInt32BE(offset + 8 + length), 'PNG chunk CRC mismatch');
    if (!header) assert(type === 'IHDR' && length === 13, 'PNG IHDR must be first');
    if (type === 'IHDR') { assert(!header, 'PNG has duplicate IHDR'); header = body; }
    else if (type === 'PLTE') { assert(!palette && !sawData && length > 0 && length <= 768 && length % 3 === 0, 'PNG palette invalid'); palette = true; }
    else if (type === 'IDAT') { assert(!dataEnded, 'PNG IDAT chunks must be consecutive'); sawData = true; compressed.push(body); }
    else if (type === 'IEND') { assert(length === 0 && sawData, 'PNG IEND/data invalid'); ended = true; }
    else { assert(type[0] === type[0].toLowerCase(), `Unsupported PNG critical chunk ${type}`); }
    if (sawData && type !== 'IDAT') dataEnded = true;
    offset += length + 12;
    if (ended) break;
  }
  assert(ended && offset === bytes.length, 'PNG IEND is missing or trailing bytes exist');
  const width = header.readUInt32BE(0), height = header.readUInt32BE(4), depth = header[8], color = header[9], interlace = header[12];
  const depths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
  assert(width > 0 && height > 0 && width * height <= 64_000_000 && depths[color]?.includes(depth) && header[10] === 0 && header[11] === 0 && [0, 1].includes(interlace), 'PNG image format invalid or too large');
  assert(color !== 3 || palette, 'Indexed PNG needs a palette');
  const pixels = zlib.inflateSync(Buffer.concat(compressed), { maxOutputLength: 256 * 1024 * 1024 });
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[color];
  const passes = interlace ? [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]] : [[0, 0, 1, 1]];
  let cursor = 0;
  for (const [x, y, dx, dy] of passes) {
    const columns = Math.max(0, Math.ceil((width - x) / dx)), rows = Math.max(0, Math.ceil((height - y) / dy));
    if (!columns || !rows) continue;
    const rowBytes = Math.ceil(columns * channels * depth / 8);
    for (let row = 0; row < rows; row++) { assert(cursor + 1 + rowBytes <= pixels.length && pixels[cursor] <= 4, 'PNG scanline data is invalid'); cursor += 1 + rowBytes; }
  }
  assert(cursor === pixels.length, 'PNG decompressed size mismatch');
  return { width, height };
}

function validateTextSetting(setting, platform, required) {
  assert(setting && typeof setting === 'object' && !Array.isArray(setting), `${platform}: actual setting must record a structured category or scale`);
  if (platform === 'ios') {
    const categories = { large: 'large', UICTContentSizeCategoryL: 'large', accessibility5: 'accessibility5', UICTContentSizeCategoryAccessibilityXXXL: 'accessibility5' };
    const expected = required === 'largest-accessibility' ? 'accessibility5' : 'large';
    assert(categories[setting.category] === expected, `${platform}: actual text category contradicts required ${required}`);
  } else {
    const { scale, defaultScale, maxSupportedScale } = setting;
    assert([scale, defaultScale, maxSupportedScale].every(Number.isFinite) && defaultScale > 0 && maxSupportedScale > defaultScale && scale > 0, `${platform}: actual/default/maximum text scales are required`);
    const expected = required === 'largest-accessibility' ? maxSupportedScale : defaultScale;
    assert(Math.abs(scale - expected) <= 0.000001, `${platform}: actual text scale contradicts required ${required}`);
  }
}

function validateCapture(capture, name, item, ledger, provenance, evidenceRoot, { fixtureItem = item } = {}) {
  assert(capture && provenance, `${name}: capture/provenance missing`);
  assert(capture.caseId === item.id, `${name}: capture belongs to another case`);
  assert(capture.sourceHash === provenance.sourceHash && capture.buildHash === provenance.buildHash, `${name}: capture source/build is stale`);
  assert(capture.fixtureVersion === ledger.fixtureVersion, `${name}: fixture version mismatch`);
  assert(capture.fixtureHash === fixtureHash(ledger, fixtureItem), `${name}: fixture data hash mismatch`);
  assert(capture.fixedTime === ledger.fixedTime && capture.locale === ledger.locale && capture.timezone === ledger.timezone, `${name}: fixture time/locale/timezone mismatch`);
  assert(capture.textSize === item.textSize, `${name}: text size mismatch`);
  validateTextSetting(capture.actualTextSetting, name, item.textSize);
  assert(Number.isFinite(Date.parse(capture.capturedAt)), `${name}: capture time missing`);
  assert(Date.parse(capture.capturedAt) >= Date.parse(provenance.builtAt), `${name}: capture predates this build`);
  const device = capture.device;
  assert(nonempty(device?.name) && nonempty(device.osVersion), `${name}: device identity missing`);
  const { width, height } = device.viewport ?? {};
  assert(width > 0 && height > 0 && Number.isFinite(width) && Number.isFinite(height) && device.scale > 0 && Number.isFinite(device.scale), `${name}: viewport/scale missing`);
  assert(Array.isArray(capture.images) && capture.images.length > 0, `${name}: images missing`);
  const scroll = capture.scrollGeometry;
  const needsCoverage = item.checkpoints.includes('all-overflow-content');
  if (needsCoverage) {
    assert(scroll && [scroll.totalContentHeight, scroll.viewportHeight, scroll.maxScrollOffset].every(Number.isFinite) && scroll.totalContentHeight > 0 && scroll.viewportHeight > 0 && scroll.viewportHeight <= height && scroll.maxScrollOffset >= 0 && nonempty(scroll.lastAnchor), `${name}: measured scroll geometry/last anchor missing`);
    assert(Math.abs(scroll.maxScrollOffset - Math.max(0, scroll.totalContentHeight - scroll.viewportHeight)) <= 1, `${name}: max scroll offset disagrees with measured content extent`);
  }
  const fitsOneScreen = needsCoverage && scroll.maxScrollOffset === 0 && scroll.totalContentHeight <= scroll.viewportHeight;
  const paths = new Set();
  const hashes = new Set();
  for (const image of capture.images) {
    assert(item.checkpoints.includes(image.checkpoint) || (fitsOneScreen && image.checkpoint === 'full-content'), `${name}: unknown checkpoint ${image.checkpoint}`);
    assert(nonempty(image.contentAnchor) && Number.isFinite(image.scrollOffset) && image.scrollOffset >= 0, `${name}: capture anchor/offset missing`);
    const file = contained(evidenceRoot, image.path);
    assert(!paths.has(file), `${name}: repeated original path`); paths.add(file);
    assert(hashPattern.test(image.sha256 ?? '') && sha(fs.readFileSync(file)) === image.sha256, `${name}: image hash changed`);
    assert(!hashes.has(image.sha256), `${name}: duplicate screenshot bytes do not prove different checkpoints`); hashes.add(image.sha256);
    const size = pngSize(file);
    assert(size.width === Math.round(width * device.scale) && size.height === Math.round(height * device.scale), `${name}: PNG dimensions disagree with recorded device`);
  }
  if (fitsOneScreen) {
    const image = capture.images[0];
    assert(capture.images.length === 1 && image.checkpoint === 'full-content' && image.scrollOffset === 0 && image.contentAnchor === scroll.lastAnchor && image.visibleContentHeight === scroll.viewportHeight, `${name}: one-screen coverage needs one full-content image with the measured final anchor`);
    assert(Array.isArray(image.coversCheckpoints) && item.checkpoints.every(checkpoint => image.coversCheckpoints.includes(checkpoint)), `${name}: full-content image must explicitly cover every checkpoint`);
  } else for (const checkpoint of item.checkpoints) assert(capture.images.some(image => image.checkpoint === checkpoint), `${name}: missing checkpoint ${checkpoint}`);
  if (needsCoverage && !fitsOneScreen) {
    assert(capture.images[0].checkpoint === 'top' && capture.images[0].scrollOffset === 0 && capture.images.at(-1).checkpoint === 'bottom', `${name}: overflow capture must run from top to bottom`);
    assert(Math.abs(capture.images.at(-1).scrollOffset - scroll.maxScrollOffset) <= 1 && capture.images.at(-1).contentAnchor === scroll.lastAnchor, `${name}: bottom image does not reach the measured end/last anchor`);
    const anchors = new Set();
    for (let index = 0; index < capture.images.length; index++) {
      const image = capture.images[index];
      assert(!anchors.has(image.contentAnchor), `${name}: overflow anchors must identify successive content`); anchors.add(image.contentAnchor);
      assert(Number.isFinite(image.visibleContentHeight) && image.visibleContentHeight > 0 && image.visibleContentHeight <= height, `${name}: visible content height missing`);
      assert(image.scrollOffset <= scroll.maxScrollOffset + 1 && Math.abs(image.visibleContentHeight - scroll.viewportHeight) <= 1, `${name}: image geometry disagrees with measured scroll viewport`);
      if (index > 0 && index < capture.images.length - 1) assert(image.checkpoint === 'all-overflow-content', `${name}: intermediate image must show overflow content`);
      if (index > 0) {
        const previous = capture.images[index - 1];
        const distance = image.scrollOffset - previous.scrollOffset;
        assert(distance > 0 && distance <= previous.visibleContentHeight * 0.9, `${name}: overflow order/gap lacks at least 10% overlap`);
      }
    }
  }
  return capture.images.map(image => image.sha256);
}

function validateReview(item, imageHashes) {
  const review = item.review;
  assert(review?.verdict === 'pass' && nonempty(review.reviewer) && Number.isFinite(Date.parse(review.reviewedAt)), 'independent review missing or not pass');
  assert(review.caseId === item.id && review.fixtureHash === item.harmony.fixtureHash, 'review: case/fixture binding mismatch');
  assert(Date.parse(review.reviewedAt) >= Math.max(Date.parse(item.harmony.capturedAt), Date.parse(item.ios.capturedAt)), 'review predates the captures');
  for (const name of ['harmony', 'ios']) {
    assert(review.sourceHashes?.[name] === item[name].sourceHash, `review: ${name} source is stale`);
    assert(review.buildHashes?.[name] === item[name].buildHash, `review: ${name} build is stale`);
    assert(review.captureHashes?.[name] === captureMetadataHash(item[name]), `review: ${name} capture metadata changed`);
    assert(JSON.stringify(review.imageHashes?.[name]) === JSON.stringify(imageHashes[name]), `review: ${name} reviewed images differ`);
  }
  for (const criterion of ['fidelity', 'readability', 'actions', 'polish']) assert(review[criterion]?.verdict === 'pass' && nonempty(review[criterion].notes), `review: ${criterion} needs a pass and concrete notes`);
  assert(Array.isArray(review.findings), 'review findings must be explicit');
  for (const finding of review.findings) assert(['resolved', 'accepted-deviation'].includes(finding.status) && nonempty(finding.notes), 'review has unresolved findings');
}

/** Structural evidence verification never invents an independent visual verdict. */
export function validateEvidence({ ledger, harmonyManifest, iosManifest, harmonyRoot, iosRoot, evidenceRoot }) {
  const errors = [];
  const rows = [];
  const attempt = (label, action) => { try { return action(); } catch (error) { errors.push(`${label}: ${error.message}`); return undefined; } };
  attempt('manifest', () => {
    assert(ledger?.version === 1 && nonempty(ledger.fixtureVersion) && Number.isFinite(Date.parse(ledger.fixedTime)) && nonempty(ledger.locale) && nonempty(ledger.timezone), 'fixture manifest missing');
    assert(Array.isArray(ledger.cases), 'cases missing');
    const ids = ledger.cases.map(item => item.id);
    assert(new Set(ids).size === ids.length, 'duplicate case IDs');
    for (const id of REQUIRED_CASE_IDS) assert(ids.includes(id), `missing required case ${id}`);
  });
  const provenance = {
    harmony: attempt('provenance', () => checkProvenance(harmonyManifest, harmonyRoot, 'harmony')),
    ios: attempt('provenance', () => checkProvenance(iosManifest, iosRoot, 'ios')),
  };
  const originals = new Map();
  for (const item of Array.isArray(ledger?.cases) ? ledger.cases : []) {
    const before = errors.length;
    attempt(item.id ?? 'unnamed case', () => {
      assert(item.required === true, 'case cannot be removed from required coverage');
      const [route, state] = item.id.split('--');
      assert(item.route === route && item.state === state, 'case route/state changed');
      const expectedSize = item.id.endsWith('--large-text') ? 'largest-accessibility' : 'default';
      assert(item.textSize === expectedSize, 'reviewed text-size requirement changed');
      assert(Array.isArray(item.checkpoints) && item.checkpoints.length > 0 && new Set(item.checkpoints).size === item.checkpoints.length, 'checkpoints missing or duplicated');
      if (overflowIds.has(item.id) || expectedSize === 'largest-accessibility') for (const checkpoint of ['top', 'all-overflow-content', 'bottom']) assert(item.checkpoints.includes(checkpoint), `reviewed checkpoint removed: ${checkpoint}`);
      else assert(item.checkpoints.includes('visible-state'), 'reviewed checkpoint removed: visible-state');
      const imageHashes = {};
      for (const name of ['harmony', 'ios']) imageHashes[name] = validateCapture(item[name], name, item, ledger, provenance[name], evidenceRoot);
      validateReview(item, imageHashes);
      for (const name of ['harmony', 'ios']) for (const image of item[name].images) {
        const previous = originals.get(image.sha256);
        if (previous) assert(item.review.findings.some(finding => finding.status === 'accepted-deviation' && finding.sourceCaseId === previous.caseId && finding.sourcePlatform === previous.platform && finding.platform === name && finding.sha256 === image.sha256 && nonempty(finding.sourceAction) && nonempty(finding.notes)), 'cross-case/platform duplicate image needs an explicit source-action accepted-deviation review');
        else originals.set(image.sha256, { caseId: item.id, platform: name });
      }
    });
    rows.push({ id: item.id, passed: errors.length === before, errors: errors.slice(before) });
  }
  return { version: 1, passed: errors.length === 0, total: rows.length, passedCases: rows.filter(row => row.passed).length, requiredMinimum: REQUIRED_CASE_IDS.length, errors, cases: rows };
}

const escape = text => String(text ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const routeNames = { login: '登录', home: '心情星球', classify: '此刻或过去', 'now-note': '记下此刻', 'past-time': '回忆时间', chat: '回忆对话', diary: '日记', timeline: '回忆长廊', detail: '回忆详情', card: '回忆卡片', account: '我的账户', 'ai-settings': 'AI 设置' };
const stateNames = { email: '邮箱输入', password: '密码登录', code: '验证码', reset: '重置密码', error: '错误提示', 'mood-calm': '平静心情', 'mood-joyful': '雀跃心情', 'mood-low': '低落心情', 'words-empty': '未选描述词', 'words-three': '已选三个描述词', default: '默认界面', empty: '空白状态', written: '已写记录', 'keyboard-long': '长文与键盘', preset: '预设时间', custom: '自定义时间', opening: '开始对话', conversation: '对话内容', offline: '离线引导', keyboard: '键盘展开', busy: '回复等待', enabled: '开启日记', disabled: '关闭日记', editing: '编辑日记', long: '长篇内容', populated: '已有回忆', now: '此刻记录', past: '过去回忆', 'transcript-expanded': '展开对话', missing: '记录不存在', 'delete-confirmation': '删除确认', 'planet-letter': '星球来信', 'orbit-theatre': '轨道剧场', local: '本地账户', remote: '邮箱账户', 'password-form': '修改密码', export: '导出数据', hosted: 'MILO 默认模型', personal: '自己的模型', 'missing-config': '缺少配置', consent: '发送前确认', 'connection-error': '连接错误' };
const checkpointName = value => ({ top: '页首', bottom: '页尾', 'all-overflow-content': '连续滚动内容', 'visible-state': '当前画面', 'full-content': '一屏完整内容' })[value] ?? value;
const textSettingLabel = setting => {
  if (!setting || typeof setting !== 'object') return '未记录结构化实际字号';
  if (setting.category) return ['accessibility5', 'UICTContentSizeCategoryAccessibilityXXXL'].includes(setting.category) ? `最大辅助字号 · ${setting.category}` : `系统字号 · ${setting.category}`;
  return `实际 ${setting.scale} 倍 · 默认 ${setting.defaultScale} 倍 · 平台最大 ${setting.maxSupportedScale} 倍`;
};
export function renderReport({ ledger, result, evidenceRoot, output }) {
  const imageBlock = (capture, platform) => {
    if (!capture) return '<p class="pending">待采集原图</p>';
    const images = (capture.images ?? []).map(image => {
      try {
        const file = contained(evidenceRoot, image.path);
        const href = path.relative(path.dirname(output), file).split(path.sep).map(encodeURIComponent).join('/');
        return `<figure><a href="${escape(href)}"><img loading="lazy" src="${escape(href)}" alt="${escape(platform + ' · ' + checkpointName(image.checkpoint))}"></a><figcaption>${escape(checkpointName(image.checkpoint))} · 位置 ${escape(image.scrollOffset)}<br>${escape(image.contentAnchor)}<br><a href="${escape(href)}">打开原图</a></figcaption></figure>`;
      } catch { return `<p class="pending">原图不可用：${escape(image.path)}</p>`; }
    }).join('');
    const scroll = capture.scrollGeometry;
    return `<p>${escape(capture.device?.name)} · ${escape(capture.device?.osVersion)}<br>字号：${escape(textSettingLabel(capture.actualTextSetting))}${capture.actualTextSetting?.description ? `<br>${escape(capture.actualTextSetting.description)}` : ''}</p>${scroll ? `<p>内容高度 ${escape(scroll.totalContentHeight)} · 可见高度 ${escape(scroll.viewportHeight)} · 末尾位置 ${escape(scroll.maxScrollOffset)}<br>最后内容：${escape(scroll.lastAnchor)}</p>` : ''}${images || '<p class="pending">待采集原图</p>'}`;
  };
  const sections = (ledger.cases ?? []).map(item => {
    const row = result.cases.find(row => row.id === item.id);
    return `<section><h2>${escape(routeNames[item.route] ?? item.route)} · ${escape(stateNames[item.state] ?? item.state)} <span class="${row?.passed ? 'ok' : 'pending'}">${row?.passed ? '证据完整' : '待完成'}</span></h2><p>字号：${item.textSize === 'largest-accessibility' ? '最大辅助字号' : '默认'} · 查看：${escape(item.checkpoints?.map(checkpointName).join(' → '))}<br><small>编号：${escape(item.id)}</small></p><div class="pair"><article><h3>鸿蒙参考</h3>${imageBlock(item.harmony, '鸿蒙')}</article><article><h3>iOS</h3>${imageBlock(item.ios, 'iOS')}</article></div><div class="review"><h3>逐页评审</h3>${item.review ? `<p>评审：${escape(item.review.reviewer)} · ${escape(item.review.reviewedAt)}</p>` + ['fidelity', 'readability', 'actions', 'polish'].map((key, index) => `<p><b>${['复刻程度', '可读性', '可操作性', '美学提升'][index]}</b>：${escape(item.review[key]?.notes || '未评审')}</p>`).join('') + (item.review.findings ?? []).map(finding => `<p>差异处理：${escape(finding.notes)}${finding.sourceAction ? `<br>参考操作：${escape(finding.sourceCaseId)} · ${escape(finding.sourceAction)}` : ''}</p>`).join('') : '<p class="pending">尚无独立评审；不能凭构建成功判断复刻完成。</p>'}${(row?.errors ?? []).map(error => `<p class="pending">${escape(error)}</p>`).join('')}</div></section>`;
  }).join('');
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MILO 两端逐页验收</title><style>body{margin:0;background:#080910;color:#ece9f5;font:16px/1.6 system-ui,sans-serif}main{max-width:1200px;margin:auto;padding:32px 20px}h1{font-size:30px}h2{font-size:20px}h3{font-size:16px}section{margin:28px 0;padding:24px;background:#11121c;border:1px solid #303044;border-radius:18px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{min-width:0}figure{margin:16px 0}img{max-width:100%;max-height:760px;border-radius:12px}figcaption,p{overflow-wrap:anywhere}figcaption{font-size:13px;color:#aaa6bd}a{color:#b8aaff}.pending{color:#f2bd76}.ok{color:#91d9b6}h2 span{font-size:13px;margin-left:12px}.review{border-top:1px solid #303044;margin-top:20px}.summary{padding:20px;background:#1a1729;border-radius:16px}@media(max-width:650px){.pair{gap:12px}section{padding:12px}main{padding:20px 10px}}</style><main><h1>MILO · 鸿蒙 / iOS 逐页验收</h1><div class="summary"><b>${result.passed ? '所需证据结构完整' : '验收尚未完成'}</b><p>${result.passedCases} / ${result.total} 个状态的证据完整；要求至少 ${result.requiredMinimum} 个状态。两侧均展示原始截图，不补画、不改图。</p><p>此报告校验源代码、构建与图片指纹及评审记录；页面真实性、操作体验和美学判断由具名独立评审负责。模拟器证据不代表实体手机实测。</p></div><details><summary>待解决项（${result.errors.length}）</summary><ul>${result.errors.map(error => `<li>${escape(error)}</li>`).join('')}</ul></details>${sections}</main></html>`;
}

function options(args) {
  const value = {};
  for (let index = 0; index < args.length; index += 2) {
    assert(args[index]?.startsWith('--') && args[index + 1] && !args[index + 1].startsWith('--'), 'Options require --name value');
    assert(['root', 'cases', 'ios-provenance', 'harmony-root', 'evidence-root', 'output', 'path', 'case'].includes(args[index].slice(2)), `Unknown option ${args[index]}`);
    value[args[index].slice(2)] = args[index + 1];
  }
  return value;
}

function main() {
  const [command, ...args] = process.argv.slice(2);
  const opts = options(args);
  const root = path.resolve(opts.root ?? project);
  if (command === 'hash-source') { console.log(JSON.stringify(hashIOSSource(root), null, 2)); return; }
  if (command === 'hash-build') { assert(opts.path, 'hash-build requires --path'); console.log(hashBuild(root, opts.path)); return; }
  assert(['validate', 'report', 'hash-fixture', 'hash-captures'].includes(command), 'Usage: parity-evidence.mjs hash-source|hash-build|hash-fixture|hash-captures|validate|report [--name value]');
  const casesFile = path.resolve(opts.cases ?? path.join(root, 'docs/visual-parity/cases.json'));
  const ledger = json(casesFile);
  if (['hash-fixture', 'hash-captures'].includes(command)) {
    const item = ledger.cases.find(item => item.id === opts.case); assert(item, 'A known --case ID is required');
    if (command === 'hash-fixture') console.log(fixtureHash(ledger, item));
    else { assert(item.harmony && item.ios, 'Both platform captures must exist'); console.log(JSON.stringify({ harmony: captureMetadataHash(item.harmony), ios: captureMetadataHash(item.ios) }, null, 2)); }
    return;
  }
  const evidenceRoot = path.resolve(opts['evidence-root'] ?? path.dirname(casesFile));
  const readOptional = file => { try { return json(file); } catch { return undefined; } };
  const harmonyManifest = readOptional(path.resolve(path.dirname(casesFile), ledger.referenceManifest ?? 'harmony-source.json'));
  const iosManifest = readOptional(path.resolve(opts['ios-provenance'] ?? path.join(path.dirname(casesFile), 'ios-source-build.json')));
  const result = validateEvidence({ ledger, harmonyManifest, iosManifest, harmonyRoot: path.resolve(opts['harmony-root'] ?? harmonyManifest?.referenceRoot ?? root), iosRoot: root, evidenceRoot });
  if (command === 'report') {
    const output = path.resolve(opts.output ?? path.join(path.dirname(casesFile), 'report.html'));
    assert(output !== casesFile, 'Report cannot overwrite the capture manifest');
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, renderReport({ ledger, result, evidenceRoot, output }));
    console.log(`已生成对照报告：${output}（${result.passedCases}/${result.total} 证据完整）`);
  } else {
    console.log(JSON.stringify(result, null, 2));
    if (!result.passed) process.exitCode = 1;
  }
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  try { main(); } catch (error) { console.error(`Evidence unavailable: ${error.message}`); process.exitCode = 1; }
}

// Shared native evidence primitives; legacy validation behavior is unchanged.
export { checkProvenance, validateCapture, pngSize, contained, overflowIds };
