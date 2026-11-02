import { preferences } from '@kit.ArkData';

/**
 * Synchronous key/value storage contract. Repository tests use MapKVStorage;
 * the release UI uses PreferencesKVStorage so entries survive app restarts.
 */
export interface KVStorage {
  read(key: string): string | undefined;
  write(key: string, value: string): void;
  remove(key: string): void;
}

/**
 * In-memory adapter used by Hypium tests. Not intended for production.
 * Exposes a `hydrate` helper so a test can pre-populate a corrupt payload.
 */
export class MapKVStorage implements KVStorage {
  private store: Map<string, string> = new Map<string, string>();

  read(key: string): string | undefined {
    return this.store.get(key);
  }

  write(key: string, value: string): void {
    this.store.set(key, value);
  }

  remove(key: string): void {
    this.store.delete(key);
  }

  /** Seed the store with arbitrary bytes to simulate a corrupt legacy record. */
  hydrate(key: string, value: string): void {
    this.store.set(key, value);
  }
}

/** App-private, flushed Preferences store for diary entries and draft state. */
export class PreferencesKVStorage implements KVStorage {
  private store: preferences.Preferences;

  constructor(context: Context, name: string = 'milo_local_diary') {
    this.store = preferences.getPreferencesSync(context, { name: name });
  }

  read(key: string): string | undefined {
    const value = this.store.getSync(key, '');
    return typeof value === 'string' && value.length > 0 ? value : undefined;
  }

  write(key: string, value: string): void {
    this.store.putSync(key, value);
    this.store.flushSync();
  }

  remove(key: string): void {
    this.store.deleteSync(key);
    this.store.flushSync();
  }
}
