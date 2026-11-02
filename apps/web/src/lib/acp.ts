/**
 * 与本地 ACP 桥接服务（server/acp-bridge.mjs）通信的 WebSocket 客户端。
 * 桥接服务负责把消息转发给 Codex ACP（stdio）。
 */

import { AI_FEATURE_AVAILABLE, AI_PAUSED_MESSAGE } from './aiAvailability.ts'

const bridgeUrl = () => `ws://${location.hostname}:8787`

type ServerMsg =
  | { type: 'ready' }
  | { type: 'delta'; id: number; text: string }
  | { type: 'turn_end'; id: number; stopReason?: string }
  | { type: 'error'; message: string }

export class AcpClient {
  private ws: WebSocket | null = null
  private nextId = 1
  private pending = new Map<
    number,
    { onDelta: (t: string) => void; resolve: (full: string) => void; reject: (e: Error) => void; buf: string }
  >()

  /** 连接并等待 ACP 会话就绪；失败或超时抛错 */
  connect(timeoutMs = 20000): Promise<void> {
    if (!AI_FEATURE_AVAILABLE) return Promise.reject(new Error(AI_PAUSED_MESSAGE))
    return new Promise((resolve, reject) => {
      let settled = false
      const ws = new WebSocket(bridgeUrl())
      this.ws = ws
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true
          ws.close()
          reject(new Error('ACP 桥接连接超时'))
        }
      }, timeoutMs)

      ws.onmessage = (ev) => {
        let msg: ServerMsg
        try {
          msg = JSON.parse(ev.data as string)
        } catch {
          return
        }
        if (msg.type === 'ready' && !settled) {
          settled = true
          clearTimeout(timer)
          resolve()
          return
        }
        if (msg.type === 'delta') {
          const p = this.pending.get(msg.id)
          if (p) {
            p.buf += msg.text
            p.onDelta(msg.text)
          }
        } else if (msg.type === 'turn_end') {
          const p = this.pending.get(msg.id)
          if (p) {
            this.pending.delete(msg.id)
            p.resolve(p.buf)
          }
        } else if (msg.type === 'error') {
          if (!settled) {
            settled = true
            clearTimeout(timer)
            reject(new Error(msg.message))
          }
          for (const [id, p] of this.pending) {
            p.reject(new Error(msg.message))
            this.pending.delete(id)
          }
        }
      }
      ws.onerror = () => {
        if (!settled) {
          settled = true
          clearTimeout(timer)
          reject(new Error('无法连接 ACP 桥接服务'))
        }
      }
      ws.onclose = () => {
        for (const [id, p] of this.pending) {
          p.reject(new Error('连接已断开'))
          this.pending.delete(id)
        }
      }
    })
  }

  /** 发送一轮 prompt，流式回调增量文本，返回完整回复 */
  prompt(text: string, onDelta: (t: string) => void = () => {}): Promise<string> {
    if (!AI_FEATURE_AVAILABLE) return Promise.reject(new Error(AI_PAUSED_MESSAGE))
    const ws = this.ws
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error('未连接'))
    }
    const id = this.nextId++
    return new Promise<string>((resolve, reject) => {
      this.pending.set(id, { onDelta, resolve, reject, buf: '' })
      ws.send(JSON.stringify({ type: 'prompt', id, text }))
    })
  }

  close() {
    this.ws?.close()
    this.ws = null
  }
}

/* ---------- 单例会话：对话页与日记页共享同一 ACP 会话 ---------- */

let singleton: AcpClient | null = null
let connecting: Promise<AcpClient | null> | null = null

/** 获取（或建立）共享 ACP 会话；不可用时返回 null */
export function ensureAcp(): Promise<AcpClient | null> {
  if (!AI_FEATURE_AVAILABLE) {
    resetAcp()
    return Promise.resolve(null)
  }
  if (singleton) return Promise.resolve(singleton)
  if (connecting) return connecting
  connecting = (async () => {
    const client = new AcpClient()
    try {
      await client.connect()
      singleton = client
      return client
    } catch {
      client.close()
      return null
    } finally {
      connecting = null
    }
  })()
  return connecting
}

/** 结束当前会话（一次回忆记录完成后调用） */
export function resetAcp() {
  singleton?.close()
  singleton = null
  connecting = null
}
