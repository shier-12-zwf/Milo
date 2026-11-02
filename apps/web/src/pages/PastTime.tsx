import { useState } from 'react'
import { triggerTapHaptic } from '../lib/haptics'

const PRESETS = [
  '昨天',
  '上个星期',
  '几个月前',
  '去年这个时候',
  '去年夏天',
  '几年前',
  '大学时光',
  '刚工作那会儿',
  '少年时代',
  '小时候',
]

interface Props {
  onNext: (timeMark: string) => void
  onBack: () => void
}

export function PastTime({ onNext, onBack }: Props) {
  const [picked, setPicked] = useState<string | null>(null)
  const [custom, setCustom] = useState('')

  const mark = custom.trim() || picked

  return (
    <div className="screen screen-scroll">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 返回
        </button>
      </div>

      <div style={{ textAlign: 'center', marginTop: 24, marginBottom: 40 }}>
        <h1 className="title">那是什么时候的事？</h1>
        <p className="subtitle" style={{ marginTop: 12 }}>
          不用记清日期，
          <br />
          大概就好。
        </p>
      </div>

      <div className="chips" style={{ marginBottom: 28 }}>
        {PRESETS.map((p) => (
          <button
            type="button"
            key={p}
            className={`chip ${picked === p && !custom.trim() ? 'on' : ''}`}
            aria-pressed={picked === p && !custom.trim()}
            onClick={() => {
              triggerTapHaptic()
              setPicked(p)
              setCustom('')
            }}
          >
            {p}
          </button>
        ))}
      </div>

      <input
        className="note-input past-time-input"
        placeholder="也可以写，比如「高三的雨季」"
        value={custom}
        onChange={(e) => setCustom(e.target.value)}
      />

      <button
        className="btn btn-primary"
        style={{ marginTop: 26 }}
        disabled={!mark}
        onClick={() => mark && onNext(mark)}
      >
        回到那时
      </button>
    </div>
  )
}
