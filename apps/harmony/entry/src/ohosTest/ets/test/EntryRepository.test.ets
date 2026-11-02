import { describe, expect, it } from '@ohos/hypium';
import {
  EntryRepository,
  parseEnvelope,
  ENTRIES_STORAGE_KEY,
} from '../../../main/ets/core/data/EntryRepository';
import {
  RecallSessionRepository,
  parseDraft,
  DRAFT_STORAGE_KEY,
} from '../../../main/ets/core/data/RecallSessionRepository';
import { MapKVStorage } from '../../../main/ets/core/data/KVStorage';
import { type DiaryEntry, type StickerTemplateId, DEFAULT_STICKER_TEMPLATE } from '../../../main/ets/core/model/Domain';
import {
  initialRecallState,
  RecallEvents,
  transition,
  type RecallState,
} from '../../../main/ets/core/flow/RecallMachine';

interface EntryPatch {
  diary?: string;
  diaryEnabled?: boolean;
  stickerTemplate?: StickerTemplateId;
}

interface RawEntryRow {
  id?: string;
  createdAt?: number;
  kind?: string;
  mood?: RawMood;
  diaryEnabled?: boolean;
  diary?: string;
  stickerTemplate?: string | number;
}

interface RawEnvelope {
  schemaVersion?: number;
  entries?: Array<RawEntryRow | null>;
}

interface RawChatMessage {
  role?: string;
  text?: string;
  ts?: number;
}

interface RawDraftDraft {
  valence?: number;
  labels?: string[];
  diaryEnabled?: boolean;
  transcript?: RawChatMessage[];
}

interface RawDraftState {
  screenName?: string;
  entryId?: string;
  draft?: RawDraftDraft;
}

interface RawDraftEnvelope {
  schemaVersion?: number;
  state?: RawDraftState;
}

interface RawMood {
  valence?: number | string;
  labels?: Array<string | number>;
}

function entry(id: string, kind: 'now' | 'past', createdAt: number, diaryEnabled: boolean): DiaryEntry {
  return {
    id: id,
    createdAt: createdAt,
    kind: kind,
    mood: { valence: 0, labels: ['平静'] },
    diaryEnabled: diaryEnabled,
  };
}

function rawRow(id: string, createdAt: number, kind: string): RawEntryRow {
  const mood: RawMood = { valence: 0, labels: [] };
  return { id: id, createdAt: createdAt, kind: kind, mood: mood, diaryEnabled: true };
}

function rawRowWithBadMood(): RawEntryRow {
  const mood: RawMood = { valence: 'no' };
  return { id: 'bad-mood', createdAt: 1, kind: 'now', mood: mood, diaryEnabled: true };
}

