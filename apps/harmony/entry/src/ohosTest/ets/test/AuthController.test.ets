import { describe, expect, it } from '@ohos/hypium';
import {
  AuthController,
  BACKDOOR_EMAIL,
  BACKDOOR_SESSION,
} from '../../../main/ets/features/auth/AuthController';
import { FakeAuthProvider, FAKE_AUTH_CODE } from '../../../main/ets/core/auth/FakeAuthProvider';
import {
  AuthSessionStore,
  SESSION_STORAGE_KEY,
  DELETION_PENDING_STORAGE_KEY,
  parseSession,
} from '../../../main/ets/core/auth/AuthSessionStore';
import { MapKVStorage } from '../../../main/ets/core/data/KVStorage';
import { clearAvatarRecord } from '../../../main/ets/core/system/AvatarCleanup';
import {
  isValidEmail,
  isValidPassword,
  isValidVerificationCode,
  type CodePurpose,
  type AuthSession,
  type SendCodeResult,
  type SignInResult,
} from '../../../main/ets/core/auth/AuthProvider';

class FailingDeletionStorage extends MapKVStorage {
  failWriteKey: string = '';
  failRemoveKey: string = '';
  mutateBeforeRemoveFailure: boolean = false;
  write(key: string, value: string): void {
    if (key === this.failWriteKey) {
      this.failWriteKey = '';
      throw new Error('Synthetic preferences flush failure');
    }
    super.write(key, value);
  }
  remove(key: string): void {
    if (key === this.failRemoveKey) {
      this.failRemoveKey = '';
      if (this.mutateBeforeRemoveFailure) super.remove(key);
      throw new Error('Synthetic removal flush failure');
    }
    super.remove(key);
  }
}

class FailingConfirmationStore extends AuthSessionStore {
  failConfirmation: boolean = true;
  saveDeletionPending(session: AuthSession): void {
    if (this.failConfirmation) {
      this.failConfirmation = false;
      throw new Error('Synthetic confirmed-deleted flush failure');
    }
    super.saveDeletionPending(session);
  }
}

class RecoverableAuthProvider extends FakeAuthProvider {
  failSending: boolean = false;
  failPasswordLogin: boolean = false;
  sendCalls: number = 0;

  async sendCode(email: string, purpose: CodePurpose): Promise<SendCodeResult> {
    this.sendCalls += 1;
    if (this.failSending) {
      return { ok: false, error: { reason: 'network', message: '网络连接失败，请检查后重试。' } };
    }
    return super.sendCode(email, purpose);
  }

  async signInWithPassword(email: string, password: string): Promise<SignInResult> {
    if (this.failPasswordLogin) {
      return { ok: false, error: { reason: 'network', message: '网络连接失败，请检查后重试。' } };
    }
    return super.signInWithPassword(email, password);
  }
}

function newController(storage: MapKVStorage): AuthController {
  return new AuthController({
    provider: new FakeAuthProvider(),
    store: new AuthSessionStore(storage),
  });
}

interface RawSessionRow {
  uid?: string;
  email?: string;
  provider?: string;
}

interface RawSessionEnvelope {
  schemaVersion?: number;
  session?: RawSessionRow;
}

