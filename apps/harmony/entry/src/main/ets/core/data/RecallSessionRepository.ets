import { Screen, type Draft, type MoodId, type ScreenName, type StickerTemplateId } from '../model/Domain';
import { initialRecallState, type RecallState } from '../flow/RecallMachine';
import { type KVStorage } from './KVStorage';

/** Persisted shape for the in-progress recall draft. */
export interface DraftEnvelope {
  schemaVersion: 1;
  state: PersistedRecallState;
}

interface PersistedRecallState {
  screenName: ScreenName;
  entryId?: string;
  draft: PersistedDraft;
}

interface PersistedDraft {
  valence: number;
  labels: string[];
  emotionId?: string;
  kind?: 'now' | 'past';
  timeMark?: string;
  note?: string;
  diary?: string;
  diaryEnabled: boolean;
  stickerTemplate?: string;
  transcript: PersistedChatMessage[];
  aiEnabled?: boolean;
  inputText?: string;
}

interface PersistedChatMessage {
  role: 'user' | 'ai';
  text: string;
  ts: number;
}

export const DRAFT_STORAGE_KEY = 'milo.recall.draft.v1';
export const DRAFT_SCHEMA_VERSION = 1;

const VALID_KINDS: ReadonlyArray<'now' | 'past'> = ['now', 'past'];
const VALID_ROLES: ReadonlyArray<'user' | 'ai'> = ['user', 'ai'];
const VALID_SCREEN_NAMES: ReadonlyArray<ScreenName> = [
  'home',
  'classify',
  'now-note',
  'past-time',
  'chat',
  'diary',
  'card',
  'timeline',
  'detail',
];

export class RecallSessionRepository {
  private storage: KVStorage;

  constructor(storage: KVStorage) {
    this.storage = storage;
  }

  saveDraft(state: RecallState): void {
    const envelope: DraftEnvelope = {
      schemaVersion: DRAFT_SCHEMA_VERSION,
      state: serialiseState(state),
    };
    this.storage.write(DRAFT_STORAGE_KEY, JSON.stringify(envelope));
  }

  /** Returns `undefined` when nothing is saved, the payload is corrupt, or the
   *  screen name is unrecognised. Never throws. */
  loadDraft(): RecallState | undefined {
    const raw = this.storage.read(DRAFT_STORAGE_KEY);
    if (raw === undefined) {
      return undefined;
    }
    return parseDraft(raw);
  }

  clearDraft(): void {
    this.storage.remove(DRAFT_STORAGE_KEY);
  }
}

function serialiseState(state: RecallState): PersistedRecallState {
  const draft = state.draft;
  const transcript: PersistedChatMessage[] = [];
  for (let index = 0; index < draft.transcript.length; index += 1) {
    const message = draft.transcript[index];
    transcript.push({ role: message.role, text: message.text, ts: message.ts });
  }
  const persisted: PersistedDraft = {
    valence: draft.mood.valence,
    labels: draft.mood.labels.slice(),
    diaryEnabled: draft.diaryEnabled,
    transcript: transcript,
  };
  if (draft.aiEnabled !== undefined) {
    persisted.aiEnabled = draft.aiEnabled;
  }
  if (draft.inputText !== undefined) {
    persisted.inputText = draft.inputText;
  }
  if (draft.mood.emotionId !== undefined) {
    persisted.emotionId = draft.mood.emotionId;
  }
  if (draft.kind !== undefined) {
    persisted.kind = draft.kind;
  }
  if (draft.timeMark !== undefined) {
    persisted.timeMark = draft.timeMark;
  }
  if (draft.note !== undefined) {
    persisted.note = draft.note;
  }
  if (draft.diary !== undefined) {
    persisted.diary = draft.diary;
  }
  if (draft.stickerTemplate !== undefined) {
    persisted.stickerTemplate = draft.stickerTemplate;
  }
  const screen: PersistedRecallState = {
    screenName: state.screen.name,
    draft: persisted,
  };
  if (state.screen.entryId !== undefined) {
    screen.entryId = state.screen.entryId;
  }
  return screen;
}

export function parseDraft(raw: string): RecallState | undefined {
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch {
    return undefined;
  }
  const persisted = validatePersistedState(parsed);
  if (persisted === undefined) {
    return undefined;
  }
  return hydrateState(persisted);
}

function validatePersistedState(value: Object): PersistedRecallState | undefined {
  if (typeof value !== 'object' || value === null) {
    return undefined;
  }
  const record = value as Record<string, Object>;
  if (record['schemaVersion'] !== DRAFT_SCHEMA_VERSION) {
    return undefined;
  }
  const stateValue = record['state'];
  if (typeof stateValue !== 'object' || stateValue === null) {
    return undefined;
  }
  return validateState(stateValue as Object);
}

function validateState(value: Object): PersistedRecallState | undefined {
  const record = value as Record<string, Object>;
  const screenName = record['screenName'];
  if (typeof screenName !== 'string') {
    return undefined;
  }
  if (VALID_SCREEN_NAMES.indexOf(screenName as ScreenName) < 0) {
    return undefined;
  }
  const entryIdRaw = record['entryId'];
  let entryId: string | undefined;
  if (entryIdRaw !== undefined) {
    if (typeof entryIdRaw !== 'string') {
      return undefined;
    }
    entryId = entryIdRaw;
  }
  const draftValue = record['draft'];
  if (typeof draftValue !== 'object' || draftValue === null) {
    return undefined;
  }
  const draft = validateDraft(draftValue as Object);
  if (draft === undefined) {
    return undefined;
  }
  const persisted: PersistedRecallState = {
    screenName: screenName as ScreenName,
    draft: draft,
  };
  if (entryId !== undefined) {
    persisted.entryId = entryId;
  }
  return persisted;
}