function entryRepositorySuite() {
  describe('entryRepositoryTest', () => {
    it('returns an empty list on a fresh launch', 0, () => {
      const repo = new EntryRepository(new MapKVStorage());
      expect(repo.list().length).assertEqual(0);
    });

    it('persists entries newest-first and round-trips them', 0, () => {
      const storage = new MapKVStorage();
      const repo = new EntryRepository(storage);
      repo.save(entry('a', 'now', 1000, false));
      repo.save(entry('b', 'past', 2000, true));
      repo.save(entry('c', 'now', 3000, true));

      const ids = repo.list().map((item) => item.id);
      expect(ids.join(',')).assertEqual('c,b,a');

      const reread = new EntryRepository(storage).list().map((item) => item.id);
      expect(reread.join(',')).assertEqual('c,b,a');
    });

    it('replaces an entry when saving with an existing id', 0, () => {
      const repo = new EntryRepository(new MapKVStorage());
      repo.save(entry('a', 'now', 1000, false));
      repo.save(entry('a', 'past', 1500, true));
      const all = repo.list();
      expect(all.length).assertEqual(1);
      expect(all[0].kind).assertEqual('past');
      expect(all[0].createdAt).assertEqual(1500);
      expect(all[0].diaryEnabled).assertTrue();
    });

    it('looks up an entry by id and returns undefined when missing', 0, () => {
      const repo = new EntryRepository(new MapKVStorage());
      repo.save(entry('a', 'now', 1000, false));
      expect(repo.get('a') !== undefined).assertTrue();
      expect(repo.get('nope')).assertEqual(undefined);
    });

    it('updates an existing entry without touching others', 0, () => {
      const repo = new EntryRepository(new MapKVStorage());
      repo.save(entry('a', 'now', 1000, false));
      repo.save(entry('b', 'past', 2000, true));
      const patch: EntryPatch = { diary: 'hello world', diaryEnabled: true };
      repo.update('a', patch);
      const a = repo.get('a');
      const b = repo.get('b');
      expect(a !== undefined && b !== undefined).assertTrue();
      expect(a!.diary).assertEqual('hello world');
      expect(a!.diaryEnabled).assertTrue();
      expect(b!.diary === undefined).assertTrue();
    });

    it('keeps the selected card template after invalidating and reopening the repository', 0, () => {
      const storage = new MapKVStorage();
      const repo = new EntryRepository(storage);
      repo.save(entry('a', 'past', 1000, true));
      const patch: EntryPatch = { stickerTemplate: 'orbit-theatre' };
      repo.update('a', patch);
      expect(repo.get('a')!.stickerTemplate).assertEqual('orbit-theatre');

      repo.invalidate();
      expect(repo.get('a')!.stickerTemplate).assertEqual('orbit-theatre');
      expect(new EntryRepository(storage).get('a')!.stickerTemplate).assertEqual('orbit-theatre');
    });

    it('preserves the saved template when editing other diary fields', 0, () => {
      const storage = new MapKVStorage();
      const repo = new EntryRepository(storage);
      const saved = entry('a', 'past', 1000, true);
      saved.stickerTemplate = 'orbit-theatre';
      repo.save(saved);
      repo.invalidate();
      const patch: EntryPatch = { diary: '换个说法，还是同一段回忆。' };
      repo.update('a', patch);

      const loaded = new EntryRepository(storage).get('a');
      expect(loaded!.stickerTemplate).assertEqual('orbit-theatre');
      expect(loaded!.diary).assertEqual(patch.diary);
    });

    it('falls back for unknown templates without losing the entry and keeps legacy records readable', 0, () => {
      const unknown = rawRow('unknown-template', 3000, 'past');
      unknown.stickerTemplate = 'future-template';
      const malformed = rawRow('malformed-template', 2000, 'past');
      malformed.stickerTemplate = 42;
      const legacy = rawRow('legacy', 1000, 'now');
      const envelope: RawEnvelope = { schemaVersion: 1, entries: [unknown, malformed, legacy] };
      const loaded = parseEnvelope(JSON.stringify(envelope));

      expect(loaded.length).assertEqual(3);
      expect(loaded[0].stickerTemplate).assertEqual(DEFAULT_STICKER_TEMPLATE);
      expect(loaded[1].stickerTemplate).assertEqual(DEFAULT_STICKER_TEMPLATE);
      expect(loaded[2].stickerTemplate).assertEqual(undefined);
    });

    it('removes an entry by id and tolerates missing ids', 0, () => {
      const repo = new EntryRepository(new MapKVStorage());
      repo.save(entry('a', 'now', 1000, false));
      repo.save(entry('b', 'past', 2000, true));
      repo.remove('a');
      expect(repo.list().map((item) => item.id).join(',')).assertEqual('b');
      repo.remove('missing');
      expect(repo.list().length).assertEqual(1);
    });

    it('isolates malformed stored payloads and recovers after a write', 0, () => {
      const storage = new MapKVStorage();
      storage.hydrate(ENTRIES_STORAGE_KEY, '{not-json');
      const repo = new EntryRepository(storage);
      expect(repo.list().length).assertEqual(0);

      const blank: RawEnvelope = { entries: [] };
      storage.hydrate(ENTRIES_STORAGE_KEY, JSON.stringify(blank));
      expect(repo.list().length).assertEqual(0);

      const futureRows: Array<RawEntryRow | null> = [rawRow('bad', 1, 'now')];
      const future: RawEnvelope = { schemaVersion: 99, entries: futureRows };
      storage.hydrate(ENTRIES_STORAGE_KEY, JSON.stringify(future));
      const futureRepo = new EntryRepository(storage);
      expect(futureRepo.list().length).assertEqual(0);
      futureRepo.save(entry('a', 'now', 1000, false));
      expect(futureRepo.list().length).assertEqual(1);
    });

    it('drops malformed entries inside an otherwise valid envelope', 0, () => {
      const rows: Array<RawEntryRow | null> = [
        rawRow('ok', 1, 'now'),
        rawRow('bad-kind', 1, 'other'),
        rawRowWithBadMood(),
        null,
        rawRow('', 1, 'now'),
      ];
      const mixed: RawEnvelope = { schemaVersion: 1, entries: rows };
      const storage = new MapKVStorage();
      storage.hydrate(ENTRIES_STORAGE_KEY, JSON.stringify(mixed));
      const repo = new EntryRepository(storage);
      const ids = repo.list().map((item) => item.id);
      expect(ids.join(',')).assertEqual('ok');
    });

    it('parseEnvelope returns [] for every malformed input', 0, () => {
      expect(parseEnvelope('').length).assertEqual(0);
      expect(parseEnvelope('null').length).assertEqual(0);
      const empty: RawEnvelope = {};
      expect(parseEnvelope(JSON.stringify(empty)).length).assertEqual(0);
      const versionOnly: RawEnvelope = { schemaVersion: 1 };
      expect(parseEnvelope(JSON.stringify(versionOnly)).length).assertEqual(0);
      expect(parseEnvelope('[]').length).assertEqual(0);
    });
  });
}

