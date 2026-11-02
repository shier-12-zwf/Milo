import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildDiaryPrompt,
  buildOpeningPrompt,
  fallbackDiary,
  FallbackGuide,
  moodWord,
  transcriptToText,
  wantsToPause,
} from '../src/lib/guide.ts'
import type { Draft } from '../src/types.ts'

const draft: Draft = {
  mood: { valence: -2, labels: ['委屈'], emotionId: 'aggrieved' },
  timeMark: '去年夏天',
  transcript: [],
  diaryEnabled: true,
}

test('moodWord preserves a named discrete emotion and legacy valence fallback', () => {
  assert.equal(moodWord(-2, 'angry'), '愤怒')
  assert.equal(moodWord(-2), '低落')
})

test('offline guidance stays brief and asks at most one question at a time', () => {
  const guide = new FallbackGuide('去年夏天')
  const replies = [guide.opening(), ...Array.from({ length: 8 }, () => guide.next())]
  for (const reply of replies) {
    assert.ok(reply.length <= 48, reply)
    assert.ok((reply.match(/[?？]/g) ?? []).length <= 1, reply)
  }
  assert.equal(guide.isWrappingUp(), true)
  assert.equal(replies.at(-1), '嗯，我在听。')
})

test('long time descriptions do not turn the opening into a paragraph', () => {
  const longMark = '那是几年前一个特别长的夏天，我和朋友第一次去海边的时候'
  const opening = new FallbackGuide(longMark).opening()
  assert.ok(opening.length <= 30)
  assert.doesNotMatch(opening, new RegExp(longMark))
})

test('a present pause is respected without mistaking a recalled reluctance for stopping', () => {
  const guide = new FallbackGuide('昨天')
  assert.equal(wantsToPause('我现在不想聊了。'), true)
  assert.equal(wantsToPause('那时候我不想说，但现在想说说'), false)
  assert.equal(guide.next('我现在不想聊了。'), '好，先停在这里。')
  assert.equal(guide.isWrappingUp(), true)
  assert.doesNotMatch(guide.next(), /[?？]/)
  assert.equal(guide.next('不知道怎么说'), '没关系，慢慢来。')
})

test('local diaries keep every user statement and do not invent gratitude or use the guide as fact', () => {
  const memory: Draft = {
    ...draft,
    transcript: [
      { role: 'ai', text: '你后来释然了吗？', ts: 1 },
      { role: 'user', text: '  我还是有点难过。  ', ts: 2 },
      { role: 'user', text: ' ', ts: 3 },
      { role: 'user', text: '今天只想写这么多。', ts: 4 },
    ],
  }
  assert.equal(fallbackDiary(memory), '我还是有点难过。\n\n今天只想写这么多。')
  assert.equal(fallbackDiary(draft), '今天的心情，先记在这里。')
})

test('AI instructions favor brief optional questions and factual diaries without a word quota', () => {
  const opening = buildOpeningPrompt(draft)
  assert.match(opening, /最多问一个问题/)
  assert.match(opening, /不再追问/)
  assert.match(opening, /委屈/)
  assert.match(opening, /去年夏天/)
  const diary = buildDiaryPrompt(draft)
  assert.match(diary, /引导者的话不能当成用户经历/)
  assert.match(diary, /不为凑字数扩写/)
  assert.doesNotMatch(diary, /200~400/)
})

test('transcript exports retain the existing narrator name and complete text', () => {
  assert.equal(transcriptToText([
    { role: 'user', text: '我想慢慢说。', ts: 1 },
    { role: 'ai', text: '嗯，我在听。', ts: 2 },
  ]), '我：我想慢慢说。\n回响：嗯，我在听。')
})
