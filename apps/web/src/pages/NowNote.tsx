import { useState } from 'react'
import { MoodOrb } from '../components/MoodOrb'
import { MoodPlanetImage } from '../components/MoodPlanetImage'
import type { MoodState } from '../types'

interface Props {
  mood: MoodState
  onSave: (note: string) => void
  onBack: () => void
}

export function NowNote({ mood, onSave, onBack }: Props) {
  const [note, setNote] = useState('')

  return (
    <div className="screen screen-scroll">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 返回
        </button>
      </div>

      <div style={{ textAlign: 'center' }}>
        <h1 className="title">记下此刻</h1>
        <p className="subtitle" style={{ marginTop: 10 }}>
          写一句，或留空。
        </p>
      </div>

      {mood.emotionId ? (
        <MoodPlanetImage moodId={mood.emotionId} size={120} />
      ) : (
        <MoodOrb valence={mood.valence} size={120} />
      )}

      <textarea
        className="note-input"
        placeholder="此刻想说点什么吗…（可留空）"
        value={note}
        onChange={(e) => setNote(e.target.value)}
      />

      <button className="btn btn-primary" style={{ marginTop: 22 }} onClick={() => onSave(note.trim())}>
        收藏这一刻
      </button>
    </div>
  )
}
