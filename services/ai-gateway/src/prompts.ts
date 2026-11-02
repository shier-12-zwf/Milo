import type { DraftSummary } from './contracts.js';

const VALENCE_LABEL: Record<number, string> = {
  [-3]: '非常低落',
  [-2]: '低落',
  [-1]: '有些沉',
  [0]: '平静',
  [1]: '还不错',
  [2]: '明亮',
  [3]: '雀跃',
};

function moodWord(valence: number, emotionId?: string): string {
  if (emotionId !== undefined) {
    const label = labelForEmotionId(emotionId);
    if (label !== undefined) return label;
  }
  return VALENCE_LABEL[valence] ?? '平静';
}

function labelForEmotionId(id: string): string | undefined {
  const known: Record<string, string> = {
    'very-low': '非常低落',
    'low': '低落',
    'heavy': '有些沉',
    'calm': '平静',
    'okay': '还不错',
    'bright': '明亮',
    'joyful': '雀跃',
    'lonely': '孤独',
    'sad': '悲伤',
    'angry': '愤怒',
    'afraid': '害怕',
    'disappointed': '失望',
    'anxious': '焦虑',
    'aggrieved': '委屈',
    'embarrassed': '尴尬',
  };
  return known[id];
}

export const CONVERSATION_SYSTEM = [
  '你是「回响」，一个安静的情绪记录伙伴。少说，让用户多说。',
  '每次只给一句短提示，通常 10~30 字，最多 48 字；最多问一个问题，也可以不提问。',
  '优先接住用户刚说的一个具体细节，轻轻追问；已说过的事不要重新问。',
  '让用户选择说什么、说多少；不要按固定问卷推进，不要求交代原因、人生意义或成长。',
  '用户说不想说、先停一下或没有了，就简短接受，不再追问；想不起来时也不要催促。',
  '不替用户判断情绪，不说“我完全理解”，不总结分析、说教、给建议或强行鼓励。',
  '只用自然口语，不用标题、列表、markdown、自我介绍或操作说明。',
].join('\n');

function conversationContext(draft: DraftSummary): string {
  const labels = draft.mood.labels.length > 0 ? draft.mood.labels.join('、') : '未具体命名';
  return [
    `用户此刻选择的情绪：${moodWord(draft.mood.valence, draft.mood.emotionId)}（${labels}）。`,
    `想起的时光：「${draft.timeMark ?? '过去的某一天'}」。`,
  ].join('\n');
}

export function buildOpeningPrompt(draft: DraftSummary): string {
  return [
    conversationContext(draft),
    '请只问一个很短的第一个问题，让用户从最先想起的画面说起。',
  ].join('\n');
}

export function buildRespondSystem(draft: DraftSummary): string {
  return [CONVERSATION_SYSTEM, conversationContext(draft), '顺着下面的对话回应最后一句，不要重新开场。'].join('\n');
}

export function buildDiaryPrompt(draft: DraftSummary): string {
  const transcript = draft.transcript
    .filter((m) => m.role === 'user' && m.text.trim().length > 0)
    .map((m) => `我：${m.text.trim()}`)
    .join('\n');
  return [
    '请根据下面的用户原话，用用户（“我”）的第一人称，整理一段感受日记。',
    '只使用用户明确表达的事实和感受，保留原意；不得推导用户没说过的情绪或结论。',
    '保持原话的情绪强度；没有明确表述时，不添加最高级、比较级或因果关系。',
    '不添加用户没说过的释然、感激、成长或结论，不补背景和细节。',
    '用户只说了一点，就只写一点，不为凑字数扩写。',
    '不用标题、列表或 markdown，只输出日记正文。',
    `回忆的时间：「${draft.timeMark ?? '过去的某一天'}」。`,
    '',
    '用户原话：',
    transcript,
  ].join('\n');
}
