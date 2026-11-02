import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { AcpClient, ensureAcp } from '../src/lib/acp.ts'
import { AI_FEATURE_AVAILABLE } from '../src/lib/aiAvailability.ts'
import { fallbackDiary } from '../src/lib/guide.ts'

test('AI pause blocks ACP before any WebSocket creation or retained-session prompt', async () => {
  assert.equal(AI_FEATURE_AVAILABLE, false)
  assert.equal(await ensureAcp(), null)
  const client = new AcpClient()
  // Node has no location; either entry leaking to browser/network setup would fail differently.
  await assert.rejects(client.connect(), /暂时下架/)
  await assert.rejects(client.prompt('仅本机保留'), /暂时下架/)
})

test('paused diary generation preserves the user text without generated conclusions', () => {
  assert.equal(fallbackDiary({
    mood: { valence: 0, labels: [] }, diaryEnabled: true,
    transcript: [{ role: 'user', text: '想留住今天这件小事。', ts: 1 }],
  }), '想留住今天这件小事。')
})

test('chat choice and diary generation consult the product pause before transports', () => {
  const chat = readFileSync(new URL('../src/pages/Chat.tsx', import.meta.url), 'utf8')
  const diary = readFileSync(new URL('../src/pages/Diary.tsx', import.meta.url), 'utf8')
  const deployment = readFileSync(new URL('../src/lib/deployment.ts', import.meta.url), 'utf8')
  assert.match(chat, /AI_FEATURE_AVAILABLE && mode === 'choice'/)
  assert.ok(chat.indexOf('if (!AI_FEATURE_AVAILABLE ||') < chat.indexOf('await gatewayOpening'))
  assert.ok(diary.indexOf('if (!AI_FEATURE_AVAILABLE)') < diary.indexOf('await gatewayDiary'))
  assert.match(deployment, /PUBLIC_AI_ENABLED = AI_FEATURE_AVAILABLE &&/)
})
