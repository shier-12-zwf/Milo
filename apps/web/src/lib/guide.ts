import { moodLabel } from '../components/moodEmotionModel.ts'
import type { Draft, ChatMessage, MoodId } from '../types'

export function moodWord(valence: number, emotionId?: MoodId): string {
  return moodLabel(valence, emotionId)
}

/** 首轮发给 Codex 的角色设定 + 开场引导请求 */
export function buildOpeningPrompt(draft: Draft): string {
  const labels = draft.mood.labels.length ? draft.mood.labels.join('、') : '未具体命名'
  return [
    '你是「回响」，一个安静的情绪记录伙伴。少说，让用户多说。',
    '每次只给一句短提示，通常 10~30 字，最多 48 字；最多问一个问题，也可以不提问。',
    '顺着用户刚说的一个具体细节回应，已说过的事不要重新问。',
    '让用户选择说什么、说多少；不要按问卷推进，不要求交代原因、人生意义或成长。',
    '用户说不想说、先停一下或没有了，就简短接受，不再追问；想不起来时也不要催促。',
    '不替用户判断情绪，不总结分析、说教、给建议或强行鼓励。',
    '只用自然口语，不用标题、列表、markdown、自我介绍或操作说明。',
    '',
    `用户此刻的情绪：${moodWord(draft.mood.valence, draft.mood.emotionId)}（${labels}）。`,
    `ta 想回到的时光：「${draft.timeMark ?? '过去的某一天'}」。`,
    '',
    '请只问一个很短的第一个问题，让用户从最先想起的画面说起。',
  ].join('\n')
}

/** 让 Codex 把对话沉淀为第一人称日记 */
export function buildDiaryPrompt(draft: Draft): string {
  const lines = draft.transcript
    .map((m) => `${m.role === 'user' ? '我' : '引导者'}：${m.text}`)
    .join('\n')
  return [
    '请根据下面这段对话，用用户（“我”）的第一人称，整理一段感受日记。',
    '只使用用户明确表达的事实和感受，保留原意；引导者的话不能当成用户经历。',
    '不添加用户没说过的释然、感激、成长或结论，不补背景和细节。',
    '用户只说了一点，就只写一点，不为凑字数扩写。',
    '不用标题、列表或 markdown，只输出日记正文。',
    `回忆的时间：「${draft.timeMark ?? '过去的某一天'}」。`,
    '',
    '对话记录：',
    lines,
  ].join('\n')
}

const GUIDE_STEPS = [
  '那一刻，你是什么感受？',
  '哪件小事让你记得最清楚？',
  '现在想起它，心里有什么变化？',
  '还有什么想说的？',
  '嗯，我在听。',
]

/** Recognize a present request to pause, not a memory of a past reluctance. */
export function wantsToPause(text: string): boolean {
  const line = text.trim().replace(/[，,。.!！?？\s]/g, '')
  return /^(我)?(现在|今天|暂时|真的)?(不想说|不想聊|不说了|不聊了|先不说|先不聊|说不下去|聊不下去|先这样|就这样|到这里|算了|没了|没有了)(了|吧)?$/.test(line)
}

function hasNoWords(text: string): boolean {
  const line = text.trim().replace(/[，,。.!！?？\s]/g, '')
  return /^(我)?(也|现在|有点)?(不知道|不知道怎么说|说不上来|想不起来|没什么|没啥)(了|吧)?$/.test(line)
}

/** Offline guidance leaves the story and its meaning to the user. */
export class FallbackGuide {
  private step = 0
  private timeMark: string

  constructor(timeMark: string) {
    this.timeMark = timeMark
  }

  opening(): string {
    return this.timeMark.length > 18
      ? '那段时光里，你最先想起什么？'
      : `「${this.timeMark}」，你最先想起什么？`
  }

  next(userText = ''): string {
    if (wantsToPause(userText)) {
      this.step = Math.max(this.step + 1, GUIDE_STEPS.length)
      return '好，先停在这里。'
    }
    const reply = GUIDE_STEPS[Math.min(this.step, GUIDE_STEPS.length - 1)]
    this.step++
    return hasNoWords(userText) ? '没关系，慢慢来。' : reply
  }

  isWrappingUp(): boolean {
    return this.step >= GUIDE_STEPS.length
  }
}

/** Preserve the user's own words without inventing relief or a lesson. */
export function fallbackDiary(draft: Draft): string {
  const userLines = draft.transcript
    .filter((m) => m.role === 'user')
    .map((m) => m.text.trim())
    .filter(Boolean)
  return userLines.length > 0 ? userLines.join('\n\n') : '今天的心情，先记在这里。'
}

export function transcriptToText(transcript: ChatMessage[]): string {
  return transcript.map((m) => `${m.role === 'user' ? '我' : '回响'}：${m.text}`).join('\n')
}
