import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';

const etsRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../entry/src/main/ets');
const cache = new Map();

function load(rel) {
  const key = rel.replace(/\\/g, '/');
  if (cache.has(key)) return cache.get(key);
  const file = join(etsRoot, key);
  const source = readFileSync(file, 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    fileName: file,
  }).outputText;
  const exports = {};
  const module = { exports };
  const localRequire = (id) => {
    if (id.startsWith('.')) {
      let resolved = resolve(dirname(file), id);
      if (!resolved.endsWith('.ets')) resolved += '.ets';
      return load(relative(etsRoot, resolved));
    }
    if (id === '@kit.ArkData') return { preferences: {} };
    if (id === '@kit.ArkTS') return { buffer: Buffer };
    throw new Error(`unexpected dependency ${id} from ${key}`);
  };
  vm.runInNewContext(compiled, {
    exports,
    module,
    require: localRequire,
    console,
    setTimeout,
    clearTimeout,
  }, { filename: file });
  cache.set(key, module.exports);
  return module.exports;
}

class MemoryStorage {
  constructor() { this.values = new Map(); }
  read(key) { return this.values.get(key); }
  write(key, value) { this.values.set(key, value); }
  remove(key) { this.values.delete(key); }
  hydrate(key, value) { this.values.set(key, value); }
}

test('explicit deletion failure rolls back and an unknown restart can retry remotely', async () => {
  const { AuthController } = load('features/auth/AuthController.ets');
  const { AuthSessionStore } = load('core/auth/AuthSessionStore.ets');
  const { FakeAuthProvider } = load('core/auth/FakeAuthProvider.ets');
  const storage = new MemoryStorage();
  const store = new AuthSessionStore(storage);
  const session = { uid: 'test-user', email: 'test@example.com', provider: 'agc' };
  store.save(session);
  const provider = new FakeAuthProvider();
  provider.deleteFails = true;
  const controller = new AuthController({ provider, store, allowOwnerBackdoor: false });
  controller.restore();
  let cleaned = 0;
  assert.equal(await controller.deleteAccount(() => { cleaned += 1; }), false);
  assert.equal(cleaned, 0);
  assert.equal(controller.isDeletionOutcomeUnknown(), false);
  assert.equal(controller.isDeletionPending(), false);
  assert.equal(store.loadDeletionRecovery(), undefined);
  assert.equal(controller.getError().message, '网络连接失败，请检查后重试。');
  provider.deleteFails = false;
  assert.equal(await controller.deleteAccount(() => { cleaned += 1; }), true);
  assert.equal(cleaned, 1);
  assert.equal(provider.deleteCalls, 2);

  const restartedStorage = new MemoryStorage();
  const origin = new AuthSessionStore(restartedStorage);
  origin.save(session);
  origin.saveDeletionRequested(session);
  restartedStorage.write('entries', 'kept');
  const remote = new FakeAuthProvider();
  const restarted = new AuthController({ provider: remote, store: new AuthSessionStore(restartedStorage) });
  assert.equal(restarted.restore().uid, 'test-user');
  assert.equal(restarted.isDeletionOutcomeUnknown(), true);
  assert.equal(await restarted.deleteAccount(() => { restartedStorage.remove('entries'); }), false);
  assert.equal(remote.deleteCalls, 0);
  remote.deleteFails = true;
  assert.equal(await restarted.retryRemoteDeletion(() => { restartedStorage.remove('entries'); }), false);
  assert.equal(restarted.isDeletionOutcomeUnknown(), true);
  assert.equal(restartedStorage.read('entries'), 'kept');
  remote.deleteFails = false;
  assert.equal(await restarted.retryRemoteDeletion(() => { restartedStorage.remove('entries'); }), true);
  assert.equal(restartedStorage.read('entries'), undefined);
  assert.equal(remote.deleteCalls, 2);
});

test('the owner backdoor is debug-only and diaries migrate per uid', () => {
  const { AuthController, BACKDOOR_EMAIL } = load('features/auth/AuthController.ets');
  const { AuthSessionStore } = load('core/auth/AuthSessionStore.ets');
  const { FakeAuthProvider } = load('core/auth/FakeAuthProvider.ets');
  const locked = new AuthController({
    provider: new FakeAuthProvider(),
    store: new AuthSessionStore(new MemoryStorage()),
  });
  locked.restore();
  return locked.submitEmail(BACKDOOR_EMAIL).then((session) => {
    assert.equal(session, undefined);
    assert.equal(locked.getPhase(), 'signedOut');
    assert.equal(locked.allowsOwnerBackdoor(), false);
  }).then(async () => {
    const storage = new MemoryStorage();
    const open = new AuthController({
      provider: new FakeAuthProvider(),
      store: new AuthSessionStore(storage),
      allowOwnerBackdoor: true,
    });
    open.restore();
    const session = await open.submitEmail(' Milo ');
    assert.equal(session.uid, 'milo-local-owner');
    assert.equal(await open.signOut(), true);

    const { EntryRepository, ENTRIES_STORAGE_KEY, scopedEntriesKey } = load('core/data/EntryRepository.ets');
    const { RecallSessionRepository, DRAFT_STORAGE_KEY } = load('core/data/RecallSessionRepository.ets');
    const diaries = new MemoryStorage();
    diaries.hydrate(ENTRIES_STORAGE_KEY, JSON.stringify({
      schemaVersion: 1,
      entries: [{
        id: 'legacy', createdAt: 10, kind: 'now', diaryEnabled: false,
        mood: { valence: 0, labels: ['平静'] },
      }],
    }));
    diaries.hydrate(DRAFT_STORAGE_KEY, JSON.stringify({
      schemaVersion: 1,
      state: { screenName: 'home', draft: { valence: 0, labels: [], diaryEnabled: true, transcript: [] } },
    }));
    const first = new EntryRepository(diaries, 'uid-a');
    assert.equal(first.list()[0].id, 'legacy');
    assert.equal(diaries.read(ENTRIES_STORAGE_KEY), undefined);
    assert.ok(diaries.read(scopedEntriesKey('uid-a')));
    assert.equal(new EntryRepository(diaries, 'uid-b').list().length, 0);
    const drafts = new RecallSessionRepository(diaries, 'uid-a');
    assert.equal(drafts.loadDraft().screen.name, 'home');
    assert.equal(diaries.read(DRAFT_STORAGE_KEY), undefined);
    assert.equal(new RecallSessionRepository(diaries, 'uid-b').loadDraft(), undefined);
  });
});

