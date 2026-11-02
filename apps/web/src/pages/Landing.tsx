import { useState } from 'react'
import type { MoodId } from '../types'
import { CosmicSky } from '../components/CosmicSky'
import { PlanetSanctuary } from '../components/PlanetSanctuary'
import { MoodPlanetImage } from '../components/MoodPlanetImage'
import { ECHO_MOODS } from '../components/moodEmotionModel'
import { PUBLIC_AI_ENABLED } from '../lib/deployment'

const APP_PATH = './app'

export function Landing() {
  const [immersive, setImmersive] = useState(false)
  const [selectedMood, setSelectedMood] = useState<MoodId>('calm')
  const activeMood = ECHO_MOODS.find((mood) => mood.id === selectedMood) ?? ECHO_MOODS[3]

  return (
    <main className="landing-page landing-universe">
      <CosmicSky paused={immersive} />
      <nav className="landing-nav" aria-label="主导航">
        <a className="landing-brand" href="./" aria-label="Milo 米洛首页">
          <img className="landing-brand-logo" src="./favicon.png" alt="" width="36" height="36" />
          <span>
            <strong>Milo</strong>
            <em>米洛</em>
          </span>
        </a>
        <div className="landing-nav-links">
          <a href="#about">关于 Milo</a>
          <a href="#how">怎么开始</a>
          <a className="landing-nav-cta" href={APP_PATH}>
            打开 Web 端 <span aria-hidden="true">↗</span>
          </a>
        </div>
      </nav>

      <section className="landing-hero" aria-labelledby="landing-title">
        <div className="landing-hero-copy">
          <p className="landing-kicker"><span /> 星海很大，你有自己的小小归处</p>
          <h1 id="landing-title">
            今天的你，<br />
            <span>想说些什么？</span>
          </h1>
          <p className="landing-lead">
            Milo 是星海里，属于你的一间情绪小屋。让今天的感受有地方停靠，不急着解释，也不急着变好。
          </p>
          <div className="landing-actions">
            <a className="landing-primary" href={APP_PATH}>
              进入 Milo <span aria-hidden="true">→</span>
            </a>
            <a className="landing-secondary" href="#about">了解它 <span aria-hidden="true">↓</span></a>
          </div>
          <p className="landing-note">无需下载 · 打开即用 · 记录留在你的设备里</p>
        </div>

        <PlanetSanctuary selected={selectedMood} onSelect={setSelectedMood} onImmersiveChange={setImmersive} />

      </section>

      <section className="landing-trust" aria-label="产品特点">
        <span>为真实感受留白</span>
        <span>只属于你的片刻</span>
        <span>没有标准答案</span>
      </section>

      <section className="landing-section landing-moods" id="moods" aria-labelledby="moods-title">
        <div className="landing-section-heading landing-moods-heading">
          <div>
            <p className="landing-kicker"><span /> 情绪星球图鉴</p>
            <h2 id="moods-title">每一种感受，<br /><em>都有自己的光。</em></h2>
          </div>
          <p className="landing-moods-intro">十五颗星球，十五个小小的归处。选一颗像此刻的你，再去星空里看看它。</p>
        </div>
        <div className="landing-mood-gallery" aria-label="十五种情绪星球">
          {ECHO_MOODS.map((mood, index) => (
            <button
              type="button"
              className="landing-mood-card"
              data-polarity={mood.valence < 0 ? 'negative' : mood.valence > 0 ? 'positive' : 'neutral'}
              aria-label={`点亮${mood.label}星球`}
              aria-pressed={mood.id === selectedMood}
              onClick={() => setSelectedMood(mood.id)}
              key={mood.id}
            >
              <MoodPlanetImage moodId={mood.id} alt={`${mood.label}情绪星球`} size={108} className="landing-mood-planet" />
              <div className="landing-mood-meta">
                <span>{String(index + 1).padStart(2, '0')}</span>
                <strong>{mood.label}</strong>
              </div>
            </button>
          ))}
        </div>
        <div className="landing-mood-selection" aria-live="polite"><p>{activeMood.label}，也可以好好被看见。</p><button type="button" onClick={() => document.querySelector('.planet-hero-wrap')?.scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'center' })}>去看看这颗星球 ↑</button></div>
      </section>

      <section className="landing-section landing-about" id="about" aria-labelledby="about-title">
        <div className="landing-section-heading">
          <p className="landing-kicker"><span /> 为什么是 Milo</p>
          <h2 id="about-title">少一点打扰，<br /><em>多一点自我听见。</em></h2>
        </div>
        <div className="landing-feature-grid">
          <article className="landing-feature-card">
            <span className="landing-feature-index">01</span>
            <h3>从感受开始</h3>
            <p>不用先想好要写什么。拨动情绪，给此刻一个模糊但真实的名字。</p>
          </article>
          <article className="landing-feature-card landing-feature-card-highlight">
            <span className="landing-feature-index">02</span>
            <h3>让你多说一点</h3>
            <p>{PUBLIC_AI_ENABLED ? 'AI 只在需要时轻轻提问；没有 AI，也有安静、简短的陪伴。' : '用简短的提示陪你慢慢说，把更多空间留给你的感受。'}</p>
          </article>
          <article className="landing-feature-card">
            <span className="landing-feature-index">03</span>
            <h3>记在自己的地方</h3>
            <p>日记和回忆优先保存在你的设备中，什么时候想回看，都由你决定。</p>
          </article>
        </div>
      </section>

      <section className="landing-section landing-how" id="how" aria-labelledby="how-title">
        <div className="landing-how-copy">
          <p className="landing-kicker"><span /> 三个小动作</p>
          <h2 id="how-title">把今天，<br /><em>还给自己。</em></h2>
          <p>打开 Milo，花几分钟和自己待在一起。你可以只留下一个词，也可以慢慢写成一段故事。</p>
          <a className="landing-inline-link" href={APP_PATH}>现在就试试 <span aria-hidden="true">↗</span></a>
        </div>
        <ol className="landing-steps">
          <li><span>01</span><strong>感受</strong><em>此刻是什么颜色？</em></li>
          <li><span>02</span><strong>表达</strong><em>给它一个词，或一句话。</em></li>
          <li><span>03</span><strong>留下</strong><em>让这份记忆有地方回去。</em></li>
        </ol>
      </section>

      <section className="landing-final-cta" aria-labelledby="landing-final-title">
        <div>
          <p className="landing-kicker"><span /> 你的 Milo 时刻</p>
          <h2 id="landing-final-title">先不用想太多。<br /><em>从此刻开始。</em></h2>
        </div>
        <a className="landing-primary" href={APP_PATH}>打开 Web 端 <span aria-hidden="true">→</span></a>
      </section>

      <footer className="landing-footer">
        <span>© {new Date().getFullYear()} Milo-米洛</span>
        <a href="./privacy">隐私说明</a>
        <span>让情绪有地方落下</span>
      </footer>
    </main>
  )
}
