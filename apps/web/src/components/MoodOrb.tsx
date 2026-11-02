import { useEffect, useRef, useState } from 'react'
import { createGlassyOrbRenderer, type GlassyOrbRenderer } from './glassyOrbRenderer'
import { MoodExpression } from './MoodExpression'
import { getMoodVisual, type MoodVisual } from './moodEmotionModel'
import { echoMoodColorsF, moodColorsF } from './moodOrbModel'
import type { MoodId } from '../types'

export { moodColors } from './moodOrbModel'

interface Props {
  valence: number
  size?: number
  /** 拨盘旋转角（度），驱动晶体内部星云转动 */
  spin?: number
  /** 选中档位时的脉冲动画 */
  pulse?: boolean
  /** 独立回响深空 Demo 使用低饱和月银配色。 */
  tone?: 'default' | 'echo'
  /** 具名情绪使用离散色彩和手绘表情；缺省时保持旧版纯玻璃球。 */
  emotionId?: MoodId
}

type RendererStatus = 'pending' | 'webgl' | 'fallback'

/** WebGL 宇宙玻璃情绪球，不可用时自动回退到 CSS 晶体球。 */
export function MoodOrb({
  valence,
  size = 200,
  spin = 0,
  pulse = false,
  tone = 'default',
  emotionId,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const rendererRef = useRef<GlassyOrbRenderer | null>(null)
  const [rendererStatus, setRendererStatus] = useState<RendererStatus>('pending')
  const [leavingMood, setLeavingMood] = useState<MoodVisual>()
  const previousMoodRef = useRef<MoodVisual | undefined>(undefined)
  const mood = emotionId ? getMoodVisual(emotionId) : undefined
  const palette = mood?.palette ?? (tone === 'echo' ? echoMoodColorsF(valence) : moodColorsF(valence))
  const [main, deep, light] = palette
  const effectiveSpin = spin + (mood?.spinOffset ?? 0)
  const silverTone = tone === 'echo' && !mood

  useEffect(() => {
    const previous = previousMoodRef.current
    previousMoodRef.current = mood
    if (!previous || !mood || previous.id === mood.id) return
    setLeavingMood(previous)
    const timer = window.setTimeout(() => setLeavingMood(undefined), 520)
    return () => window.clearTimeout(timer)
  }, [mood])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    rendererRef.current = createGlassyOrbRenderer(
      canvas,
      () => setRendererStatus('webgl'),
      (error) => {
        setRendererStatus('fallback')
        if (import.meta.env.DEV) console.warn('[MoodOrb] WebGL fallback', error)
      },
    )
    return () => {
      rendererRef.current?.destroy()
      rendererRef.current = null
    }
  }, [])

  useEffect(() => {
    rendererRef.current?.update({
      palette: [main, deep, light],
      spin: effectiveSpin,
      pulse,
      silverTone,
      dynamics: mood?.dynamics,
    })
  }, [main, deep, light, effectiveSpin, pulse, silverTone, mood])

  return (
    <div
      className={`corb ${pulse ? 'corb-pulse' : ''}`}
      data-orb-status={rendererStatus}
      data-orb-mood={emotionId}
      style={{ width: size, height: size }}
    >
      <div
        className="corb-halo"
        style={{ background: `radial-gradient(circle, ${main}77 0%, ${deep}33 45%, transparent 70%)` }}
      />

      <canvas
        ref={canvasRef}
        className={`corb-canvas ${rendererStatus === 'webgl' ? 'is-ready' : ''}`}
        data-orb-renderer={rendererStatus}
        aria-hidden="true"
      />

      <div className={`corb-fallback ${rendererStatus === 'webgl' ? 'is-hidden' : ''}`} aria-hidden="true">
        <div
          className="corb-body"
          style={{
            background: `radial-gradient(circle at 34% 30%, ${light}, ${main} 52%, ${deep} 88%)`,
            boxShadow: [
              `0 0 60px ${main}66`,
              `0 0 130px ${deep}44`,
              `inset -18px -26px 50px ${deep}dd`,
              'inset 14px 18px 42px rgba(255,255,255,0.18)',
              'inset 0 0 12px rgba(255,255,255,0.10)',
            ].join(', '),
          }}
        >
          <div className="corb-nebula-spin" style={{ transform: `rotate(${effectiveSpin}deg)` }}>
            <div
              className="corb-nebula"
              style={{
                background: `conic-gradient(from 40deg, ${main}00, ${light}66 90deg, ${main}00 160deg, ${deep}88 240deg, ${main}00 330deg)`,
              }}
            />
          </div>
          <div className="corb-depth" style={{ background: `radial-gradient(circle at 50% 78%, ${deep}cc, transparent 55%)` }} />
          <div className="corb-refract" style={{ background: `radial-gradient(circle at 70% 62%, ${light}44, transparent 42%)` }} />
          <div className="corb-spec" />
          <div className="corb-spec2" style={{ background: `radial-gradient(ellipse, ${light}88, transparent 65%)` }} />
          <div className="corb-arc" />
        </div>
      </div>

      {leavingMood && <MoodExpression key={`leaving-${leavingMood.id}`} mood={leavingMood} phase="exit" />}
      {mood && <MoodExpression key={mood.id} mood={mood} phase="enter" />}

      <div className="corb-caustic" style={{ background: `radial-gradient(ellipse, ${main}55, transparent 65%)` }} />
    </div>
  )
}