function populatedDraft(): RecallState {
  let state = initialRecallState();
  state = transition(state, RecallEvents.selectMood('calm'));
  state = transition(state, RecallEvents.classify('past'));
  state = transition(state, RecallEvents.setTimeMark('去年夏天'));
  state = transition(state, RecallEvents.appendMessage('user', '在河边', 1700));
  return state;
}

function recallSessionRepositorySuite() {
  describe('recallSessionRepositoryTest', () => {
    it('returns undefined when nothing has been saved', 0, () => {
      const repo = new RecallSessionRepository(new MapKVStorage());
      expect(repo.loadDraft()).assertEqual(undefined);
    });

    it('round-trips a populated draft and preserves its screen + transcript', 0, () => {
      const storage = new MapKVStorage();
      new RecallSessionRepository(storage).saveDraft(populatedDraft());

      const loaded = new RecallSessionRepository(storage).loadDraft();
      expect(loaded !== undefined).assertTrue();
      expect(loaded!.screen.name).assertEqual('chat');
      expect(loaded!.draft.mood.emotionId).assertEqual('calm');
      expect(loaded!.draft.timeMark).assertEqual('去年夏天');
      expect(loaded!.draft.kind).assertEqual('past');
      expect(loaded!.draft.transcript.length).assertEqual(1);
      expect(loaded!.draft.transcript[0].role).assertEqual('user');
      expect(loaded!.draft.transcript[0].text).assertEqual('在河边');
    });

    it('clearDraft removes the persisted draft', 0, () => {
      const storage = new MapKVStorage();
      new RecallSessionRepository(storage).saveDraft(populatedDraft());
      const reader = new RecallSessionRepository(storage);
      reader.clearDraft();
      expect(reader.loadDraft()).assertEqual(undefined);
    });

    it('returns undefined for malformed payloads instead of throwing', 0, () => {
      const storage = new MapKVStorage();
      storage.hydrate(DRAFT_STORAGE_KEY, '{broken');
      expect(new RecallSessionRepository(storage).loadDraft()).assertEqual(undefined);

      const wrongVersion: RawDraftEnvelope = { schemaVersion: 99, state: {} };
      storage.hydrate(DRAFT_STORAGE_KEY, JSON.stringify(wrongVersion));
      expect(new RecallSessionRepository(storage).loadDraft()).assertEqual(undefined);

      const unknownScreen: RawDraftEnvelope = {
        schemaVersion: 1,
        state: {
          screenName: 'orbit',
          draft: { valence: 0, labels: [], diaryEnabled: true, transcript: [] },
        },
      };
      storage.hydrate(DRAFT_STORAGE_KEY, JSON.stringify(unknownScreen));
      expect(new RecallSessionRepository(storage).loadDraft()).assertEqual(undefined);
    });

    it('parseDraft tolerates blank, null, and missing-state envelopes', 0, () => {
      expect(parseDraft('')).assertEqual(undefined);
      expect(parseDraft('null')).assertEqual(undefined);
      const empty: RawDraftEnvelope = {};
      expect(parseDraft(JSON.stringify(empty))).assertEqual(undefined);
      const noState: RawDraftEnvelope = { schemaVersion: 1 };
      expect(parseDraft(JSON.stringify(noState))).assertEqual(undefined);
    });

    it('keeps damaged drafts from hiding previously saved entries', 0, () => {
      const storage = new MapKVStorage();
      const entries = new EntryRepository(storage);
      entries.save(entry('a', 'now', 1000, false));
      storage.hydrate(DRAFT_STORAGE_KEY, '???corrupt???');

      const drafts = new RecallSessionRepository(storage);
      drafts.clearDraft();
      expect(drafts.loadDraft()).assertEqual(undefined);
      expect(entries.list().length).assertEqual(1);
    });
  });
}

export default function entryRepositoryTest() {
  entryRepositorySuite();
  recallSessionRepositorySuite();
}