function authControllerSuite() {
  describe('authControllerTest', () => {
    it('avatar deletion retains its pointer after an unlink failure and retries idempotently', 0, () => {
      const storage = new FailingDeletionStorage();
      storage.write('avatar-test', '/synthetic-files/avatar-123.img');
      let didThrow = false;
      try {
        clearAvatarRecord(storage, 'avatar-test', '/synthetic-files', (_path: string): void => {
          throw new Error('Synthetic unlink failure');
        });
      } catch (_error) { didThrow = true; }
      expect(didThrow).assertTrue();
      expect(storage.read('avatar-test')).assertEqual('/synthetic-files/avatar-123.img');
      let unlinkCalls = 0;
      const unlink = (_path: string): void => { unlinkCalls += 1; };
      clearAvatarRecord(storage, 'avatar-test', '/synthetic-files', unlink);
      clearAvatarRecord(storage, 'avatar-test', '/synthetic-files', unlink);
      expect(unlinkCalls).assertEqual(1);
      expect(storage.read('avatar-test')).assertEqual(undefined);
    });
    it('avatar deletion propagates metadata flush failures without deleting unowned paths', 0, () => {
      const storage = new FailingDeletionStorage();
      storage.write('avatar-test', '/synthetic-files/avatar-../journal.json');
      storage.failRemoveKey = 'avatar-test';
      let unlinkCalls = 0;
      let didThrow = false;
      const unlink = (_path: string): void => { unlinkCalls += 1; };
      try { clearAvatarRecord(storage, 'avatar-test', '/synthetic-files', unlink); }
      catch (_error) { didThrow = true; }
      expect(didThrow).assertTrue();
      expect(unlinkCalls).assertEqual(0);
      clearAvatarRecord(storage, 'avatar-test', '/synthetic-files', unlink);
      expect(storage.read('avatar-test')).assertEqual(undefined);
    });
    it('changes an authenticated account password without losing its session', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: new AuthSessionStore(storage) });
      await controller.submitEmail('test@example.com');
      await controller.submitCode(FAKE_AUTH_CODE, 'OldPass123!');
      const uid = controller.getSession()!.uid;
      expect(await controller.sendAccountPasswordCode()).assertTrue();
      expect(await controller.sendAccountPasswordCode()).assertFalse();
      expect(await controller.changeAccountPassword('x', 'NewPass123!')).assertFalse();
      expect(controller.getSession()!.uid).assertEqual(uid);
      expect(await controller.changeAccountPassword(FAKE_AUTH_CODE, 'NewPass123!')).assertTrue();
      expect(controller.getPhase()).assertEqual('signedIn');
      expect(controller.getSession()!.uid).assertEqual(uid);
      expect((await provider.signInWithPassword('test@example.com', 'NewPass123!')).ok).assertTrue();
    });

    it('does not send password reset requests for the local owner', 0, async () => {
      const controller = newController(new MapKVStorage());
      await controller.submitEmail(BACKDOOR_EMAIL);
      expect(await controller.sendAccountPasswordCode()).assertFalse();
      expect(await controller.changeAccountPassword(FAKE_AUTH_CODE, 'NewPass123!')).assertFalse();
      expect(controller.getSession()!.uid).assertEqual(BACKDOOR_SESSION.uid);
    });
    it('an uncertain remote deletion retains data and requires explicit local-only cleanup', 0, async () => {
      const store = new AuthSessionStore(new MapKVStorage());
      store.save({ uid: 'test-user', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      provider.deleteFails = true;
      let cleanupCalls = 0;
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(cleanupCalls).assertEqual(0);
      expect(store.load()!.uid).assertEqual('test-user');
      expect(controller.getPhase()).assertEqual('signedIn');
      expect(controller.isDeletionOutcomeUnknown()).assertTrue();
      provider.deleteFails = false;
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(cleanupCalls).assertEqual(0);
      expect(provider.deleteCalls).assertEqual(1);
      expect(await controller.clearLocalAfterUnknown(() => { cleanupCalls += 1; })).assertTrue();
      expect(cleanupCalls).assertEqual(1);
      expect(provider.deleteCalls).assertEqual(1);
      expect(store.load()).assertEqual(undefined);
      expect(controller.getSession()).assertEqual(undefined);
    });

    it('deleting a local owner session never deletes a remote account', 0, async () => {
      const store = new AuthSessionStore(new MapKVStorage());
      store.save(BACKDOOR_SESSION);
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      expect(await controller.deleteAccount(() => {})).assertTrue();
      expect(provider.deleteCalls).assertEqual(0);
      expect(store.load()).assertEqual(undefined);
    });
    it('recovers each partial local cleanup after restart without deleting the remote account twice', 0, async () => {
      const keys: string[] = ['avatar', 'settings', 'keychain', 'entries', 'draft'];
      for (let failedIndex = 0; failedIndex < keys.length; failedIndex += 1) {
        const storage = new FailingDeletionStorage();
        const store = new AuthSessionStore(storage);
        store.save({ uid: 'deletion-test', email: 'test@example.com', provider: 'agc' });
        keys.forEach((key: string) => { storage.write(key, 'synthetic data'); });
        const provider = new FakeAuthProvider();
        const first = new AuthController({ provider: provider, store: store });
        first.restore();
        storage.failRemoveKey = keys[failedIndex];
        const cleanup = (): void => { keys.forEach((key: string) => { storage.remove(key); }); };
        expect(await first.deleteAccount(cleanup)).assertFalse();
        expect(first.isDeletionPending()).assertTrue();
        expect(first.getSession()!.uid).assertEqual('deletion-test');
        expect(first.getPhase()).assertEqual('signedIn');
        expect(first.getError()!.message.indexOf('再次点击注销') >= 0).assertTrue();
        expect(provider.deleteCalls).assertEqual(1);
        expect(store.loadDeletionPending()!.uid).assertEqual('deletion-test');
        await first.signOut();
        expect(first.getSession()!.uid).assertEqual('deletion-test');
        expect(provider.signOutCallCount()).assertEqual(0);
        expect(await first.sendAccountPasswordCode()).assertFalse();
        expect(await first.changeAccountPassword(FAKE_AUTH_CODE, 'NewPass123!')).assertFalse();
        const restarted = new AuthController({ provider: provider, store: new AuthSessionStore(storage) });
        expect(restarted.restore()!.uid).assertEqual('deletion-test');
        expect(restarted.isDeletionPending()).assertTrue();
        expect(await restarted.deleteAccount(cleanup)).assertTrue();
        expect(provider.deleteCalls).assertEqual(1);
        expect(restarted.getPhase()).assertEqual('signedOut');
        expect(restarted.getSession()).assertEqual(undefined);
        expect(restarted.isDeletionPending()).assertFalse();
        keys.forEach((key: string) => { expect(storage.read(key)).assertEqual(undefined); });
        expect(store.load()).assertEqual(undefined);
        expect(store.loadDeletionPending()).assertEqual(undefined);
      }
    });
    it('does not delete the remote account when the storage preflight cannot flush', 0, async () => {
      const storage = new FailingDeletionStorage();
      const store = new AuthSessionStore(storage);
      store.save({ uid: 'write-test', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      storage.failWriteKey = SESSION_STORAGE_KEY;
      let cleanupCalls = 0;
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(provider.deleteCalls).assertEqual(0);
      expect(cleanupCalls).assertEqual(0);
      expect(controller.isDeletionPending()).assertFalse();
      expect(store.load()!.uid).assertEqual('write-test');
    });
    it('retries a failed success-marker flush in memory before touching local data', 0, async () => {
      const storage = new FailingDeletionStorage();
      const store = new FailingConfirmationStore(storage);
      store.save({ uid: 'marker-test', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      let cleanupCalls = 0;
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(cleanupCalls).assertEqual(0);
      expect(controller.isDeletionPending()).assertTrue();
      expect(controller.isDeletionOutcomeUnknown()).assertFalse();
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertTrue();
      expect(cleanupCalls).assertEqual(1);
      expect(provider.deleteCalls).assertEqual(1);
    });
    it('a failed intent flush never calls remote deletion or removes local data', 0, async () => {
      const storage = new FailingDeletionStorage();
      const store = new AuthSessionStore(storage);
      store.save({ uid: 'intent-test', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      storage.failWriteKey = DELETION_PENDING_STORAGE_KEY;
      let cleanupCalls = 0;
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(provider.deleteCalls).assertEqual(0);
      expect(cleanupCalls).assertEqual(0);
      expect(controller.isDeletionPending()).assertFalse();
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertTrue();
      expect(provider.deleteCalls).assertEqual(1);
    });
    it('restart after a failed confirmation flush never invents cloud success or deletes twice', 0, async () => {
      const storage = new MapKVStorage();
      const store = new FailingConfirmationStore(storage);
      store.save({ uid: 'unknown-test', email: 'test@example.com', provider: 'agc' });
      storage.write('entries', 'synthetic diary');
      const provider = new FakeAuthProvider();
      const first = new AuthController({ provider: provider, store: store });
      first.restore();
      let cleanupCalls = 0;
      const cleanup = (): void => { cleanupCalls += 1; storage.remove('entries'); };
      expect(await first.deleteAccount(cleanup)).assertFalse();
      const restarted = new AuthController({ provider: provider, store: new AuthSessionStore(storage) });
      expect(restarted.restore()!.uid).assertEqual('unknown-test');
      expect(restarted.isDeletionOutcomeUnknown()).assertTrue();
      expect(restarted.getError()!.message.indexOf('不代表云端账号已注销') >= 0).assertTrue();
      expect(await restarted.deleteAccount(cleanup)).assertFalse();
      expect(provider.deleteCalls).assertEqual(1);
      expect(cleanupCalls).assertEqual(0);
      expect(storage.read('entries')).assertEqual('synthetic diary');
      expect(await restarted.clearLocalAfterUnknown(cleanup)).assertTrue();
      expect(provider.deleteCalls).assertEqual(1);
      expect(cleanupCalls).assertEqual(1);
      expect(store.loadDeletionRecovery()).assertEqual(undefined);
    });
    it('restores pending identity even when session removal changed memory before its flush failed', 0, async () => {
      const storage = new FailingDeletionStorage();
      const store = new AuthSessionStore(storage);
      store.save({ uid: 'session-test', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const first = new AuthController({ provider: provider, store: store });
      first.restore();
      storage.failRemoveKey = SESSION_STORAGE_KEY;
      storage.mutateBeforeRemoveFailure = true;
      expect(await first.deleteAccount(() => {})).assertFalse();
      expect(store.load()).assertEqual(undefined);
      expect(store.loadDeletionPending()!.uid).assertEqual('session-test');
      const restarted = new AuthController({ provider: provider, store: new AuthSessionStore(storage) });
      expect(restarted.restore()!.uid).assertEqual('session-test');
      expect(await restarted.deleteAccount(() => {})).assertTrue();
      expect(provider.deleteCalls).assertEqual(1);
    });
    it('retries the final deletion-marker removal after restart and preserves the local-owner bypass', 0, async () => {
      const storage = new FailingDeletionStorage();
      const store = new AuthSessionStore(storage);
      store.save(BACKDOOR_SESSION);
      const provider = new FakeAuthProvider();
      const first = new AuthController({ provider: provider, store: store });
      first.restore();
      storage.failRemoveKey = DELETION_PENDING_STORAGE_KEY;
      expect(await first.deleteAccount(() => {})).assertFalse();
      const restarted = new AuthController({ provider: provider, store: new AuthSessionStore(storage) });
      expect(restarted.restore()!.uid).assertEqual(BACKDOOR_SESSION.uid);
      expect(await restarted.deleteAccount(() => {})).assertTrue();
      expect(provider.deleteCalls).assertEqual(0);
      expect(restarted.restore()).assertEqual(undefined);
    });
    it('rejects duplicate taps while the remote deletion request is in flight', 0, async () => {
      const store = new AuthSessionStore(new MapKVStorage());
      store.save({ uid: 'concurrent-test', email: 'test@example.com', provider: 'agc' });
      const provider = new FakeAuthProvider();
      const controller = new AuthController({ provider: provider, store: store });
      controller.restore();
      let cleanupCalls = 0;
      const pending = controller.deleteAccount(() => { cleanupCalls += 1; });
      expect(await controller.deleteAccount(() => { cleanupCalls += 1; })).assertFalse();
      expect(await pending).assertTrue();
      expect(provider.deleteCalls).assertEqual(1);
      expect(cleanupCalls).assertEqual(1);
    });
    it('restore signs out when nothing is persisted', 0, () => {
      const controller = newController(new MapKVStorage());
      expect(controller.restore()).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('signedOut');
    });

    it('the owner backdoor signs in a persistent local session without any provider call', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();

      const session = await controller.submitEmail(BACKDOOR_EMAIL);
      expect(session).assertEqual(BACKDOOR_SESSION);
      expect(controller.getPhase()).assertEqual('signedIn');
      expect(controller.getSession()!.provider).assertEqual('local');
      expect(provider.codesSentTo('milo')).assertEqual(0);
    });

    it('the backdoor ignores case and surrounding whitespace', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      const session = await controller.submitEmail('  Milo  ');
      expect(session !== undefined).assertTrue();
      expect(controller.getPhase()).assertEqual('signedIn');
    });

    it('the backdoor session survives a restart via restore', 0, async () => {
      const storage = new MapKVStorage();
      const first = newController(storage);
      first.restore();
      await first.submitEmail(BACKDOOR_EMAIL);

      const second = newController(storage);
      const restored = second.restore();
      expect(restored !== undefined).assertTrue();
      expect(restored!.uid).assertEqual(BACKDOOR_SESSION.uid);
      expect(second.getPhase()).assertEqual('signedIn');
    });

    it('rejects malformed emails before contacting the provider', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();

      const session = await controller.submitEmail('not-an-email');
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('signedOut');
      expect(controller.getError()!.reason).assertEqual('invalid-email');
      expect(provider.codesSentTo('not-an-email')).assertEqual(0);
    });

    it('walks the email → code happy path and persists the session', 0, async () => {
      const storage = new MapKVStorage();
      const controller = newController(storage);
      controller.restore();

      const pending = await controller.submitEmail('owner@milo.app');
      expect(pending).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');

      const session = await controller.submitCode(FAKE_AUTH_CODE);
      expect(session !== undefined).assertTrue();
      expect(session!.email).assertEqual('owner@milo.app');
      expect(session!.provider).assertEqual('agc');
      expect(controller.getPhase()).assertEqual('signedIn');

      const restored = newController(storage).restore();
      expect(restored !== undefined).assertTrue();
      expect(restored!.uid).assertEqual('agc-owner@milo.app');
    });

    it('keeps the code step on a wrong verification code', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app');

      const session = await controller.submitCode('111111');
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(controller.getError()!.reason).assertEqual('invalid-code');
    });

    it('rejects an empty code without calling the provider', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app');

      const session = await controller.submitCode('   ');
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(controller.getError()!.reason).assertEqual('invalid-code');
    });

    it('submitCode is a no-op outside the awaitingCode phase', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      const session = await controller.submitCode(FAKE_AUTH_CODE);
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('signedOut');
    });

    it('backToEmail returns from the code step and clears the error', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app');
      await controller.submitCode('wrong');

      controller.backToEmail();
      expect(controller.getPhase()).assertEqual('signedOut');
      expect(controller.getError()).assertEqual(undefined);
    });

    it('signOut clears the persisted session and returns to the gate', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();
      await controller.submitEmail('owner@milo.app');
      await controller.submitCode(FAKE_AUTH_CODE);

      await controller.signOut();
      expect(controller.getPhase()).assertEqual('signedOut');
      expect(controller.getSession()).assertEqual(undefined);
      expect(provider.signOutCallCount()).assertEqual(1);
      expect(newController(storage).restore()).assertEqual(undefined);
    });

    it('signOut of a local backdoor session never touches the provider', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();
      await controller.submitEmail(BACKDOOR_EMAIL);

      await controller.signOut();
      expect(provider.signOutCallCount()).assertEqual(0);
      expect(newController(storage).restore()).assertEqual(undefined);
    });

    it('a real email like milo@example.com is not treated as the backdoor', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      const session = await controller.submitEmail('milo@example.com');
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');
    });

    it('prevents overlapping sends and password login while a code is being sent', 0, async () => {
      const provider = new RecoverableAuthProvider();
      const controller = new AuthController({ provider: provider, store: new AuthSessionStore(new MapKVStorage()) });
      controller.restore();

      const firstSend = controller.submitEmail('owner@milo.app');
      const duplicateSend = controller.submitEmail('other@milo.app');
      const passwordLogin = controller.submitPassword(BACKDOOR_EMAIL, '');
      await firstSend;
      await duplicateSend;
      await passwordLogin;

      expect(provider.sendCalls).assertEqual(1);
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(controller.getSession()).assertEqual(undefined);
      const session = await controller.submitCode(FAKE_AUTH_CODE);
      expect(session!.email).assertEqual('owner@milo.app');
    });

    it('waits sixty seconds before resending and can reopen the existing code form', 0, async () => {
      let now = 1000;
      const provider = new RecoverableAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(new MapKVStorage()),
        now: () => now,
      });
      controller.restore();
      await controller.submitEmail('owner@milo.app');
      expect(controller.getResendSeconds('OWNER@milo.app')).assertEqual(60);
      expect(controller.getResendSeconds('other@milo.app')).assertEqual(0);
      controller.backToEmail();
      await controller.submitEmail('owner@milo.app');
      expect(provider.sendCalls).assertEqual(1);
      expect(controller.getPhase()).assertEqual('awaitingCode');

      now = 2500;
      expect(controller.getResendSeconds('owner@milo.app')).assertEqual(59);
      now = 61000;
      await controller.submitEmail('owner@milo.app');
      expect(provider.sendCalls).assertEqual(2);
      expect(controller.getResendSeconds('owner@milo.app')).assertEqual(60);
    });

    it('a failed resend leaves the previous code usable', 0, async () => {
      let now = 0;
      const provider = new RecoverableAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(new MapKVStorage()),
        now: () => now,
      });
      controller.restore();
      await controller.submitEmail('owner@milo.app');
      now = 60000;
      provider.failSending = true;
      await controller.submitEmail('owner@milo.app');
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(controller.getError()!.reason).assertEqual('network');
      expect(controller.getResendSeconds('owner@milo.app')).assertEqual(0);

      const session = await controller.submitCode(FAKE_AUTH_CODE);
      expect(session!.email).assertEqual('owner@milo.app');
    });
  });
}

