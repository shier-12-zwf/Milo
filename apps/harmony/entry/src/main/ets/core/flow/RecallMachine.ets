import { ChatMessage, ChatRole, Draft, EntryKind, MoodId, Screen } from '../model/Domain';
import { moodStateForId } from '../model/Moods';

export interface RecallState {
  screen: Screen;
  draft: Draft;
}

export class SelectMoodEvent {
  readonly type: 'SELECT_MOOD' = 'SELECT_MOOD';
  readonly moodId: MoodId;
  readonly labels: string[] | undefined;

  constructor(moodId: MoodId, labels?: string[]) {
    this.moodId = moodId;
    this.labels = labels;
  }
}

export class ClassifyEvent {
  readonly type: 'CLASSIFY' = 'CLASSIFY';
  readonly kind: EntryKind;

  constructor(kind: EntryKind) {
    this.kind = kind;
  }
}

export class SetNoteEvent {
  readonly type: 'SET_NOTE' = 'SET_NOTE';
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }
}

export class SetTimeMarkEvent {
  readonly type: 'SET_TIME_MARK' = 'SET_TIME_MARK';
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }
}

export class AppendMessageEvent {
  readonly type: 'APPEND_MESSAGE' = 'APPEND_MESSAGE';
  readonly message: ChatMessage;

  constructor(role: ChatRole, text: string, ts: number) {
    this.message = { role: role, text: text, ts: ts };
  }
}

export class SetDiaryEvent {
  readonly type: 'SET_DIARY' = 'SET_DIARY';
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }
}

export class UpdateChatEvent {
  readonly type: 'UPDATE_CHAT' = 'UPDATE_CHAT';
  readonly messages: ChatMessage[];
  readonly inputText: string;
  readonly aiEnabled: boolean;

  constructor(messages: ChatMessage[], inputText: string, aiEnabled: boolean) {
    this.messages = messages;
    this.inputText = inputText;
    this.aiEnabled = aiEnabled;
  }
}

export class SetDiaryEnabledEvent {
  readonly type: 'SET_DIARY_ENABLED' = 'SET_DIARY_ENABLED';
  readonly value: boolean;

  constructor(value: boolean) {
    this.value = value;
  }
}

export class OpenTimelineEvent {
  readonly type: 'OPEN_TIMELINE' = 'OPEN_TIMELINE';
}

export class OpenDetailEvent {
  readonly type: 'OPEN_DETAIL' = 'OPEN_DETAIL';
  readonly entryId: string;

  constructor(entryId: string) {
    this.entryId = entryId;
  }
}

export class BackEvent {
  readonly type: 'BACK' = 'BACK';
}

export class ResetEvent {
  readonly type: 'RESET' = 'RESET';
}

export type RecallEvent =
  | SelectMoodEvent
  | ClassifyEvent
  | SetNoteEvent
  | SetTimeMarkEvent
  | AppendMessageEvent
  | UpdateChatEvent
  | SetDiaryEvent
  | SetDiaryEnabledEvent
  | OpenTimelineEvent
  | OpenDetailEvent
  | BackEvent
  | ResetEvent;

export class RecallEvents {
  static selectMood(moodId: MoodId, labels?: string[]): SelectMoodEvent {
    return new SelectMoodEvent(moodId, labels);
  }

  static classify(kind: EntryKind): ClassifyEvent {
    return new ClassifyEvent(kind);
  }

  static setNote(value: string): SetNoteEvent {
    return new SetNoteEvent(value);
  }

  static setTimeMark(value: string): SetTimeMarkEvent {
    return new SetTimeMarkEvent(value);
  }

  static appendMessage(role: ChatRole, text: string, ts: number): AppendMessageEvent {
    return new AppendMessageEvent(role, text, ts);
  }

  static setDiary(value: string): SetDiaryEvent {
    return new SetDiaryEvent(value);
  }

  static updateChat(messages: ChatMessage[], inputText: string, aiEnabled: boolean): UpdateChatEvent {
    return new UpdateChatEvent(messages, inputText, aiEnabled);
  }

  static setDiaryEnabled(value: boolean): SetDiaryEnabledEvent {
    return new SetDiaryEnabledEvent(value);
  }

  static openTimeline(): OpenTimelineEvent {
    return new OpenTimelineEvent();
  }

  static openDetail(entryId: string): OpenDetailEvent {
    return new OpenDetailEvent(entryId);
  }

  static back(): BackEvent {
    return new BackEvent();
  }

  static reset(): ResetEvent {
    return new ResetEvent();
  }
}

export function initialRecallState(): RecallState {
  return {
    screen: Screen.home(),
    draft: {
      mood: { valence: 0, labels: [] },
      transcript: [],
      diaryEnabled: true,
    },
  };
}

