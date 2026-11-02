import type { ChatMessage, Draft } from '../types'
import { AI_FEATURE_AVAILABLE, AI_PAUSED_MESSAGE } from './aiAvailability.ts'

export const GATEWAY_TIMEOUT_MS = 15000
export const GATEWAY_MAX_TEXT_LENGTH = 2000
const MAX_TRANSCRIPT_LINES = 32

export interface GatewayRequestOptions {
  signal?: AbortSignal
  timeoutMs?: number
}

function summary(draft: Draft, transcript = draft.transcript) {
  return { mood: draft.mood, timeMark: draft.timeMark, transcript }
}

/** Isolated transport for recovery tests; the app uses the paused singleton below. */
export function createGatewayClient(available = AI_FEATURE_AVAILABLE) {
  // Consent belongs to this recall flow, never to a stored diary.
  let consent = false

  function setGatewayConsent(enabled: boolean) {
    consent = available && enabled
  }

  function hasGatewayConsent(): boolean {
    return available && consent
  }

  /**
   * Public Web deployments talk to the Milo gateway through the same-origin
   * `/api` reverse proxy. The proxy adds the server-side bearer token, so no
   * gateway credential is shipped to the browser.
   */
  async function request(path: string, body: Record<string, unknown>, options: GatewayRequestOptions = {}): Promise<string> {
    if (!available) throw new Error(AI_PAUSED_MESSAGE)
    if (!consent) throw new Error('尚未开启 AI。')
    const controller = new AbortController()
    const abort = () => controller.abort(options.signal?.reason)
    if (options.signal?.aborted) abort()
    options.signal?.addEventListener('abort', abort, { once: true })
    const timer = setTimeout(() => controller.abort(new Error('AI 响应超时。')), options.timeoutMs ?? GATEWAY_TIMEOUT_MS)

    try {
      const response = await fetch(`/api/v1/recall/${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      })
      const payload = (await response.json().catch(() => null)) as { text?: unknown; message?: unknown } | null
      if (!response.ok) {
        throw new Error(typeof payload?.message === 'string' ? payload.message : '网关暂时无法回应。')
      }
      if (typeof payload?.text !== 'string' || payload.text.trim().length === 0) {
        throw new Error('网关返回了空内容。')
      }
      return payload.text.trim()
    } finally {
      clearTimeout(timer)
      options.signal?.removeEventListener('abort', abort)
    }
  }

  function gatewayOpening(draft: Draft, options?: GatewayRequestOptions): Promise<string> {
    return request('open', { draft: summary(draft, []) }, options)
  }

  function gatewayResponse(draft: Draft, transcript: ChatMessage[], userText: string, options?: GatewayRequestOptions): Promise<string> {
    return request('respond', { draft: summary(draft, transcript.slice(-MAX_TRANSCRIPT_LINES)), userText }, options)
  }

  function gatewayDiary(draft: Draft, options?: GatewayRequestOptions): Promise<string> {
    // Long conversations stay complete in the local diary instead of silently
    // sending only the ending to an AI writer.
    if (draft.transcript.length > MAX_TRANSCRIPT_LINES) return Promise.reject(new Error('本次回忆将保留完整的本地记录。'))
    return request('diary', { draft: summary(draft) }, options)
  }

  return { setGatewayConsent, hasGatewayConsent, gatewayOpening, gatewayResponse, gatewayDiary }
}

export const { setGatewayConsent, hasGatewayConsent, gatewayOpening, gatewayResponse, gatewayDiary } = createGatewayClient()
