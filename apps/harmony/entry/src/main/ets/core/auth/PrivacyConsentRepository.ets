import { type KVStorage } from '../data/KVStorage';

export const PRIVACY_POLICY_VERSION = '2026-10-11';
export const PRIVACY_CONSENT_KEY = 'milo.privacy.accepted-version';

/** A missing or older consent never permits SDK initialization. Diary data is untouched. */
export class PrivacyConsentRepository {
  private storage: KVStorage;

  constructor(storage: KVStorage) {
    this.storage = storage;
  }

  hasAccepted(): boolean {
    try { return this.storage.read(PRIVACY_CONSENT_KEY) === PRIVACY_POLICY_VERSION; }
    catch { return false; }
  }

  accept(): void {
    this.storage.write(PRIVACY_CONSENT_KEY, PRIVACY_POLICY_VERSION);
  }
}
