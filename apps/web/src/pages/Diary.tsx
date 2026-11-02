import { useEffect, useRef, useState } from 'react'
import { ensureAcp } from '../lib/acp'
import { gatewayDiary, hasGatewayConsent, setGatewayConsent } from '../lib/gateway'
import { buildDiaryPrompt, fallbackDiary } from '../lib/guide'
import { AI_FEATURE_AVAILABLE } from '../lib/aiAvailability'
import type { Draft } from '../types'

interface Props {
  draft: Draft
  onSave: (diary: string | undefined, diaryEnabled: boolean) => void
  onBack: () => void
}

export function Diary({ draft, onSave, onBack }: Props) {
  const [enabled, setEnabled] = useState(true)
  const [diary, setDiary] = useState('')
  const [generating, setGenerating] = useState(true)
  const [editing, setEditing] = useState(false)
  const generatedRef = useRef(false)

  useEffect(() => {
    if (!enabled || generatedRef.current) return
    let alive = true
    const controller = new AbortController()

    const complete = (text: string) => {
      if (!alive) return
      setDiary(text)
      generatedRef.current = true
      setGenerating(false)
    }

    const gen = async () => {
      setGenerating(true)
      if (!AI_FEATURE_AVAILABLE) {
        setGatewayConsent(false)
        complete(fallbackDiary(draft))
        return
      }
      if (import.meta.env.PROD && window.location.protocol.startsWith('http')) {
        if (!hasGatewayConsent()) {
          complete(fallbackDiary(draft))
          return
        }
        try {
          complete(await gatewayDiary(draft, { signal: controller.signal }))
        } catch {
          if (alive) {
            setGatewayConsent(false)
            complete(fallbackDiary(draft))
          }
        }
        return
      }

      const client = await ensureAcp()
      if (!alive) return
      if (client) {
        try {
          let acc = ''
          const full = await client.prompt(buildDiaryPrompt(draft), (d) => {
            acc += d
            if (alive) setDiary(acc)
          })
          if (!alive) return
          complete(full.trim())
        } catch {
          complete(fallbackDiary(draft))
        }
      } else {
        complete(fallbackDiary(draft))
      }
    }

    void gen()
    return () => {
      alive = false
      controller.abort()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled])

  return (
    <div className="screen screen-scroll">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 返回对话
        </button>
        <span className="eyebrow">{draft.timeMark}</span>
        <span style={{ width: 68 }} />
      </div>

      <div style={{ textAlign: 'center', marginBottom: 20 }}>
        <h1 className="title">显影这段回忆</h1>
        <p className="subtitle" style={{ marginTop: 8 }}>
          把你说的，留下来。
        </p>
      </div>

      <div className="switch-row glass" style={{ marginBottom: 18 }}>
        <div>
          <div style={{ fontSize: 14.5 }}>沉淀为日记</div>
          <div className="hint">关闭则只保留对话记录</div>
        </div>
        <button
          className={`switch ${enabled ? 'on' : ''}`}
          onClick={() => setEnabled((v) => !v)}
          aria-label="沉淀为日记"
        >
          <i />
        </button>
      </div>

      {enabled && (
        <div className="diary-paper fade-in" style={{ marginBottom: 20 }}>
          {generating && !diary ? (
            <span className="hint">
              回忆正在显影
              <span className="typing-dots" style={{ marginLeft: 8 }}>
                <i />
                <i />
                <i />
              </span>
            </span>
          ) : editing ? (
            <textarea className="diary-edit" value={diary} onChange={(e) => setDiary(e.target.value)} />
          ) : (
            diary
          )}
        </div>
      )}

      {enabled && !generating && (
        <button className="btn btn-ghost" style={{ marginBottom: 12 }} onClick={() => setEditing((v) => !v)}>
          {editing ? '完成编辑' : '修改一下措辞'}
        </button>
      )}

      <button
        className="btn btn-primary"
        disabled={enabled && generating}
        onClick={() => onSave(enabled ? diary : undefined, enabled)}
      >
        收进回忆
      </button>
    </div>
  )
}
