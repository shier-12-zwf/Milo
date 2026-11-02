import { useState } from 'react'
import { getEntry, removeEntry } from '../store'
import { moodWord } from '../lib/guide'
import { MoodOrb } from '../components/MoodOrb'

interface Props {
  entryId: string
  onCard: (id: string) => void
  onBack: () => void
}

export function Detail({ entryId, onCard, onBack }: Props) {
  const entry = getEntry(entryId)
  const [showChat, setShowChat] = useState(false)

  if (!entry) {
    return (
      <div className="screen">
        <div className="topbar">
          <button className="back-link" onClick={onBack}>
            ← 返回
          </button>
        </div>
        <p className="subtitle" style={{ textAlign: 'center', marginTop: 100 }}>
          这段回忆已经飘走了。
        </p>
      </div>
    )
  }

  const d = new Date(entry.createdAt)
  const dateStr = `${d.getFullYear()} 年 ${d.getMonth() + 1} 月 ${d.getDate()} 日`

  return (
    <div className="screen screen-scroll">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 回忆长廊
        </button>
        <span className="eyebrow">{dateStr}</span>
        <button
          className="back-link"
          onClick={() => {
            if (confirm('要放下这段回忆吗？')) {
              removeEntry(entry.id)
              onBack()
            }
          }}
        >
          放下
        </button>
      </div>

      <div style={{ textAlign: 'center' }}>
        <h1 className="title">{entry.kind === 'past' ? entry.timeMark ?? '过去的某一天' : '此刻'}</h1>
        <p className="subtitle" style={{ marginTop: 6 }}>
          {moodWord(entry.mood.valence, entry.mood.emotionId)}
          {entry.mood.labels.length ? ` · ${entry.mood.labels.join(' · ')}` : ''}
        </p>
      </div>

      <MoodOrb valence={entry.mood.valence} emotionId={entry.mood.emotionId} size={110} />

      {entry.diary ? (
        <div className="diary-paper" style={{ marginBottom: 18 }}>
          {entry.diary}
        </div>
      ) : entry.note ? (
        <div className="diary-paper" style={{ marginBottom: 18 }}>
          {entry.note}
        </div>
      ) : null}

      {entry.transcript && entry.transcript.length > 0 && (
        <>
          <button className="btn btn-ghost" style={{ marginBottom: 12 }} onClick={() => setShowChat((v) => !v)}>
            {showChat ? '收起当时的对话' : '看看当时的对话'}
          </button>
          {showChat && (
            <div className="fade-in" style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 18 }}>
              {entry.transcript.map((m, i) => (
                <div key={i} className={`bubble ${m.role}`} style={{ alignSelf: m.role === 'user' ? 'flex-end' : 'flex-start' }}>
                  {m.text}
                </div>
              ))}
            </div>
          )}
        </>
      )}

      <button className="btn btn-primary" onClick={() => onCard(entry.id)}>
        生成回忆卡片
      </button>
    </div>
  )
}
