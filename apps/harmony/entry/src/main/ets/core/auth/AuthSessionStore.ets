import { type AuthSession, type AuthProviderKind } from './AuthProvider';
import { type KVStorage } from '../data/KVStorage';

/** Persisted shape for the signed-in session. */
export interface SessionEnvelope {
  schemaVersion: 1;
  session: PersistedSession;
  deletionPhase?: DeletionPhase;
}

export type DeletionPhase = 'requested' | 'confirmed-deleted';
export interface DeletionRecovery {
  phase: DeletionPhase;
  session: AuthSession;
}

interface PersistedSession {
  uid: string;
  email: string;
  provider: string;
}

export const SESSION_STORAGE_KEY = 'milo.auth.session.v1';
/** Separate recovery journal: survives removing the ordinary login snapshot. */
export const DELETION_PENDING_STORAGE_KEY = 'milo.auth.deletion-pending.v1';
export const SESSION_SCHEMA_VERSION = 1;

const VALID_PROVIDERS: ReadonlyArray<AuthProviderKind> = ['agc', 'local'];

/**
 * KVStorage-backed session persistence. Survives app restarts so the app
 * stays fully offline after the first successful login. Phase 2 moves the
 * AGC token itself into Asset Store Kit; this envelope only keeps the
 * identity snapshot.
 */
export class AuthSessionStore {
  private storage: KVStorage;

  constructor(storage: KVStorage) {
    this.storage = storage;
  }

  save(session: AuthSession): void {
    const envelope: SessionEnvelope = {
      schemaVersion: SESSION_SCHEMA_VERSION,
      session: {
        uid: session.uid,
        email: session.email,
        provider: session.provider,
      },
    };
    this.storage.write(SESSION_STORAGE_KEY, JSON.stringify(envelope));
  }

  /** Returns `undefined` when nothing is saved or the payload is corrupt. Never throws. */
  load(): AuthSession | undefined {
    const raw = this.storage.read(SESSION_STORAGE_KEY);
    if (raw === undefined) {
      return undefined;
    }
    return parseSession(raw);
  }

  clear(): void {
    this.storage.remove(SESSION_STORAGE_KEY);
  }

  /** Written after remote success and before any app-local data is removed. */
  saveDeletionPending(session: AuthSession): void {
    this.saveDeletionRecord(session, 'confirmed-deleted');
  }

  /** Must flush before deleteUser: a restart must not erase an unknown result. */
  saveDeletionRequested(session: AuthSession): void {
    this.saveDeletionRecord(session, 'requested');
  }

  private saveDeletionRecord(session: AuthSession, phase: DeletionPhase): void {
    const envelope: SessionEnvelope = {
      schemaVersion: SESSION_SCHEMA_VERSION,
      session: { uid: session.uid, email: session.email, provider: session.provider },
      deletionPhase: phase,
    };
    this.storage.write(DELETION_PENDING_STORAGE_KEY, JSON.stringify(envelope));
  }

  loadDeletionPending(): AuthSession | undefined {
    return this.loadDeletionRecovery()?.session;
  }

  loadDeletionRecovery(): DeletionRecovery | undefined {
    const raw = this.storage.read(DELETION_PENDING_STORAGE_KEY);
    if (raw === undefined) return undefined;
    const session = parseSession(raw);
    if (session === undefined) return undefined;
    const record = JSON.parse(raw) as Record<string, Object>;
    const phase = record['deletionPhase'];
    // The previous recovery format was only written after remote success.
    if (phase === undefined || phase === 'confirmed-deleted') return { phase: 'confirmed-deleted', session: session };
    // Unknown future phase values must never be treated as remote success.
    return { phase: 'requested', session: session };
  }

  /** Last deletion step, after local data and the ordinary session are gone. */
  clearDeletionPending(): void {
    this.storage.remove(DELETION_PENDING_STORAGE_KEY);
  }
}

export function parseSession(raw: string): AuthSession | undefined {
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch {
    return undefined;
  }
  if (typeof parsed !== 'object' || parsed === null) {
    return undefined;
  }
  const record = parsed as Record<string, Object>;
  if (record['schemaVersion'] !== SESSION_SCHEMA_VERSION) {
    return undefined;
  }
  const sessionValue = record['session'];
  if (typeof sessionValue !== 'object' || sessionValue === null) {
    return undefined;
  }
  const session = sessionValue as Record<string, Object>;
  const uid = session['uid'];
  const email = session['email'];
  const provider = session['provider'];
  if (typeof uid !== 'string' || uid.length === 0) {
    return undefined;
  }
  if (typeof email !== 'string' || email.length === 0) {
    return undefined;
  }
  if (typeof provider !== 'string' || VALID_PROVIDERS.indexOf(provider as AuthProviderKind) < 0) {
    return undefined;
  }
  return {
    uid: uid,
    email: email,
    provider: provider as AuthProviderKind,
  };
}