function authSessionStoreSuite() {
  describe('authSessionStoreTest', () => {
    it('round-trips a session', 0, () => {
      const storage = new MapKVStorage();
      const store = new AuthSessionStore(storage);
      store.save({ uid: 'u1', email: 'a@b.com', provider: 'agc' });
      const loaded = new AuthSessionStore(storage).load();
      expect(loaded !== undefined).assertTrue();
      expect(loaded!.uid).assertEqual('u1');
      expect(loaded!.email).assertEqual('a@b.com');
      expect(loaded!.provider).assertEqual('agc');
    });

    it('clear removes the persisted session', 0, () => {
      const storage = new MapKVStorage();
      const store = new AuthSessionStore(storage);
      store.save({ uid: 'u1', email: 'a@b.com', provider: 'local' });
      store.clear();
      expect(store.load()).assertEqual(undefined);
    });

    it('returns undefined for malformed payloads instead of throwing', 0, () => {
      const storage = new MapKVStorage();
      storage.hydrate(SESSION_STORAGE_KEY, '{broken');
      expect(new AuthSessionStore(storage).load()).assertEqual(undefined);

      const futureVersion: RawSessionEnvelope = { schemaVersion: 99 };
      storage.hydrate(SESSION_STORAGE_KEY, JSON.stringify(futureVersion));
      expect(new AuthSessionStore(storage).load()).assertEqual(undefined);

      const badProvider: RawSessionEnvelope = {
        schemaVersion: 1,
        session: { uid: 'x', email: 'y', provider: 'nope' },
      };
      storage.hydrate(SESSION_STORAGE_KEY, JSON.stringify(badProvider));
      expect(new AuthSessionStore(storage).load()).assertEqual(undefined);

      const blankUid: RawSessionEnvelope = {
        schemaVersion: 1,
        session: { uid: '', email: 'y', provider: 'agc' },
      };
      storage.hydrate(SESSION_STORAGE_KEY, JSON.stringify(blankUid));
      expect(new AuthSessionStore(storage).load()).assertEqual(undefined);
    });

    it('parseSession tolerates blank and null payloads', 0, () => {
      expect(parseSession('')).assertEqual(undefined);
      expect(parseSession('null')).assertEqual(undefined);
    });
  });
}

