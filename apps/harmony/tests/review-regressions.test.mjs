import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript/lib/typescript.js');
const sourceRoot = new URL('../entry/src/main/ets/', import.meta.url);

// Run the actual non-UI ArkTS adapter, with only device APIs substituted.
function loadEts(path, dependencies = {}, globals = {}) {
  const source = readFileSync(new URL(path, sourceRoot), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: (name) => {
    assert.ok(name in dependencies, `Unexpected device dependency: ${name}`);
    return dependencies[name];
  }, console, setTimeout, clearTimeout, ...globals }, { filename: path });
  return exports;
}

const { gestureLocalPoint } = loadEts('features/mood/GesturePoint.ets');
test('both rotary gestures ignore missing, sparse, null and non-finite fingers', () => {
  for (const event of [undefined, {}, { fingerList: [] }, { fingerList: [undefined] },
    { fingerList: [null] }, { fingerList: [{ localX: NaN, localY: 1 }] }]) {
    assert.equal(gestureLocalPoint(event), null);
  }
  const sparse = [];
  sparse[7] = { localX: 24, localY: 36 };
  assert.equal(JSON.stringify(gestureLocalPoint({ fingerList: sparse })), '{"x":24,"y":36}');
  assert.equal(gestureLocalPoint({ fingerInfos: [{ localX: 1, localY: 2 }], fingerList: sparse }).x, 1);
  for (const path of ['features/home/HomeScreen.ets', 'features/mood/MoodOrbitCarousel.ets']) {
    const source = readFileSync(new URL(path, sourceRoot), 'utf8');
    assert.match(source, /gestureLocalPoint\(event\)/);
    assert.doesNotMatch(source, /fingerList\[0\]/);
  }
});

function platformFixture(createError = false) {
  const engines = [];
  const pending = [];
  const timers = new Map();
  let nextTimer = 0;
  let delayed = false;
  function makeEngine() {
    const engine = {
      shutdowns: 0, cancels: 0, finishes: 0,
      setListener(listener) { this.listener = listener; },
      startListening(params) { this.params = params; },
      finish() { this.finishes++; }, cancel() { this.cancels++; }, shutdown() { this.shutdowns++; }
    };
    engines.push(engine);
    return engine;
  }
  const sdk = { speechRecognizer: { createEngine: async (params) => {
    assert.equal(params.online, 1, 'Speech must stay offline');
    if (createError) throw new Error('engine unavailable');
    if (delayed) return await new Promise(resolve => pending.push(() => resolve(makeEngine())));
    return makeEngine();
  } } };
  const { HarmonySpeechPlatform } = loadEts('core/system/HarmonySpeechPlatform.ets', {
    '@kit.CoreSpeechKit': sdk, '@kit.AbilityKit': {}
  }, {
    setTimeout: (fn) => { timers.set(++nextTimer, fn); return nextTimer; },
    clearTimeout: id => timers.delete(id)
  });
  const platform = new HarmonySpeechPlatform({});
  const results = [];
  const listener = { onPartial: text => results.push(['partial', text]), onFinal: text => results.push(['final', text]), onError: error => results.push(['error', error]) };
  return { platform, results, listener, engines, timers, pending, delay: () => { delayed = true; } };
}

test('production adapter opens the microphone and releases engine on final text', async () => {
  const f = platformFixture();
  const done = f.platform.start(f.listener);
  await new Promise(setImmediate);
  const engine = f.engines[0];
  assert.equal(engine.params.extraParams.recognitionMode, 0);
  assert.equal(engine.params.audioInfo.sampleRate, 16000);
  engine.listener.onResult(engine.params.sessionId, { result: '测试回忆', isFinal: true, isLast: true });
  await done;
  assert.deepEqual(f.results, [['final', '测试回忆']]);
  assert.equal(engine.shutdowns, 1);
  assert.equal(f.timers.size, 0);
});

test('finish requests transcription while cancellation ignores late results', async () => {
  const f = platformFixture();
  const done = f.platform.start(f.listener);
  await new Promise(setImmediate);
  const engine = f.engines[0];
  await f.platform.finish();
  assert.equal(engine.finishes, 1);
  await f.platform.cancel();
  await done;
  engine.listener.onResult(engine.params.sessionId, { result: '过期内容', isFinal: true });
  assert.deepEqual(f.results, []);
  assert.equal(engine.shutdowns, 1);
});

test('a final clause does not close recording before the last result of the session', async () => {
  const f = platformFixture();
  const done = f.platform.start(f.listener);
  await new Promise(setImmediate);
  const engine = f.engines[0];
  engine.listener.onResult(engine.params.sessionId, { result: '今天阳光很好', isFinal: true, isLast: false });
  assert.equal(engine.shutdowns, 0, 'A final clause is not necessarily the end of the recording');
  engine.listener.onResult(engine.params.sessionId, { result: '今天阳光很好我的心情很平静', isFinal: true, isLast: true });
  await done;
  assert.equal(f.results.at(-1)[1], '今天阳光很好我的心情很平静');
  assert.equal(engine.shutdowns, 1);
});

test('a cancelled initialization releases a late engine without starting recording', async () => {
  const f = platformFixture();
  f.delay();
  const done = f.platform.start(f.listener);
  await f.platform.destroy();
  await done;
  f.pending.shift()();
  await new Promise(setImmediate);
  assert.equal(f.engines[0].shutdowns, 1);
  assert.equal(f.engines[0].params, undefined);
});

test('missing callbacks and engine creation failures return errors rather than hang', async () => {
  const f = platformFixture();
  const done = f.platform.start(f.listener);
  await new Promise(setImmediate);
  [...f.timers.values()][0]();
  await done;
  assert.equal(f.results[0][0], 'error');
  assert.equal(f.engines[0].shutdowns, 1);
  const broken = platformFixture(true);
  await broken.platform.start(broken.listener);
  assert.equal(broken.results[0][0], 'error');
  assert.equal(broken.timers.size, 0);
});
