export type MoodId =
  | 'very-low'
  | 'low'
  | 'heavy'
  | 'calm'
  | 'okay'
  | 'bright'
  | 'joyful'
  | 'lonely'
  | 'sad'
  | 'angry'
  | 'afraid'
  | 'disappointed'
  | 'anxious'
  | 'aggrieved'
  | 'embarrassed';

export interface MoodState {
  valence: number;
  labels: string[];
  emotionId?: MoodId;
}

export type EntryKind = 'now' | 'past';

export type StickerTemplateId = 'planet-letter' | 'orbit-theatre';

export const DEFAULT_STICKER_TEMPLATE: StickerTemplateId = 'planet-letter';

export const VALID_STICKER_TEMPLATES: StickerTemplateId[] = ['planet-letter', 'orbit-theatre'];

export type ChatRole = 'user' | 'ai';

export interface ChatMessage {
  role: ChatRole;
  text: string;
  ts: number;
}

export interface DiaryEntry {
  id: string;
  createdAt: number;
  kind: EntryKind;
  mood: MoodState;
  timeMark?: string;
  note?: string;
  transcript?: ChatMessage[];
  diary?: string;
  diaryEnabled: boolean;
  stickerTemplate?: StickerTemplateId;
}

export type ScreenName =
  | 'home'
  | 'classify'
  | 'now-note'
  | 'past-time'
  | 'chat'
  | 'diary'
  | 'card'
  | 'timeline'
  | 'detail';

export class Screen {
  readonly name: ScreenName;
  readonly entryId?: string;

  private constructor(name: ScreenName, entryId?: string) {
    this.name = name;
    this.entryId = entryId;
  }

  static home(): Screen {
    return new Screen('home');
  }

  static classify(): Screen {
    return new Screen('classify');
  }

  static nowNote(): Screen {
    return new Screen('now-note');
  }

  static pastTime(): Screen {
    return new Screen('past-time');
  }

  static chat(): Screen {
    return new Screen('chat');
  }

  static diary(): Screen {
    return new Screen('diary');
  }

  static card(entryId: string): Screen {
    return new Screen('card', entryId);
  }

  static timeline(): Screen {
    return new Screen('timeline');
  }

  static detail(entryId: string): Screen {
    return new Screen('detail', entryId);
  }
}

export interface Draft {
  mood: MoodState;
  kind?: EntryKind;
  timeMark?: string;
  note?: string;
  transcript: ChatMessage[];
  aiEnabled?: boolean;
  inputText?: string;
  diary?: string;
  diaryEnabled: boolean;
  stickerTemplate?: StickerTemplateId;
}