function emailValidationSuite() {
  describe('emailValidationTest', () => {
    it('accepts ordinary addresses', 0, () => {
      expect(isValidEmail('owner@milo.app')).assertTrue();
      expect(isValidEmail('  owner@milo.app  ')).assertTrue();
      expect(isValidEmail('a.b+c@sub.example.com')).assertTrue();
    });

    it('rejects malformed addresses', 0, () => {
      expect(isValidEmail('')).assertFalse();
      expect(isValidEmail('milo')).assertFalse();
      expect(isValidEmail('a@')).assertFalse();
      expect(isValidEmail('@b.com')).assertFalse();
      expect(isValidEmail('a@b')).assertFalse();
      expect(isValidEmail('a@.com')).assertFalse();
      expect(isValidEmail('a@b.')).assertFalse();
      expect(isValidEmail('a@@b.com')).assertFalse();
      expect(isValidEmail('a b@example.com')).assertFalse();
      expect(isValidEmail('a@exa mple.com')).assertFalse();
    });

    it('validates complete numeric codes and consistent password bounds', 0, () => {
      expect(isValidVerificationCode('123456')).assertTrue();
      expect(isValidVerificationCode(' 123456 ')).assertTrue();
      expect(isValidVerificationCode('12345')).assertFalse();
      expect(isValidVerificationCode('1234567')).assertFalse();
      expect(isValidVerificationCode('abcdef')).assertFalse();
      expect(isValidPassword('my passphrase')).assertTrue();
      expect(isValidPassword(' hunter22')).assertFalse();
      expect(isValidPassword('hunter22 ')).assertFalse();
      expect(isValidPassword('12345')).assertFalse();
      expect(isValidPassword('a'.repeat(33))).assertFalse();
    });
  });
}

