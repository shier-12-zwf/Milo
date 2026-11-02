import {
  type DiaryEntry,
  type MoodId,
  type MoodState,
  type StickerTemplateId,
  DEFAULT_STICKER_TEMPLATE,
  VALID_STICKER_TEMPLATES,
} from '../model/Domain';
import { type KVStorage } from './KVStorage';

/** Persisted shape; bump `schemaVersion` whenever the layout changes. */
export interface EntryEnvelope {
  schemaVersion: 1;
  entries: DiaryEntry[];
}

export const ENTRIES_STORAGE_KEY = 'milo.entries.v1';
export const ENTRY_SCHEMA_VERSION = 1;

export class EntryRepository {
  private storage: KVStorage;
  private cache: DiaryEntry[] | undefined;

  constructor(storage: KVStorage) {
    this.storage = storage;
  }

  /** Replace the in-memory cache with a freshly-read payload. */
  private refresh(): DiaryEntry[] {
    if (this.cache !== undefined) {
      return this.cache;
    }
    const raw = this.storage.read(ENTRIES_STORAGE_KEY);
    if (raw === undefined) {
      this.cache = [];
      return this.cache;
    }
    this.cache = parseEnvelope(raw);
    return this.cache;
  }

  /** Persist the current cache, then notify any listeners. */
  private flush(): void {
    if (this.cache === undefined) {
      return;
    }
    const envelope: EntryEnvelope = {
      schemaVersion: ENTRY_SCHEMA_VERSION,
      entries: this.cache.slice(),
    };
    this.storage.write(ENTRIES_STORAGE_KEY, JSON.stringify(envelope));
  }

  /** Return every saved entry, newest first. Tolerates malformed records. */
  list(): DiaryEntry[] {
    return this.refresh().slice();
  }

  /** Clear persisted entries and their in-memory cache after account deletion. */
  clear(): void {
    this.storage.remove(ENTRIES_STORAGE_KEY);
    this.cache = [];
  }

  /** Look up a single entry by id; returns `undefined` when missing. */
  get(id: string): DiaryEntry | undefined {
    const all = this.refresh();
    for (let index = 0; index < all.length; index += 1) {
      if (all[index].id === id) {
        return all[index];
      }
    }
    return undefined;
  }

  /** Insert or replace; callers should provide a fresh `id`. */
  save(entry: DiaryEntry): void {
    const all = this.refresh();
    const filtered = all.filter((existing) => existing.id !== entry.id);
    filtered.unshift(entry);
    this.cache = filtered;
    this.flush();
  }

  /** Patch an entry in place; missing ids are a no-op. */
  update(id: string, patch: Partial<DiaryEntry>): void {
    const all = this.refresh();
    let mutated = false;
    const next: DiaryEntry[] = [];
    for (let index = 0; index < all.length; index += 1) {
      const existing = all[index];
      if (existing.id === id) {
        mutated = true;
        next.push(mergeEntry(existing, patch));
      } else {
        next.push(existing);
      }
    }
    if (!mutated) {
      return;
    }
    this.cache = next;
    this.flush();
  }

  /** Remove by id; missing ids are a no-op. */
  remove(id: string): void {
    const all = this.refresh();
    const filtered: DiaryEntry[] = [];
    let changed = false;
    for (let index = 0; index < all.length; index += 1) {
      const existing = all[index];
      if (existing.id === id) {
        changed = true;
      } else {
        filtered.push(existing);
      }
    }
    if (!changed) {
      return;
    }
    this.cache = filtered;
    this.flush();
  }

  /** Test seam: forget the cached payload so the next read re-parses storage. */
  invalidate(): void {
    this.cache = undefined;
  }
}

function mergeEntry(base: DiaryEntry, patch: Partial<DiaryEntry>): DiaryEntry {
  const next: DiaryEntry = {
    id: base.id,
    createdAt: base.createdAt,
    kind: base.kind,
    mood: base.mood,
    diaryEnabled: base.diaryEnabled,
  };
  if (base.timeMark !== undefined) {
    next.timeMark = base.timeMark;
  }
  if (base.note !== undefined) {
    next.note = base.note;
  }
  if (base.diary !== undefined) {
    next.diary = base.diary;
  }
  if (base.transcript !== undefined) {
    next.transcript = base.transcript;
  }
  if (base.stickerTemplate !== undefined) {
    next.stickerTemplate = normalizeEntryTemplate(base.stickerTemplate);
  }
  if (patch.mood !== undefined) {
    next.mood = patch.mood;
  }
  if (patch.createdAt !== undefined) {
    next.createdAt = patch.createdAt;
  }
  if (patch.kind !== undefined) {
    next.kind = patch.kind;
  }
  if (patch.diaryEnabled !== undefined) {
    next.diaryEnabled = patch.diaryEnabled;
  }
  if (patch.timeMark !== undefined) {
    next.timeMark = patch.timeMark;
  }
  if (patch.note !== undefined) {
    next.note = patch.note;
  }
  if (patch.diary !== undefined) {
    next.diary = patch.diary;
  }
  if (patch.transcript !== undefined) {
    next.transcript = patch.transcript;
  }
  if (patch.stickerTemplate !== undefined) {
    next.stickerTemplate = normalizeEntryTemplate(patch.stickerTemplate);
  }
  return next;
}

