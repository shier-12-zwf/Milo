import type { MoodId } from '../types'
import { ECHO_MOODS, getMoodVisual } from './moodEmotionModel.ts'

export type MoodPolarity = 'negative' | 'neutral' | 'positive'

export interface MoodSelection {
  valence: number
  emotionId?: MoodId
}

/**
 * Display order for the rotating first-page selector.
 * With calm focused at 180°, lower indices render on the right and higher
 * indices on the left, so each side progresses outward by intensity.
 */
export const ECHO_SELECTOR_MOOD_IDS: readonly MoodId[] = Object.freeze([
  'joyful',
  'bright',
  'okay',
  'calm',
  'heavy',
  'low',
  'very-low',
])

export const ECHO_SELECTOR_MOODS = Object.freeze(
  ECHO_SELECTOR_MOOD_IDS.map((id) => getMoodVisual(id)),
)

export const DEFAULT_ECHO_SELECTOR_INDEX = ECHO_SELECTOR_MOODS.findIndex(({ id }) => id === 'calm')

const BASE_DESCRIPTOR_WORDS: Readonly<Record<MoodPolarity, readonly string[]>> = Object.freeze({
  negative: Object.freeze([
    '难过',
    '失落',
    '孤独',
    '担心',
    '疲惫',
    '压抑',
    '委屈',
    '害怕',
    '遗憾',
    '迷茫',
    '烦躁',
    '无力',
  ]),
  neutral: Object.freeze([
    '平静',
    '安稳',
    '松弛',
    '清醒',
    '踏实',
    '淡然',
    '宁静',
    '柔和',
    '从容',
    '平衡',
    '舒展',
    '自在',
  ]),
  positive: Object.freeze([
    '轻盈',
    '温暖',
    '喜悦',
    '期待',
    '安心',
    '满足',
    '有力量',
    '被理解',
    '感动',
    '雀跃',
    '明亮',
    '自在',
  ]),
})

const MOOD_DESCRIPTOR_PREFIXES: Readonly<Partial<Record<MoodId, readonly string[]>>> = Object.freeze({
  'very-low': Object.freeze(['沉到底', '撑不住', '空荡', '无望']),
  low: Object.freeze(['低沉', '消沉', '沮丧', '提不起劲']),
  heavy: Object.freeze(['沉重', '疲惫', '压着', '迟滞']),
  calm: Object.freeze(['平静', '安稳', '松弛', '清醒']),
  okay: Object.freeze(['还不错', '舒心', '安然', '有盼头']),
  bright: Object.freeze(['明亮', '开朗', '有希望', '焕然']),
  joyful: Object.freeze(['雀跃', '兴奋', '欢欣', '想庆祝']),
  lonely: Object.freeze(['孤单', '被落下', '想念', '疏离']),
  sad: Object.freeze(['悲伤', '心碎', '想哭', '哀痛']),
  angry: Object.freeze(['恼火', '愤懑', '被冒犯', '想反抗']),
  afraid: Object.freeze(['恐惧', '不安全', '警觉', '想躲开']),
  disappointed: Object.freeze(['落空', '心凉', '遗憾', '不甘']),
  anxious: Object.freeze(['焦灼', '不安', '紧绷', '停不下来']),
  aggrieved: Object.freeze(['委屈', '被误解', '忍着', '想被看见']),
  embarrassed: Object.freeze(['窘迫', '不自在', '难为情', '想逃开']),
})

const DESCRIPTOR_WORDS_BY_MOOD = new Map<MoodId, readonly string[]>(
  ECHO_MOODS.map(({ id, valence }) => {
    const polarity = polarityFromValence(valence)
    const words = [...new Set([...(MOOD_DESCRIPTOR_PREFIXES[id] ?? []), ...BASE_DESCRIPTOR_WORDS[polarity]])]
    return [id, Object.freeze(words.slice(0, 12))]
  }),
)

export function polarityFromValence(valence: number): MoodPolarity {
  if (valence < 0) return 'negative'
  if (valence > 0) return 'positive'
  return 'neutral'
}

export function moodPolarity(selection: MoodSelection): MoodPolarity {
  const valence = selection.emotionId === undefined
    ? selection.valence
    : getMoodVisual(selection.emotionId).valence
  return polarityFromValence(valence)
}

export function getMoodDescriptorWords(selection: MoodSelection): readonly string[] {
  if (selection.emotionId !== undefined) {
    const words = DESCRIPTOR_WORDS_BY_MOOD.get(selection.emotionId)
    if (words) return words
  }
  return BASE_DESCRIPTOR_WORDS[moodPolarity(selection)]
}
