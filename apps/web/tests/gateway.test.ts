import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createGatewayClient,
  gatewayOpening as pausedOpening,
  gatewayResponse as pausedResponse,
  gatewayDiary as pausedDiary,
  setGatewayConsent as setPausedConsent,
  hasGatewayConsent as hasPausedConsent,
} from '../src/lib/gateway.ts'
import type { Draft } from '../src/types.ts'

// Keep the original recovery-path contract tests, without enabling product AI.
const { gatewayDiary, gatewayOpening, gatewayResponse, hasGatewayConsent, setGatewayConsent } = createGatewayClient(true)

const draft: Draft = {
  mood: { valence: 0, labels: ['平静'] },
  timeMark: '昨天',
  transcript: [{ role: 'user', text: '我出去散步了。', ts: 1 }],
  diaryEnabled: true,
  note: '不属于本次 AI 请求的本地文字',
  diary: '不属于本次 AI 请求的旧日记',
}

test('product pause prevents all gateway calls even when consent was enabled', async (t) => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => { throw new Error('must stay offline') })
  setPausedConsent(true)
  assert.equal(hasPausedConsent(), false)
  await assert.rejects(pausedOpening(draft), /暂时下架/)
  await assert.rejects(pausedResponse(draft, draft.transcript, '保留我的原话'), /暂时下架/)
  await assert.rejects(pausedDiary(draft), /暂时下架/)
  assert.equal(fetchMock.mock.callCount(), 0)
  assert.equal(draft.note, '不属于本次 AI 请求的本地文字')
})

test('AI requests require explicit consent, including diary generation', async (t) => {
  setGatewayConsent(false)
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => { throw new Error('不应联网') })
  assert.equal(hasGatewayConsent(), false)
  await assert.rejects(gatewayOpening(draft), /尚未开启 AI/)
  await assert.rejects(gatewayDiary(draft), /尚未开启 AI/)
  assert.equal(fetchMock.mock.callCount(), 0)
})

test('opening sends only the agreed gateway fields, without stored notes or old diaries', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => Response.json({ text: ' 从哪里说起？ ' }))
  assert.equal(await gatewayOpening(draft), '从哪里说起？')
  const [url, options] = fetchMock.mock.calls[0].arguments
  assert.equal(url, '/api/v1/recall/open')
  assert.deepEqual(JSON.parse(String(options?.body)), {
    draft: { mood: draft.mood, timeMark: draft.timeMark, transcript: [] },
  })
  assert.equal(options?.method, 'POST')
  assert.equal(new Headers(options?.headers).get('authorization'), null)
})

test('long chats keep their full local record while sending bounded context to the gateway', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  const transcript = Array.from({ length: 40 }, (_, index) => ({ role: 'user' as const, text: `记录 ${index}`, ts: index }))
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => Response.json({ text: '后来呢？' }))
  await gatewayResponse(draft, transcript, '记录 39')
  const payload = JSON.parse(String(fetchMock.mock.calls[0].arguments[1]?.body))
  assert.equal(payload.draft.transcript.length, 32)
  assert.equal(payload.draft.transcript[0].text, '记录 8')
  assert.equal(payload.userText, '记录 39')
  assert.equal(transcript.length, 40)
  // The diary fallback preserves the entire conversation instead of writing
  // an AI diary based only on the newest messages.
  await assert.rejects(gatewayDiary({ ...draft, transcript }), /完整的本地记录/)
  assert.equal(fetchMock.mock.callCount(), 1)
})

test('gateway errors use the server error envelope', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  t.mock.method(globalThis, 'fetch', async () => Response.json({ code: 'RATE_LIMITED', message: '请求过于频繁，请稍后再试。' }, { status: 429 }))
  await assert.rejects(gatewayOpening(draft), /请求过于频繁/)
})

test('a stalled request is aborted so the caller can continue with offline guidance', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  let signal: AbortSignal | null = null
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    signal = options?.signal ?? null
    return new Promise<Response>((_resolve, reject) => {
      signal?.addEventListener('abort', () => reject(signal?.reason), { once: true })
    })
  })
  await assert.rejects(gatewayOpening(draft, { timeoutMs: 5 }), /响应超时/)
  assert.equal((signal as AbortSignal | null)?.aborted, true)
})

test('leaving a screen cancels an in-flight request', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  t.mock.method(globalThis, 'fetch', async (_url, options) => new Promise<Response>((_resolve, reject) => {
    options?.signal?.addEventListener('abort', () => reject(options.signal?.reason), { once: true })
  }))
  const controller = new AbortController()
  const request = gatewayDiary(draft, { signal: controller.signal })
  controller.abort(new Error('已离开页面'))
  await assert.rejects(request, /已离开页面/)
})

test('malformed success responses fall back instead of becoming empty chat bubbles', async (t) => {
  setGatewayConsent(true)
  t.after(() => setGatewayConsent(false))
  t.mock.method(globalThis, 'fetch', async () => new Response('<html>not an API</html>'))
  await assert.rejects(gatewayOpening(draft), /空内容/)
})
