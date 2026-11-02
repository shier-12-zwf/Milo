interface Props {
  onNow: () => void
  onPast: () => void
  onBack: () => void
}

export function Classify({ onNow, onPast, onBack }: Props) {
  return (
    <div className="screen">
      <div className="topbar">
        <button className="back-link" onClick={onBack}>
          ← 返回
        </button>
      </div>

      <div style={{ textAlign: 'center', marginTop: 40, marginBottom: 48 }}>
        <h1 className="title">这份感受，来自哪里？</h1>
        <p className="subtitle" style={{ marginTop: 12 }}>
          此刻，或某段回忆。
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
        <button className="fork-card glass" onClick={onNow}>
          <h3>它属于此刻</h3>
          <p>记下现在的心情。</p>
        </button>

        <button
          className="fork-card glass"
          onClick={onPast}
          style={{
            borderColor: 'rgba(139, 124, 246, 0.4)',
            boxShadow: '0 0 40px rgba(139, 124, 246, 0.12)',
          }}
        >
          <h3 style={{ color: '#c9befc' }}>它来自过去的某一天</h3>
          <p>聊聊那段回忆。</p>
        </button>
      </div>
    </div>
  )
}
