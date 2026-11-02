import { MoodId, MoodState } from './Domain';

export { MoodId, MoodState };

export interface MoodDefinition {
  readonly id: MoodId;
  readonly valence: number;
  readonly labels: ReadonlyArray<string>;
  readonly emotionId: MoodId;
}

export const MOODS: ReadonlyArray<MoodDefinition> = [
  { id: 'very-low', valence: -3, labels: ['非常低落'], emotionId: 'very-low' },
  { id: 'low', valence: -2, labels: ['低落'], emotionId: 'low' },
  { id: 'heavy', valence: -1, labels: ['有些沉'], emotionId: 'heavy' },
  { id: 'calm', valence: 0, labels: ['平静'], emotionId: 'calm' },
  { id: 'okay', valence: 1, labels: ['还不错'], emotionId: 'okay' },
  { id: 'bright', valence: 2, labels: ['明亮'], emotionId: 'bright' },
  { id: 'joyful', valence: 3, labels: ['雀跃'], emotionId: 'joyful' },
  { id: 'lonely', valence: -2, labels: ['孤独'], emotionId: 'lonely' },
  { id: 'sad', valence: -3, labels: ['悲伤'], emotionId: 'sad' },
  { id: 'angry', valence: -2, labels: ['愤怒'], emotionId: 'angry' },
  { id: 'afraid', valence: -2, labels: ['害怕'], emotionId: 'afraid' },
  { id: 'disappointed', valence: -2, labels: ['失望'], emotionId: 'disappointed' },
  { id: 'anxious', valence: -1, labels: ['焦虑'], emotionId: 'anxious' },
  { id: 'aggrieved', valence: -2, labels: ['委屈'], emotionId: 'aggrieved' },
  { id: 'embarrassed', valence: -1, labels: ['尴尬'], emotionId: 'embarrassed' },
];

export function moodStateForId(id: MoodId): MoodState | undefined {
  for (let index = 0; index < MOODS.length; index += 1) {
    const mood = MOODS[index];
    if (mood.id === id) {
      return {
        valence: mood.valence,
        labels: mood.labels.slice(),
        emotionId: mood.emotionId,
      };
    }
  }
  return undefined;
}

/**
 * Home dial order, mirroring the web build's `ECHO_SELECTOR_MOOD_IDS`:
 * calm in the middle, each side progressing outward by intensity.
 */
const ECHO_SELECTOR_MOOD_IDS: ReadonlyArray<MoodId> = [
  'joyful',
  'bright',
  'okay',
  'calm',
  'heavy',
  'low',
  'very-low',
];

function selectorMood(id: MoodId): MoodDefinition {
  for (let index = 0; index < MOODS.length; index += 1) {
    const mood = MOODS[index];
    if (mood.id === id) {
      return mood;
    }
  }
  return MOODS[3];
}

export const ECHO_SELECTOR_MOODS: ReadonlyArray<MoodDefinition> = ECHO_SELECTOR_MOOD_IDS.map(
  (id: MoodId): MoodDefinition => selectorMood(id),
);

type MoodPolarity = 'negative' | 'neutral' | 'positive';

const BASE_DESCRIPTOR_WORDS: Record<MoodPolarity, ReadonlyArray<string>> = {
  'negative': [
    '难过', '失落', '孤独', '担心', '疲惫', '压抑', '委屈', '害怕', '遗憾', '迷茫', '烦躁', '无力',
  ],
  'neutral': [
    '平静', '安稳', '松弛', '清醒', '踏实', '淡然', '宁静', '柔和', '从容', '平衡', '舒展', '自在',
  ],
  'positive': [
    '轻盈', '温暖', '喜悦', '期待', '安心', '满足', '有力量', '被理解', '感动', '雀跃', '明亮', '自在',
  ],
};

const MOOD_DESCRIPTOR_PREFIXES: Record<MoodId, ReadonlyArray<string>> = {
  'very-low': ['沉到底', '撑不住', '空荡', '无望'],
  'low': ['低沉', '消沉', '沮丧', '提不起劲'],
  'heavy': ['沉重', '疲惫', '压着', '迟滞'],
  'calm': ['平静', '安稳', '松弛', '清醒'],
  'okay': ['还不错', '舒心', '安然', '有盼头'],
  'bright': ['明亮', '开朗', '有希望', '焕然'],
  'joyful': ['雀跃', '兴奋', '欢欣', '想庆祝'],
  'lonely': ['孤单', '被落下', '想念', '疏离'],
  'sad': ['悲伤', '心碎', '想哭', '哀痛'],
  'angry': ['恼火', '愤懑', '被冒犯', '想反抗'],
  'afraid': ['恐惧', '不安全', '警觉', '想躲开'],
  'disappointed': ['落空', '心凉', '遗憾', '不甘'],
  'anxious': ['焦灼', '不安', '紧绷', '停不下来'],
  'aggrieved': ['委屈', '被误解', '忍着', '想被看见'],
  'embarrassed': ['窘迫', '不自在', '难为情', '想逃开'],
};

function polarityFromValence(valence: number): MoodPolarity {
  if (valence < 0) {
    return 'negative';
  }
  if (valence > 0) {
    return 'positive';
  }
  return 'neutral';
}

/**
 * Descriptor words for the word ring, mirroring the web
 * `getMoodDescriptorWords`: mood-specific prefixes first, then the polarity
 * base list, deduplicated and capped at 12 entries.
 */
export function getMoodDescriptorWords(emotionId: MoodId | undefined, valence: number): string[] {
  const polarity: MoodPolarity = emotionId !== undefined
    ? polarityFromValence(moodValenceForId(emotionId))
    : polarityFromValence(valence);
  const words: string[] = [];
  const prefixes: ReadonlyArray<string> | undefined =
    emotionId !== undefined ? MOOD_DESCRIPTOR_PREFIXES[emotionId] : undefined;
  if (prefixes !== undefined) {
    for (let index = 0; index < prefixes.length; index += 1) {
      words.push(prefixes[index]);
    }
  }
  const base: ReadonlyArray<string> = BASE_DESCRIPTOR_WORDS[polarity];
  for (let index = 0; index < base.length; index += 1) {
    const word = base[index];
    let seen = false;
    for (let scan = 0; scan < words.length; scan += 1) {
      if (words[scan] === word) {
        seen = true;
        break;
      }
    }
    if (!seen) {
      words.push(word);
    }
  }
  return words.slice(0, 12);
}

function moodValenceForId(id: MoodId): number {
  for (let index = 0; index < MOODS.length; index += 1) {
    const mood = MOODS[index];
    if (mood.id === id) {
      return mood.valence;
    }
  }
  return 0;
}
