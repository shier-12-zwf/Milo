import { useEffect, useRef, useState } from 'react'
import { ensureAcp, type AcpClient } from '../lib/acp'
import { gatewayOpening, gatewayResponse, GATEWAY_MAX_TEXT_LENGTH, setGatewayConsent } from '../lib/gateway'
import { buildOpeningPrompt, FallbackGuide, wantsToPause } from '../lib/guide'
import { useSpeech } from '../lib/speech'
import { PUBLIC_AI_ENABLED } from '../lib/deployment'
import { AI_FEATURE_AVAILABLE } from '../lib/aiAvailability'
import type { ChatMessage, Draft } from '../types'

interface Props {
  draft: Draft
  onFinish: (transcript: ChatMessage[], usedAcp: boolean) => void
  onBack: () => void
}

type Mode = 'choice' | 'connecting' | 'acp' | 'gateway' | 'fallback'

function usePublicGateway() {
  return import.meta.env.PROD && window.location.protocol.startsWith('http')
}

export function Chat({ draft, onFinish, onBack }: Props) {
  const publicGateway = usePublicGateway()
  const [choice, setChoice] = useState<'pending' | 'ai' | 'local'>(!AI_FEATURE_AVAILABLE ? 'local' : publicGateway ? (PUBLIC_AI_ENABLED ? 'pending' : 'local') : 'ai')
  const [mode, setMode] = useState<Mode>(!AI_FEATURE_AVAILABLE ? 'fallback' : publicGateway ? 'choice' : 'connecting')
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(true)
  const [streaming, setStreaming] = useState('')

  const clientRef = useRef<AcpClient | null>(null)
  const guideRef = useRef<FallbackGuide | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const startedRef = useRef(false)
  const aliveRef = useRef(true)
  const requestRef = useRef<AbortController | null>(null)
  const sendingRef = useRef(false)

  const speech = useSpeech((text) => setInput((prev) => (prev ? prev + ' ' : '') + text))

  const push = (m: ChatMessage) => setMessages((prev) => [...prev, m])

  useEffect(() => () => {
    aliveRef.current = false
    requestRef.current?.abort()
  }, [])

  // 自动滚动到底部
  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages, streaming])

  // 初始化：连接 ACP 或启用兜底引导
  useEffect(() => {
    if (choice === 'pending') {
      setGatewayConsent(false)
      return
    }
    if (startedRef.current) return
    startedRef.current = true
    let alive = true

    const boot = async () => {
      if (!AI_FEATURE_AVAILABLE || choice === 'local') {
        setGatewayConsent(false)
        startFallback()
        setBusy(false)
        return
      }
      if (publicGateway) {
        setGatewayConsent(choice === 'ai')
        try {
          setMode('gateway')
          const controller = new AbortController()
          requestRef.current = controller
          const full = await gatewayOpening(draft, { signal: controller.signal })
          if (!alive) return
          push({ role: 'ai', text: full, ts: Date.now() })
          setBusy(false)
          return
        } catch {
          if (!alive) return
          // A public gateway outage should feel the same as an offline visit.
          setGatewayConsent(false)
          startFallback()
          setBusy(false)
          return
        }
      }

      const client = await ensureAcp()
      if (!alive) return
      if (client) {
        clientRef.current = client
        setMode('acp')
        try {
          let acc = ''
          setStreaming(' ')
          const full = await client.prompt(buildOpeningPrompt(draft), (d) => {
            acc += d
            if (alive) setStreaming(acc)
          })
          if (!alive) return
          setStreaming('')
          push({ role: 'ai', text: full.trim(), ts: Date.now() })
        } catch {
          if (!alive) return
          setStreaming('')
          startFallback()
        }
      } else {
        startFallback()
      }
      if (alive) setBusy(false)
    }

    const startFallback = () => {
      const g = new FallbackGuide(draft.timeMark ?? '过去的某一天')
      guideRef.current = g
      setMode('fallback')
      push({ role: 'ai', text: g.opening(), ts: Date.now() })
    }

    void boot()
    return () => {
      alive = false
      requestRef.current?.abort()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [choice])

  const send = async () => {
    const text = input.trim()
    if (!text || busy || sendingRef.current) return
    sendingRef.current = true
    setInput('')
    push({ role: 'user', text, ts: Date.now() })
    setBusy(true)

    // A request to stop never waits for a network response or another question.
    if (wantsToPause(text)) {
      setGatewayConsent(false)
      const guide = guideRef.current ?? new FallbackGuide(draft.timeMark ?? '过去的某一天')
      guideRef.current = guide
      setMode('fallback')
      push({ role: 'ai', text: guide.next(text), ts: Date.now() })
      setBusy(false)
      sendingRef.current = false
      return
    }

    if (AI_FEATURE_AVAILABLE && mode === 'acp' && clientRef.current) {
      try {
        let acc = ''
        setStreaming(' ')
        const full = await clientRef.current.prompt(text, (d) => {
          acc += d
          if (aliveRef.current) setStreaming(acc)
        })
        if (!aliveRef.current) return
        setStreaming('')
        push({ role: 'ai', text: full.trim(), ts: Date.now() })
      } catch {
        if (!aliveRef.current) return
        setStreaming('')
        // ACP 中途失败 → 切换兜底
        const g = new FallbackGuide(draft.timeMark ?? '过去的某一天')
        guideRef.current = g
        setMode('fallback')
        push({ role: 'ai', text: g.next(text), ts: Date.now() })
      }
    } else if (AI_FEATURE_AVAILABLE && mode === 'gateway') {
      try {
        const transcript = [...messages, { role: 'user' as const, text, ts: Date.now() }]
        const controller = new AbortController()
        requestRef.current = controller
        const full = await gatewayResponse(draft, transcript, text, { signal: controller.signal })
        if (!aliveRef.current) return
        push({ role: 'ai', text: full, ts: Date.now() })
      } catch {
        if (!aliveRef.current) return
        setGatewayConsent(false)
        const g = new FallbackGuide(draft.timeMark ?? '过去的某一天')
        guideRef.current = g
        setMode('fallback')
        push({ role: 'ai', text: g.next(text), ts: Date.now() })
      }
    } else if (guideRef.current) {
      // 模拟一点思考时间，让节奏更柔和
      await new Promise((r) => setTimeout(r, 900 + Math.random() * 600))
      if (!aliveRef.current) return
      push({ role: 'ai', text: guideRef.current.next(text), ts: Date.now() })
    }
    setBusy(false)
    sendingRef.current = false
  }

  const userSpoke = messages.some((m) => m.role === 'user')

  return (
    <div className="screen">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 离开
        </button>
        <span className="eyebrow">{draft.timeMark}</span>
        <span className="hint" style={{ width: 48, textAlign: 'right' }}>
          {mode === 'acp' || mode === 'gateway' ? 'AI' : mode === 'fallback' ? '引导' : mode === 'choice' ? '' : '…'}
        </span>
      </div>

      <div className="chat-list" ref={listRef}>
        {AI_FEATURE_AVAILABLE && mode === 'choice' && (
          <div className="glass" style={{ padding: 24, marginTop: 20 }}>
            <h1 className="title" style={{ fontSize: 22 }}>想怎么聊？</h1>
            <p className="subtitle" style={{ margin: '14px 0 20px' }}>
              本地引导不上传文字。开启 AI 后，本次情绪、时间和对话会发送给 MiniMax，用于回应与整理日记。
            </p>
            <button className="btn btn-primary" onClick={() => setChoice('local')}>使用本地引导</button>
            <button className="btn btn-ghost" style={{ marginTop: 10 }} onClick={() => setChoice('ai')}>同意并开启 AI</button>
          </div>
        )}
        {mode === 'connecting' && (
          <div className="bubble ai">
            <span className="hint">正在点亮回忆的灯…</span>
            <span className="typing-dots" style={{ marginLeft: 8 }}>
              <i />
              <i />
              <i />
            </span>
          </div>
        )}
        {messages.map((m, i) => (
          <div key={i} className={`bubble ${m.role}`}>
            {m.text}
          </div>
        ))}
        {streaming && (
          <div className="bubble ai">
            {streaming.trim() || (
              <span className="typing-dots">
                <i />
                <i />
                <i />
              </span>
            )}
          </div>
        )}
        {busy && !streaming && mode !== 'connecting' && mode !== 'choice' && (
          <div className="bubble ai">
            <span className="typing-dots">
              <i />
              <i />
              <i />
            </span>
          </div>
        )}
      </div>

      {userSpoke && !busy && (
        <button
          className="btn"
          style={{ marginBottom: 12, borderColor: 'rgba(139,124,246,0.5)', color: '#c9befc' }}
          onClick={() => onFinish(messages, mode === 'acp' || mode === 'gateway')}
        >
          ✦ 沉淀这段回忆
        </button>
      )}

      {mode !== 'choice' && <div className="chat-input-bar glass">
        <textarea
          className="chat-input"
          rows={1}
          maxLength={GATEWAY_MAX_TEXT_LENGTH}
          placeholder={speech.listening ? speech.interim || '正在聆听…' : '说说那时的事…'}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault()
              void send()
            }
          }}
        />
        {speech.supported && (
          <button
            className={`icon-btn ${speech.listening ? 'rec' : ''}`}
            title={speech.listening ? '停止' : '语音输入'}
            onClick={() => (speech.listening ? speech.stop() : speech.start())}
          >
            {speech.listening ? '◼' : '🎙'}
          </button>
        )}
        <button className="icon-btn" onClick={() => void send()} disabled={busy || !input.trim()} title="发送">
          ↑
        </button>
      </div>}
    </div>
  )
}
