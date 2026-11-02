import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDiaryPrompt, buildOpeningPrompt, buildRespondSystem, CONVERSATION_SYSTEM } from '../src/prompts.js';
import type { DraftSummary } from '../src/contracts.js';

test('opening prompt uses the chosen mood and time without prescribing a questionnaire', () => {
  const draft: DraftSummary = {
    mood: { valence: 0, labels: ['平静'], emotionId: 'calm' },
    timeMark: '去年夏天',
    transcript: [],
  };
  const text = buildOpeningPrompt(draft);
  assert.ok(CONVERSATION_SYSTEM.includes('最多 48 字'));
  assert.ok(CONVERSATION_SYSTEM.includes('不再追问'));
  assert.ok(!text.includes('人生意义'));
  assert.ok(text.includes('平静'));
  assert.ok(text.includes('去年夏天'));
  assert.ok(text.includes('第一个问题'));
});

test('opening prompt falls back to the valence bucket when no emotion id is set', () => {
  const draft: DraftSummary = {
    mood: { valence: 3, labels: [] },
    timeMark: undefined,
    transcript: [],
  };
  const text = buildOpeningPrompt(draft);
  assert.ok(text.includes('雀跃'));
  assert.ok(text.includes('过去的某一天'));
  assert.ok(text.includes('未具体命名'));
});

test('diary prompt contains only user statements, excluding leading AI questions', () => {
  const draft: DraftSummary = {
    mood: { valence: 0, labels: ['平静'] },
    timeMark: '去年夏天',
    transcript: [
      { role: 'ai', text: '欢迎回来', ts: 1 },
      { role: 'user', text: '昨天傍晚在公园散步，闻到桂花香，心情很轻松', ts: 2 },
      { role: 'ai', text: '闻到的时候最放松吧？', ts: 3 },
    ],
  };
  const text = buildDiaryPrompt(draft);
  assert.ok(!text.includes('欢迎回来'));
  assert.ok(!text.includes('闻到的时候最放松吧？'));
  assert.ok(!text.includes('最放松'));
  assert.ok(text.includes('我：昨天傍晚在公园散步，闻到桂花香，心情很轻松'));
  assert.ok(text.includes('去年夏天'));
});

test('diary source retains every user statement but no AI-supplied experience', () => {
  const text = buildDiaryPrompt({
    mood: { valence: 0, labels: [] },
    transcript: [
      { role: 'ai', text: '所以你和朋友冰释前嫌了？', ts: 1 },
      { role: 'user', text: '  我只是走了一会儿。  ', ts: 2 },
      { role: 'ai', text: '你一定很感激朋友的陪伴。', ts: 3 },
      { role: 'user', text: '其实只有我自己。', ts: 4 },
      { role: 'user', text: ' ', ts: 5 },
    ],
  });
  const source = text.split('用户原话：\n')[1];
  assert.equal(source, '我：我只是走了一会儿。\n我：其实只有我自己。');
  assert.ok(!text.includes('冰释前嫌'));
  assert.ok(!text.includes('朋友的陪伴'));
});

test('respond instructions leave the user in control and retain mood context', () => {
  const text = buildRespondSystem({ mood: { valence: -2, labels: ['低落'] }, timeMark: '毕业那天', transcript: [] });
  assert.ok(text.includes('低落'));
  assert.ok(text.includes('毕业那天'));
  assert.ok(text.includes('最多问一个问题'));
  assert.ok(text.includes('不要重新开场'));
});

test('diary length follows what the user actually shared', () => {
  const text = buildDiaryPrompt({ mood: { valence: 0, labels: [] }, transcript: [] });
  assert.ok(text.includes('不得推导用户没说过的情绪或结论'));
  assert.ok(text.includes('不添加最高级、比较级或因果关系'));
  assert.ok(text.includes('不为凑字数扩写'));
  assert.ok(!text.includes('200~400'));
});
