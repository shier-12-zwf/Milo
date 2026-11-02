import { useEntries } from '../store'
import { moodWord } from '../lib/guide'
import { moodPalette } from '../components/moodEmotionModel'
import type { Entry } from '../types'

interface Props {
  onOpen: (id: string) => void
  onBack: () => void
}

function fmtDate(ts: number): string {
  const d = new Date(ts)
  return `${d.getMonth() + 1} 月 ${d.getDate()} 日 ${String(d.getHours()).padStart(2, '0')}:${String(
    d.getMinutes(),
  ).padStart(2, '0')}`
}

function preview(e: Entry): string {
  const text = e.diary || e.note || e.transcript?.filter((m) => m.role === 'user').map((m) => m.text).join(' ') || ''
  return text.length > 64 ? text.slice(0, 64) + '…' : text || '（一次安静的记录）'
}

export function Timeline({ onOpen, onBack }: Props) {
  const entries = useEntries()

  return (
    <div className="screen screen-scroll">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 此刻
        </button>
        <span className="eyebrow">回忆长廊</span>
        <span style={{ width: 48 }} />
      </div>

      {entries.length === 0 ? (
        <div style={{ textAlign: 'center', marginTop: 120 }}>
          <p className="title" style={{ fontSize: 20 }}>
            这里还很安静
          </p>
          <p className="subtitle" style={{ marginTop: 12 }}>
            当你收藏了第一段感受，
            <br />
            它就会在这里亮起来。
          </p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {entries.map((e) => {
            const [c1] = moodPalette(e.mood.valence, e.mood.emotionId)
            return (
              <div key={e.id} className="entry-card glass" onClick={() => onOpen(e.id)}>
                <div className="entry-meta" style={{ marginBottom: 10 }}>
                  <span
                    style={{
                      width: 10,
                      height: 10,
                      borderRadius: '50%',
                      background: c1,
                      boxShadow: `0 0 10px ${c1}`,
                      display: 'inline-block',
                    }}
                  />
                  <span>{fmtDate(e.createdAt)}</span>
                  <span className={`tag ${e.kind}`}>{e.kind === 'past' ? e.timeMark ?? '过去' : '此刻'}</span>
                  <span className="tag">{moodWord(e.mood.valence, e.mood.emotionId)}</span>
                </div>
                <div style={{ fontSize: 14, lineHeight: 1.8, color: 'var(--ink-dim)' }}>{preview(e)}</div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
