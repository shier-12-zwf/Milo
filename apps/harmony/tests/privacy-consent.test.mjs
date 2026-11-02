import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const source = (path) => readFileSync(new URL(path, root), 'utf8');
function load(path, dependencies = {}) {
  const code = ts.transpileModule(source(path), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  vm.runInNewContext(code, {
    exports, console: { error() {} },
    require: (id) => {
      assert.ok(id in dependencies, `unexpected runtime dependency ${id}`);
      return dependencies[id];
    },
  }, { filename: fileURLToPath(new URL(path, root)) });
  return exports;
}

test('consent is explicit, versioned, fail-closed and does not erase a diary or login', () => {
  const { PrivacyConsentRepository, PRIVACY_CONSENT_KEY, PRIVACY_POLICY_VERSION } = load('core/auth/PrivacyConsentRepository.ets');
  const values = new Map([['diary', 'private fixture'], ['session', 'local fixture']]);
  const store = { read: (key) => values.get(key), write: (key, value) => values.set(key, value) };
  const repository = new PrivacyConsentRepository(store);
  assert.equal(repository.hasAccepted(), false);
  values.set(PRIVACY_CONSENT_KEY, 'older-policy');
  assert.equal(repository.hasAccepted(), false);
  repository.accept();
  assert.equal(values.get(PRIVACY_CONSENT_KEY), PRIVACY_POLICY_VERSION);
  assert.equal(repository.hasAccepted(), true);
  assert.equal(values.get('diary'), 'private fixture');
  assert.equal(values.get('session'), 'local fixture');
  const failed = new PrivacyConsentRepository({ read() { throw new Error('unavailable'); } });
  assert.equal(failed.hasAccepted(), false);
});

test('constructing AGC provider and all SDK operations stay inert before consent', async () => {
  const calls = [];
  const auth = {
    init() { calls.push('init'); },
    async requestVerifyCode() { calls.push('code'); },
    async signIn() { calls.push('signIn'); return { getUser: () => ({ getUid: () => 'test-uid', getEmail: () => 'test@example.test' }) }; },
    async resetPassword() { calls.push('reset'); },
    async signOut() { calls.push('signOut'); },
    async getCurrentUser() { calls.push('currentUser'); return {}; },
    async deleteUser() { calls.push('delete'); },
  };
  const { AgcAuthProvider } = load('core/auth/AgcAuthProvider.ets', {
    '@kit.ArkTS': { buffer: Buffer },
    '@hw-agconnect/auth': { __esModule: true, default: auth, VerifyCodeAction: { RESET_PASSWORD: 2, REGISTER_LOGIN: 1 } },
    './AuthProvider': load('core/auth/AuthProvider.ets'),
  });
  let accepted = false;
  const context = { resourceManager: { getRawFileContentSync() { calls.push('config'); return new Uint8Array(Buffer.from('{}')); } } };
  const provider = new AgcAuthProvider(context, () => accepted);
  assert.deepEqual(calls, []);
  const operations = [
    () => provider.sendCode('test@example.test', 'sign-in'),
    () => provider.signIn('test@example.test', '123456'),
    () => provider.signInWithPassword('test@example.test', 'test-only-password'),
    () => provider.resetPassword('test@example.test', '123456', 'test-only-password'),
    () => provider.deleteAccount(),
  ];
  for (const operation of operations) {
    const result = await operation();
    assert.equal(result.ok, false);
    assert.match(result.error.message, /同意隐私政策/);
  }
  await provider.signOut();
  assert.deepEqual(calls, []);
  accepted = true;
  for (const operation of operations) {
    const result = await operation();
    assert.equal(result.ok, true, JSON.stringify(result));
  }
  await provider.signOut();
  assert.equal(calls.filter((call) => call === 'init').length, 1);
  const previous = [...calls];
  accepted = false;
  assert.equal((await provider.sendCode('test@example.test', 'sign-in')).ok, false);
  await provider.signOut();
  assert.deepEqual(calls, previous);
  const defaultDenied = new AgcAuthProvider(context);
  assert.equal((await defaultDenied.signIn('test@example.test', '123456')).ok, false);
  assert.deepEqual(calls, previous);
});

test('both new and restored sessions are behind consent, with offline policies available before login', () => {
  const index = source('pages/Index.ets');
  assert.ok(index.indexOf('if (!this.privacyAccepted)') < index.indexOf("this.authGate === 'signedOut'"));
  assert.match(index, /new AgcAuthProvider\(getContext\(this\), \(\) => this\.privacyRepository\.hasAccepted\(\)\)/);
  for (const path of ['features/auth/LoginScreen.ets', 'features/auth/AccountScreen.ets']) {
    const screen = source(path);
    assert.match(screen, /LegalDocumentScreen/);
    assert.match(screen, /隐私政策/);
    assert.match(screen, /用户协议/);
  }
  const gate = source('features/legal/PrivacyConsentScreen.ets');
  assert.match(gate, /暂不同意/);
  assert.match(gate, /同意隐私政策与用户协议并继续/);
  assert.doesNotMatch(gate, /aboutToAppear|auth\.|requestVerifyCode|\.accept\(/);
  const reader = source('features/legal/LegalDocumentScreen.ets');
  assert.match(reader, /getRawFileContentSync/);
  for (const name of ['privacy-policy.txt', 'user-agreement.txt']) {
    const body = readFileSync(new URL(`../entry/src/main/resources/rawfile/${name}`, import.meta.url), 'utf8');
    assert.match(body, /2026年10月11日/);
    assert.match(body, /1972375139@qq\.com/);
    assert.doesNotMatch(body, /\{\{|待填写|YOUR_|example\.com/);
  }
});

test('hostable policy text and offline release resources remain identical', () => {
  for (const [resource, document] of [
    ['privacy-policy.txt', 'operations/privacy-policy.template.md'],
    ['user-agreement.txt', 'compliance/user-agreement.md'],
  ]) {
    const bundled = readFileSync(new URL(`../entry/src/main/resources/rawfile/${resource}`, import.meta.url), 'utf8');
    const published = readFileSync(new URL(`../../../docs/${document}`, import.meta.url), 'utf8');
    assert.equal(published.replace(/^#{1,2} /gm, '').trimEnd(), bundled.trimEnd());
  }
});