function validateDraft(value: Object): PersistedDraft | undefined {
  const record = value as Record<string, Object>;
  if (typeof record['valence'] !== 'number') {
    return undefined;
  }
  const labelsRaw = record['labels'];
  if (!Array.isArray(labelsRaw) || !labelsRaw.every(isStringItem)) {
    return undefined;
  }
  if (typeof record['diaryEnabled'] !== 'boolean') {
    return undefined;
  }
  const transcriptRaw = record['transcript'];
  if (!Array.isArray(transcriptRaw)) {
    return undefined;
  }
  const transcript: PersistedChatMessage[] = [];
  for (let index = 0; index < transcriptRaw.length; index += 1) {
    const item = transcriptRaw[index] as Object;
    const message = validateChatMessage(item);
    if (message === undefined) {
      return undefined;
    }
    transcript.push(message);
  }
  const draft: PersistedDraft = {
    valence: record['valence'] as number,
    labels: labelsRaw as string[],
    diaryEnabled: record['diaryEnabled'] as boolean,
    transcript: transcript,
  };
  const aiEnabledRaw = record['aiEnabled'];
  if (aiEnabledRaw !== undefined) {
    if (typeof aiEnabledRaw !== 'boolean') {
      return undefined;
    }
    draft.aiEnabled = aiEnabledRaw;
  }
  const inputTextRaw = record['inputText'];
  if (inputTextRaw !== undefined) {
    if (typeof inputTextRaw !== 'string') {
      return undefined;
    }
    draft.inputText = inputTextRaw;
  }
  const kindRaw = record['kind'];
  if (kindRaw !== undefined) {
    if (typeof kindRaw !== 'string' || VALID_KINDS.indexOf(kindRaw as 'now' | 'past') < 0) {
      return undefined;
    }
    draft.kind = kindRaw as 'now' | 'past';
  }
  const emotionIdRaw = record['emotionId'];
  if (emotionIdRaw !== undefined) {
    if (typeof emotionIdRaw !== 'string') {
      return undefined;
    }
    draft.emotionId = emotionIdRaw;
  }
  const timeMarkRaw = record['timeMark'];
  if (timeMarkRaw !== undefined) {
    if (typeof timeMarkRaw !== 'string') {
      return undefined;
    }
    draft.timeMark = timeMarkRaw;
  }
  const noteRaw = record['note'];
  if (noteRaw !== undefined) {
    if (typeof noteRaw !== 'string') {
      return undefined;
    }
    draft.note = noteRaw;
  }
  const diaryRaw = record['diary'];
  if (diaryRaw !== undefined) {
    if (typeof diaryRaw !== 'string') {
      return undefined;
    }
    draft.diary = diaryRaw;
  }
  const stickerRaw = record['stickerTemplate'];
  if (stickerRaw !== undefined) {
    if (typeof stickerRaw !== 'string') {
      return undefined;
    }
    draft.stickerTemplate = stickerRaw;
  }
  return draft;
}

function validateChatMessage(value: Object): PersistedChatMessage | undefined {
  if (typeof value !== 'object' || value === null) {
    return undefined;
  }
  const record = value as Record<string, Object>;
  if (typeof record['text'] !== 'string' || typeof record['ts'] !== 'number') {
    return undefined;
  }
  const roleRaw = record['role'];
  if (typeof roleRaw !== 'string' || VALID_ROLES.indexOf(roleRaw as 'user' | 'ai') < 0) {
    return undefined;
  }
  return {
    role: roleRaw as 'user' | 'ai',
    text: record['text'] as string,
    ts: record['ts'] as number,
  };
}

function isStringItem(value: Object): boolean {
  return typeof value === 'string';
}

function hydrateState(persisted: PersistedRecallState): RecallState {
  const draft = persisted.draft;
  const transcript: PersistedChatMessage[] = [];
  for (let index = 0; index < draft.transcript.length; index += 1) {
    const message = draft.transcript[index];
    transcript.push({ role: message.role, text: message.text, ts: message.ts });
  }
  const draftValue: Draft = {
    mood: {
      valence: draft.valence,
      labels: draft.labels.slice(),
    },
    transcript: transcript,
    diaryEnabled: draft.diaryEnabled,
  };
  if (draft.aiEnabled !== undefined) {
    draftValue.aiEnabled = draft.aiEnabled;
  }
  if (draft.inputText !== undefined) {
    draftValue.inputText = draft.inputText;
  }
  if (draft.emotionId !== undefined) {
    draftValue.mood.emotionId = draft.emotionId as MoodId;
  }
  if (draft.kind !== undefined) {
    draftValue.kind = draft.kind;
  }
  if (draft.timeMark !== undefined) {
    draftValue.timeMark = draft.timeMark;
  }
  if (draft.note !== undefined) {
    draftValue.note = draft.note;
  }
  if (draft.diary !== undefined) {
    draftValue.diary = draft.diary;
  }
  if (draft.stickerTemplate !== undefined) {
    draftValue.stickerTemplate = draft.stickerTemplate as StickerTemplateId;
  }
  const state: RecallState = {
    screen: buildScreen(persisted.screenName, persisted.entryId),
    draft: draftValue,
  };
  return state;
}

function buildScreen(name: ScreenName, entryId: string | undefined) {
  switch (name) {
    case 'home': return Screen.home();
    case 'classify': return Screen.classify();
    case 'now-note': return Screen.nowNote();
    case 'past-time': return Screen.pastTime();
    case 'chat': return Screen.chat();
    case 'diary': return Screen.diary();
    case 'card': return Screen.card(entryId ?? '');
    case 'timeline': return Screen.timeline();
    case 'detail': return Screen.detail(entryId ?? '');
    default:
      return initialRecallState().screen;
  }
}