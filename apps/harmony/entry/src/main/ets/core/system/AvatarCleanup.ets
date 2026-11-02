import { type KVStorage } from '../data/KVStorage';

/** Keep the pointer until its owned file is removed, so a failed unlink retries. */
export function clearAvatarRecord(storage: KVStorage, key: string, filesDir: string,
  removeFile: (path: string) => void): void {
  const path = storage.read(key) ?? '';
  const prefix = `${filesDir}/`;
  if (path.startsWith(prefix) && /^avatar-[0-9]+\.img$/.test(path.substring(prefix.length))) {
    removeFile(path);
  }
  storage.remove(key);
}