test('long AI replies are kept and gateway errors, limits, and cancel are honored', async () => {
  const { conciseReply, ConversationController } = load('features/conversation/ConversationController.ets');
  const full = '听起来那是一段让人难忘的时光。河边有什么让你记得很清楚？你和朋友后来还有联系吗？';
  assert.equal(conciseReply(full), full);
  assert.equal(conciseReply('很长的内容'.repeat(20)), '很长的内容'.repeat(20));
  assert.equal(conciseReply('***'), undefined);

  const { HttpAiGatewayClient, CancelSignalImpl, GATEWAY_MAX_TEXT_LENGTH, GATEWAY_MAX_TIME_MARK_LENGTH } = load('core/network/AiGatewayClient.ets');
  let captured;
  const hanging = {
    async fetch(_url, init) {
      captured = JSON.parse(init.body);
      if (init.signal?.cancelled) throw new Error('cancelled');
      return {
        status: 503,
        async text() {
          return JSON.stringify({
            code: 'AI_DISABLED', message: '模型已暂停', retryable: false, requestId: 'srv-1',
          });
        },
      };
    },
  };
  const client = new HttpAiGatewayClient({
    baseUrl: 'https://milomood.xyz', bearerToken: 'token', timeoutMs: 1000, fetcher: hanging,
  });
  const draft = {
    mood: { valence: 0, labels: [] },
    timeMark: '时'.repeat(80),
    transcript: [{ role: 'user', text: '字'.repeat(2500), ts: 1 }],
  };
  const failed = await client.respond({ draft, userText: '问'.repeat(2500) });
  assert.equal(failed.ok, false);
  assert.equal(failed.error.code, 'AI_DISABLED');
  assert.equal(failed.error.message, '模型已暂停');
  assert.equal(failed.error.retryable, false);
  assert.equal(failed.error.requestId, 'srv-1');
  assert.equal(captured.userText.length, GATEWAY_MAX_TEXT_LENGTH);
  assert.equal(captured.draft.timeMark.length, GATEWAY_MAX_TIME_MARK_LENGTH);
  assert.equal(captured.draft.transcript[0].text.length, GATEWAY_MAX_TEXT_LENGTH);

  let destroyed = false;
  const slow = {
    fetch(_url, init) {
      return new Promise((_resolve, reject) => {
        if (init.signal?.cancelled) {
          destroyed = true;
          reject(new Error('cancelled'));
          return;
        }
        init.signal?.onCancel(() => {
          destroyed = true;
          reject(new Error('cancelled'));
        });
      });
    },
  };
  const timed = new HttpAiGatewayClient({
    baseUrl: 'https://milomood.xyz', bearerToken: 'token', timeoutMs: 20, fetcher: slow,
  });
  const timeout = await timed.open({ draft: { mood: { valence: 0, labels: [] }, transcript: [] } });
  assert.equal(timeout.ok, false);
  assert.equal(timeout.error.code, 'AI_UNAVAILABLE');
  assert.equal(destroyed, true);

  const signal = new CancelSignalImpl();
  signal.fire();
  const already = await timed.open({ draft: { mood: { valence: 0, labels: [] }, transcript: [] } }, { signal });
  assert.equal(already.ok, false);
  assert.equal(already.error.code, 'AI_UNAVAILABLE');

  const index = readFileSync(join(etsRoot, 'pages/Index.ets'), 'utf8');
  assert.match(index, /allowOwnerBackdoor: BuildProfile\.DEBUG/);
  assert.match(index, /if \(!signedOut\) return/);
  assert.match(index, /new EntryRepository\(this\.storage, uid\)/);
  const detail = readFileSync(join(etsRoot, 'features/timeline/DetailScreen.ets'), 'utf8');
  assert.match(detail, /放下这段回忆？/);
  const chat = readFileSync(join(etsRoot, 'features/conversation/ChatScreen.ets'), 'utf8');
  assert.match(chat, /scheduleChat/);
  assert.match(chat, /maxLength\(GATEWAY_MAX_TEXT_LENGTH\)/);
  assert.equal(ConversationController.length >= 0, true);
});