function copyDraft(draft: Draft): Draft {
  const transcript: ChatMessage[] = [];
  for (let index = 0; index < draft.transcript.length; index += 1) {
    const message = draft.transcript[index];
    transcript.push({ role: message.role, text: message.text, ts: message.ts });
  }
  return {
    mood: {
      valence: draft.mood.valence,
      labels: draft.mood.labels.slice(),
      emotionId: draft.mood.emotionId,
    },
    kind: draft.kind,
    timeMark: draft.timeMark,
    note: draft.note,
    transcript: transcript,
    aiEnabled: draft.aiEnabled,
    inputText: draft.inputText,
    diary: draft.diary,
    diaryEnabled: draft.diaryEnabled,
    stickerTemplate: draft.stickerTemplate,
  };
}

function withDraft(screen: Screen, draft: Draft): RecallState {
  return { screen: screen, draft: draft };
}

function backScreen(state: RecallState): Screen | undefined {
  switch (state.screen.name) {
    case 'classify':
      return Screen.home();
    case 'now-note':
    case 'past-time':
      return Screen.classify();
    case 'chat':
      return Screen.pastTime();
    case 'diary':
      return Screen.chat();
    case 'card':
    case 'detail':
      return Screen.timeline();
    case 'timeline':
      return Screen.home();
    default:
      return undefined;
  }
}

export function transition(state: RecallState, event: RecallEvent): RecallState {
  if (event instanceof ResetEvent) {
    return initialRecallState();
  }

  if (event instanceof BackEvent) {
    const previous = backScreen(state);
    if (previous === undefined) {
      return state;
    }
    return withDraft(previous, copyDraft(state.draft));
  }

  if (event instanceof SelectMoodEvent) {
    if (state.screen.name !== 'home') {
      return state;
    }
    const mood = moodStateForId(event.moodId);
    if (mood === undefined) {
      return state;
    }
    if (event.labels !== undefined && event.labels.length > 0) {
      mood.labels = event.labels.slice();
    }
    return withDraft(Screen.classify(), {
      mood: mood,
      transcript: [],
      diaryEnabled: true,
    });
  }

  if (event instanceof ClassifyEvent) {
    if (state.screen.name !== 'classify' || state.draft.mood.emotionId === undefined) {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.kind = event.kind;
    return withDraft(event.kind === 'now' ? Screen.nowNote() : Screen.pastTime(), draft);
  }

  if (event instanceof SetNoteEvent) {
    if (state.screen.name !== 'now-note' || state.draft.kind !== 'now') {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.note = event.value;
    return withDraft(Screen.nowNote(), draft);
  }

  if (event instanceof SetTimeMarkEvent) {
    const timeMark = event.value.trim();
    if (state.screen.name !== 'past-time' || state.draft.kind !== 'past' || timeMark.length === 0) {
      return state;
    }
    const draft = copyDraft(state.draft);
    if (draft.timeMark !== undefined && draft.timeMark !== timeMark) {
      draft.transcript = [];
      draft.diary = undefined;
      draft.inputText = '';
    }
    draft.timeMark = timeMark;
    return withDraft(Screen.chat(), draft);
  }

  if (event instanceof AppendMessageEvent) {
    if (state.screen.name !== 'chat' || state.draft.kind !== 'past') {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.transcript.push({
      role: event.message.role,
      text: event.message.text,
      ts: event.message.ts,
    });
    return withDraft(Screen.chat(), draft);
  }

  if (event instanceof UpdateChatEvent) {
    if (state.screen.name !== 'chat' || state.draft.kind !== 'past') {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.transcript = [];
    draft.inputText = event.inputText;
    draft.aiEnabled = event.aiEnabled;
    for (let index = 0; index < event.messages.length; index += 1) {
      const message = event.messages[index];
      draft.transcript.push({ role: message.role, text: message.text, ts: message.ts });
    }
    return withDraft(Screen.chat(), draft);
  }

  if (event instanceof SetDiaryEvent) {
    if (state.screen.name !== 'chat' && state.screen.name !== 'diary') {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.diary = event.value;
    return withDraft(Screen.diary(), draft);
  }

  if (event instanceof SetDiaryEnabledEvent) {
    if (state.screen.name !== 'diary') {
      return state;
    }
    const draft = copyDraft(state.draft);
    draft.diaryEnabled = event.value;
    return withDraft(Screen.diary(), draft);
  }

  if (event instanceof OpenTimelineEvent) {
    if (state.screen.name !== 'home' && state.screen.name !== 'card') {
      return state;
    }
    return withDraft(Screen.timeline(), copyDraft(state.draft));
  }

  if (event instanceof OpenDetailEvent) {
    if (state.screen.name !== 'timeline' || event.entryId.trim().length === 0) {
      return state;
    }
    return withDraft(Screen.detail(event.entryId), copyDraft(state.draft));
  }

  return state;
}