/** Unknown templates fall back without discarding the user's diary. */
function normalizeEntryTemplate(value: Object): StickerTemplateId {
  for (let index = 0; index < VALID_STICKER_TEMPLATES.length; index += 1) {
    if (value === VALID_STICKER_TEMPLATES[index]) {
      return VALID_STICKER_TEMPLATES[index];
    }
  }
  return DEFAULT_STICKER_TEMPLATE;
}

/**
 * Decode a stored payload. Returns an empty list when the payload is missing,
 * malformed, or carries an unrecognised schema version. Never throws.
 */
export function parseEnvelope(raw: string): DiaryEntry[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch {
    return [];
  }
  const envelope = validateEnvelope(parsed);
  if (envelope === undefined) {
    return [];
  }
  return envelope.entries;
}

function validateEnvelope(value: Object): EntryEnvelope | undefined {
  if (typeof value !== 'object' || value === null) {
    return undefined;
  }
  const record = value as Record<string, Object>;
  if (record['schemaVersion'] !== ENTRY_SCHEMA_VERSION) {
    return undefined;
  }
  const entriesRaw = record['entries'];
  if (!Array.isArray(entriesRaw)) {
    return undefined;
  }
  const entries: DiaryEntry[] = [];
  for (let index = 0; index < entriesRaw.length; index += 1) {
    const candidate = validateDiaryEntry(entriesRaw[index]);
    if (candidate !== undefined) {
      entries.push(candidate);
    }
  }
  return { schemaVersion: ENTRY_SCHEMA_VERSION, entries: entries };
}

function validateDiaryEntry(value: Object): DiaryEntry | undefined {
  if (typeof value !== 'object' || value === null) {
    return undefined;
  }
  const record = value as Record<string, Object>;
  if (typeof record['id'] !== 'string' || record['id'].length === 0) {
    return undefined;
  }
  if (typeof record['createdAt'] !== 'number') {
    return undefined;
  }
  if (record['kind'] !== 'now' && record['kind'] !== 'past') {
    return undefined;
  }
  if (typeof record['diaryEnabled'] !== 'boolean') {
    return undefined;
  }
  const mood = validateMoodState(record['mood']);
  if (mood === undefined) {
    return undefined;
  }
  const entry: DiaryEntry = {
    id: record['id'] as string,
    createdAt: record['createdAt'] as number,
    kind: record['kind'] as 'now' | 'past',
    mood: mood,
    diaryEnabled: record['diaryEnabled'] as boolean,
  };
  if (record['timeMark'] !== undefined) {
    if (typeof record['timeMark'] !== 'string') {
      return undefined;
    }
    entry.timeMark = record['timeMark'];
  }
  if (record['note'] !== undefined) {
    if (typeof record['note'] !== 'string') {
      return undefined;
    }
    entry.note = record['note'];
  }
  if (record['diary'] !== undefined) {
    if (typeof record['diary'] !== 'string') {
      return undefined;
    }
    entry.diary = record['diary'];
  }
  if (record['transcript'] !== undefined) {
    const transcript = validateTranscript(record['transcript']);
    if (transcript === undefined) {
      return undefined;
    }
    entry.transcript = transcript;
  }
  if (record['stickerTemplate'] !== undefined) {
    entry.stickerTemplate = normalizeEntryTemplate(record['stickerTemplate']);
  }
  return entry;
}

function validateMoodState(value: Object): MoodState | undefined {
  if (typeof value !== 'object' || value === null) {
    return undefined;
  }
  const record = value as Record<string, Object>;
  if (typeof record['valence'] !== 'number') {
    return undefined;
  }
  if (!Array.isArray(record['labels'])) {
    return undefined;
  }
  const labels: string[] = [];
  for (let index = 0; index < record['labels'].length; index += 1) {
    const label = record['labels'][index] as Object;
    if (typeof label !== 'string') {
      return undefined;
    }
    labels.push(label);
  }
  const mood: MoodState = { valence: record['valence'] as number, labels: labels };
  if (record['emotionId'] !== undefined) {
    if (typeof record['emotionId'] !== 'string') {
      return undefined;
    }
    mood.emotionId = record['emotionId'] as MoodId;
  }
  return mood;
}

interface PersistedTranscriptMessage {
  role: 'user' | 'ai';
  text: string;
  ts: number;
}

function validateTranscript(value: Object): Array<PersistedTranscriptMessage> | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  const out: PersistedTranscriptMessage[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const item = value[index] as Object;
    if (typeof item !== 'object' || item === null) {
      return undefined;
    }
    const record = item as Record<string, Object>;
    if (typeof record['text'] !== 'string' || typeof record['ts'] !== 'number') {
      return undefined;
    }
    if (record['role'] !== 'user' && record['role'] !== 'ai') {
      return undefined;
    }
    const message: PersistedTranscriptMessage = {
      role: record['role'] as 'user' | 'ai',
      text: record['text'] as string,
      ts: record['ts'] as number,
    };
    out.push(message);
  }
  return out;
}