function passwordFlowSuite() {
  describe('passwordFlowTest', () => {
    it('registration with a password stores it for later password login', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();

      await controller.submitEmail('owner@milo.app');
      const session = await controller.submitCode(FAKE_AUTH_CODE, 'hunter22');
      expect(session !== undefined).assertTrue();
      expect(provider.passwordFor('owner@milo.app')).assertEqual('hunter22');
    });

    it('registration rejects a weak password client-side', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app');

      const session = await controller.submitCode(FAKE_AUTH_CODE, '123');
      expect(session).assertEqual(undefined);
      expect(controller.getError()!.reason).assertEqual('invalid-password');
      expect(controller.getPhase()).assertEqual('awaitingCode');
    });

    it('password login happy path persists the session', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();
      await provider.signIn('owner@milo.app', FAKE_AUTH_CODE, 'hunter22');

      const session = await controller.submitPassword('owner@milo.app', 'hunter22');
      expect(session !== undefined).assertTrue();
      expect(controller.getPhase()).assertEqual('signedIn');
      expect(new AuthSessionStore(storage).load()!.email).assertEqual('owner@milo.app');
    });

    it('wrong password keeps the user signed out with a typed error', 0, async () => {
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(new MapKVStorage()),
      });
      controller.restore();
      await provider.signIn('owner@milo.app', FAKE_AUTH_CODE, 'hunter22');

      const session = await controller.submitPassword('owner@milo.app', 'wrong-password');
      expect(session).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('signedOut');
      expect(controller.getError()!.reason).assertEqual('wrong-password');
    });

    it('password login without a stored password explains the code fallback', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();

      const session = await controller.submitPassword('owner@milo.app', 'hunter22');
      expect(session).assertEqual(undefined);
      expect(controller.getError()!.reason).assertEqual('password-not-set');
    });

    it('the backdoor works in password mode too', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();

      const session = await controller.submitPassword(BACKDOOR_EMAIL, 'anything');
      expect(session).assertEqual(BACKDOOR_SESSION);
      expect(controller.getPhase()).assertEqual('signedIn');
    });

    it('password login validates format before hitting the provider', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();

      const session = await controller.submitPassword('owner@milo.app', '123');
      expect(session).assertEqual(undefined);
      expect(controller.getError()!.reason).assertEqual('invalid-password');
    });

    it('forgot-password flow: reset code → new password → auto sign-in', 0, async () => {
      const storage = new MapKVStorage();
      const provider = new FakeAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(storage),
      });
      controller.restore();
      await provider.signIn('owner@milo.app', FAKE_AUTH_CODE, 'old-pass-1');

      const pending = await controller.submitEmail('owner@milo.app', 'reset-password');
      expect(pending).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(provider.lastPurpose()).assertEqual('reset-password');

      const session = await controller.submitReset(FAKE_AUTH_CODE, 'new-pass-22');
      expect(session !== undefined).assertTrue();
      expect(controller.getPhase()).assertEqual('signedIn');
      expect(provider.passwordFor('owner@milo.app')).assertEqual('new-pass-22');
      expect(new AuthSessionStore(storage).load()!.email).assertEqual('owner@milo.app');
    });

    it('submitReset is refused outside the reset flow', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app');

      const session = await controller.submitReset(FAKE_AUTH_CODE, 'new-pass-22');
      expect(session).assertEqual(undefined);
    });

    it('reset with a wrong code stays on the reset step', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app', 'reset-password');

      const session = await controller.submitReset('999999', 'new-pass-22');
      expect(session).assertEqual(undefined);
      expect(controller.getError()!.reason).assertEqual('invalid-code');
      expect(controller.getPhase()).assertEqual('awaitingCode');
    });

    it('a password-reset code cannot be consumed as an ordinary sign-in code', 0, async () => {
      const controller = newController(new MapKVStorage());
      controller.restore();
      await controller.submitEmail('owner@milo.app', 'reset-password');
      expect(await controller.submitCode(FAKE_AUTH_CODE)).assertEqual(undefined);
      expect(controller.getPhase()).assertEqual('awaitingCode');
      expect(controller.getSession()).assertEqual(undefined);
    });

    it('reset remains usable after a failed resend', 0, async () => {
      let now = 0;
      const provider = new RecoverableAuthProvider();
      const controller = new AuthController({
        provider: provider,
        store: new AuthSessionStore(new MapKVStorage()),
        now: () => now,
      });
      controller.restore();
      await controller.submitEmail('owner@milo.app', 'reset-password');
      now = 60000;
      provider.failSending = true;
      await controller.submitEmail('owner@milo.app', 'reset-password');
      expect(controller.getPhase()).assertEqual('awaitingCode');
      const session = await controller.submitReset(FAKE_AUTH_CODE, 'new-pass-22');
      expect(session!.email).assertEqual('owner@milo.app');
    });

    it('a successful reset followed by failed login returns to password sign-in', 0, async () => {
      const provider = new RecoverableAuthProvider();
      const controller = new AuthController({ provider: provider, store: new AuthSessionStore(new MapKVStorage()) });
      controller.restore();
      await controller.submitEmail('owner@milo.app', 'reset-password');
      provider.failPasswordLogin = true;
      expect(await controller.submitReset(FAKE_AUTH_CODE, 'new-pass-22')).assertEqual(undefined);
      expect(provider.passwordFor('owner@milo.app')).assertEqual('new-pass-22');
      expect(controller.getPhase()).assertEqual('signedOut');
      expect(controller.getError()!.message).assertEqual('密码已更新，请用新密码登录。');

      provider.failPasswordLogin = false;
      const session = await controller.submitPassword('owner@milo.app', 'new-pass-22');
      expect(session!.email).assertEqual('owner@milo.app');
      expect(controller.getPhase()).assertEqual('signedIn');
    });
  });
}

export default function authControllerTest() {
  authControllerSuite();
  authSessionStoreSuite();
  emailValidationSuite();
  passwordFlowSuite();
}
