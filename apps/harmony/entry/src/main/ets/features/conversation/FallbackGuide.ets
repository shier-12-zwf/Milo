import { type ChatMessage, type Draft, type MoodId } from '../../core/model/Domain';
import { MOODS } from '../../core/model/Moods';

/**
 * Returns the human label for a mood state. Mirrors the web
 * `moodLabel(valence, emotionId)` lookup in `apps/web/src/components/moodEmotionModel.ts`.
 */
export function moodWord(valence: number, emotionId?: MoodId): string {
  if (emotionId !== undefined) {
    for (let index = 0; index < MOODS.length; index += 1) {
      const mood = MOODS[index];
      if (mood.id === emotionId) {
        return mood.labels[0];
      }
    }
  }
  if (valence === -3) return '非常低落';
  if (valence === -2) return '低落';
  if (valence === -1) return '有些沉';
  if (valence === 0) return '平静';
  if (valence === 1) return '还不错';
  if (valence === 2) return '明亮';
  if (valence === 3) return '雀跃';
  return '平静';
}

const GUIDE_STEPS: string[] = [
  '那一刻，你是什么感受？',
  '哪件小事让你记得最清楚？',
  '现在想起它，心里有什么变化？',
  '还有什么想说的？',
  '嗯，我在听。',
];

/** Match a present request to stop, not a story about a past reluctance. */
export function wantsToPause(text: string): boolean {
  const line = text.trim().replace(/[，,。.!！?？\s]/g, '');
  return /^(我)?(现在|今天|暂时|真的)?(不想说|不想聊|不说了|不聊了|先不说|先不聊|说不下去|聊不下去|先这样|就这样|到这里|算了|没了|没有了)(了|吧)?$/.test(line);
}

/** A quiet prompt is enough when the person has no words yet. */
function hasNoWords(text: string): boolean {
  const line = text.trim().replace(/[，,。.!！?？\s]/g, '');
  return /^(我)?(也|现在|有点)?(不知道|不知道怎么说|说不上来|想不起来|没什么|没啥)(了|吧)?$/.test(line);
}

/** Offline prompts leave the story and its meaning to the user. */
export class FallbackGuide {
  private step: number = 0;
  private timeMark: string;

  constructor(timeMark: string) {
    this.timeMark = timeMark;
  }

  opening(): string {
    if (this.timeMark.length > 18) {
      return '那段时光里，你最先想起什么？';
    }
    return `「${this.timeMark}」，你最先想起什么？`;
  }

  next(userText: string = ''): string {
    if (wantsToPause(userText)) {
      this.step = Math.max(this.step + 1, GUIDE_STEPS.length);
      return '好，先停在这里。';
    }
    const reply = GUIDE_STEPS[Math.min(this.step, GUIDE_STEPS.length - 1)];
    this.step += 1;
    if (hasNoWords(userText)) {
      return '没关系，慢慢来。';
    }
    return reply;
  }

  closing(): string {
    return '先把这些留下来。';
  }

  /** A soft checkpoint, never a requirement to end or complete the chat. */
  isWrappingUp(): boolean {
    return this.step >= GUIDE_STEPS.length;
  }

  currentStep(): number {
    return this.step;
  }

  restoreStep(step: number): void {
    this.step = Math.max(0, Math.floor(step));
  }
}

/** Keep the user's own words; never invent relief, gratitude or a lesson. */
export function fallbackDiary(draft: Draft): string {
  const userLines: string[] = [];
  for (let index = 0; index < draft.transcript.length; index += 1) {
    const message = draft.transcript[index];
    if (message.role === 'user' && message.text.trim().length > 0) {
      userLines.push(message.text.trim());
    }
  }
  return userLines.length > 0 ? userLines.join('\n\n') : '今天的心情，先记在这里。';
}

/** Format a transcript as `我：…` / `回响：…` lines. */
export function transcriptToText(transcript: ChatMessage[]): string {
  const parts: string[] = [];
  for (let index = 0; index < transcript.length; index += 1) {
    const message = transcript[index];
    const who = message.role === 'user' ? '我' : '回响';
    parts.push(`${who}：${message.text}`);
  }
  return parts.join('\n');
}
