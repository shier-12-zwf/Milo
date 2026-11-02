import { useRef, useState, type KeyboardEvent } from 'react'
import { MoodOrb } from '../components/MoodOrb'
import { MoodOrbitCarousel } from '../components/MoodOrbitCarousel'
import { MoodPlanetImage } from '../components/MoodPlanetImage'
import { activeMoodIndex, nearestMoodPosition } from '../components/moodSwipeModel'
import {
  DEFAULT_ECHO_SELECTOR_INDEX,
  ECHO_SELECTOR_MOODS,
  getMoodDescriptorWords,
  moodPolarity,
} from '../components/moodTaxonomyModel'
import { triggerTapHaptic } from '../lib/haptics'
import { useMoodSwipe, type MoodSwipePhase } from '../lib/useMoodSwipe'
import { useRotary } from '../lib/useRotary'
import type { MoodState } from '../types'

const VALENCE_TEXT: Record<number, string> = {
  [-3]: '非常低落',
  [-2]: '低落',
  [-1]: '有些沉',
  [0]: '平静',
  [1]: '还不错',
  [2]: '明亮',
  [3]: '雀跃',
}

const DIAL = 300 // 拨盘直径
const WORD_R = 136 // 词环半径

interface Props {
  echoVoid?: boolean
  onNext: (mood: MoodState) => void
  onTimeline: () => void
  entryCount: number
}

export function Home({ echoVoid = false, onNext, onTimeline, entryCount }: Props) {
  const [step, setStep] = useState<'feel' | 'word'>('feel')
  const primaryActionClass = echoVoid ? 'btn btn-primary echo-confirm' : 'btn btn-primary'

  /* ---- 第一步：旋转调整整体感受 ---- */
  const [angle, setAngle] = useState(0) // -270..270，每 90° 一档
  const [echoPosition, setEchoPosition] = useState(DEFAULT_ECHO_SELECTOR_INDEX)
  const [echoPhase, setEchoPhase] = useState<MoodSwipePhase | 'idle'>('idle')
  const [orbitExpanded, setOrbitExpanded] = useState(true)
  const [pulse, setPulse] = useState(false)
  const prevLevel = useRef(0)
  const prevEchoMoodIndex = useRef(DEFAULT_ECHO_SELECTOR_INDEX)

  const valence = angle / 90 // 连续值 -3..3
  const level = Math.max(-3, Math.min(3, Math.round(valence)))
  const echoMoodIndex = activeMoodIndex(echoPosition, ECHO_SELECTOR_MOODS.length)
  const echoMood = ECHO_SELECTOR_MOODS[echoMoodIndex]
  const selectedMood = {
    valence: echoVoid ? echoMood.valence : level,
    ...(echoVoid ? { emotionId: echoMood.id } : {}),
  }
  const descriptorWords = getMoodDescriptorWords(selectedMood)
  const descriptorPolarity = moodPolarity(selectedMood)
  const wordStepAngle = 360 / descriptorWords.length

  const feelDial = useRotary((d) => {
    setAngle((a) => {
      const next = Math.max(-270, Math.min(270, a + d))
      const lv = Math.round(next / 90)
      if (lv !== prevLevel.current) {
        prevLevel.current = lv
        navigator.vibrate?.(8)
        setLabels([])
        setPulse(true)
        setTimeout(() => setPulse(false), 450)
      }
      return next
    })
  })

  const updateEchoPosition = (position: number, phase: MoodSwipePhase) => {
    const nextIndex = activeMoodIndex(position, ECHO_SELECTOR_MOODS.length)
    if (nextIndex !== prevEchoMoodIndex.current) {
      prevEchoMoodIndex.current = nextIndex
      navigator.vibrate?.(8)
      setLabels([])
    }
    setEchoPosition(position)
    setEchoPhase(phase)
  }

  const selectEchoMood = (index: number) => {
    setOrbitExpanded(true)
    const nextPosition = nearestMoodPosition(echoPosition, index, ECHO_SELECTOR_MOODS.length)
    updateEchoPosition(nextPosition, 'settling')
  }

  const moodSwipe = useMoodSwipe(
    echoPosition,
    updateEchoPosition,
    ECHO_SELECTOR_MOODS.length,
    !echoVoid || step !== 'feel',
  )

  const handleMoodKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (!echoVoid || step !== 'feel') return
    if (event.key === 'ArrowLeft') {
      event.preventDefault()
      selectEchoMood(echoMoodIndex + 1)
    } else if (event.key === 'ArrowRight') {
      event.preventDefault()
      selectEchoMood(echoMoodIndex - 1)
    }
  }

  /* ---- 第二步：词环旋转选词 ---- */
  const [ringAngle, setRingAngle] = useState(0)
  const [smooth, setSmooth] = useState(false)
  const [labels, setLabels] = useState<string[]>([])

  const wordDial = useRotary(
    (d) => {
      setSmooth(false)
      setRingAngle((a) => a + d)
    },
    () => {
      // 松手后吸附到最近的词位
      setSmooth(true)
      setRingAngle((a) => Math.round(a / wordStepAngle) * wordStepAngle)
    },
  )

  const norm = (a: number) => ((a % 360) + 360) % 360
  // 顶部（-90°）对准的词
  const focusIdx = (() => {
    let best = 0
    let bestDiff = 361
    for (let i = 0; i < descriptorWords.length; i++) {
      const a = norm(i * wordStepAngle - 90 + ringAngle)
      const diff = Math.min(Math.abs(a - 270), 360 - Math.abs(a - 270))
      if (diff < bestDiff) {
        bestDiff = diff
        best = i
      }
    }
    return best
  })()

  const toggleWord = (word: string) => {
    const next = labels.includes(word)
      ? labels.filter((label) => label !== word)
      : labels.length < 3
        ? [...labels, word]
        : labels

    if (next !== labels) {
      triggerTapHaptic()
      setLabels(next)
    }
  }

  return (
    <div className={`screen screen-scroll ${echoVoid ? 'screen--echo-void' : ''}`}>
      <div className="topbar">
        <div className="eyebrow">Milo-米洛</div>
        {step === 'feel' ? (
          <button className="back-link" onClick={onTimeline}>
            回忆 {entryCount > 0 ? `· ${entryCount}` : ''}
          </button>
        ) : (
          <button className="back-link" onClick={() => setStep('feel')}>
            ← 重新感受
          </button>
        )}
      </div>

      {step === 'feel' ? (
        <>
          {/* 拨盘 */}
          <div
            ref={echoVoid ? moodSwipe : feelDial}
            className={`dial ${echoVoid ? 'echo-feel-dial' : ''}`}
            data-mood-swipe={echoVoid ? true : undefined}
            data-mood-drag-surface={echoVoid ? true : undefined}
            aria-label={echoVoid ? '沿圆环旋转切换此刻的感受' : '旋转选择此刻的感受'}
            role={echoVoid ? 'slider' : undefined}
            tabIndex={echoVoid ? 0 : undefined}
            aria-valuemin={echoVoid ? 1 : undefined}
            aria-valuemax={echoVoid ? ECHO_SELECTOR_MOODS.length : undefined}
            aria-valuenow={echoVoid ? echoMoodIndex + 1 : undefined}
            aria-valuetext={echoVoid ? echoMood.label : undefined}
            onKeyDown={handleMoodKeyDown}
            style={{ width: DIAL, height: DIAL, marginTop: 26 }}
          >
            <div className="dial-ring" />
            <div
              className="dial-dot"
              style={{ transform: `rotate(${angle}deg) translateY(-${DIAL / 2 - 7}px)` }}
            />
            {echoVoid ? (
              <MoodOrbitCarousel
                position={echoPosition}
                activeIndex={echoMoodIndex}
                phase={echoPhase}
                expanded={orbitExpanded}
                onSelect={selectEchoMood}
                onExpandedChange={setOrbitExpanded}
              />
            ) : (
              <div className="dial-orb-center">
                <MoodOrb valence={valence} size={188} spin={angle * 1.6} pulse={pulse} />
              </div>
            )}
          </div>

          {echoVoid ? (
            <>
              <div
                className="echo-mood-label"
                data-mood-level={echoMood.valence}
                data-mood-id={echoMood.id}
                aria-live="polite"
              >
                <span>{echoMood.label}</span>
              </div>
              <div className="dial-hint echo-swipe-hint">
                沿圆环旋转，或点击任意情绪直接切换
              </div>
            </>
          ) : (
            <>
              <div style={{ textAlign: 'center', marginTop: 26, minHeight: 44 }}>
                <span className="title" style={{ fontSize: 24 }}>
                  {VALENCE_TEXT[level]}
                </span>
              </div>
              <div className="dial-hint" style={{ marginTop: 8, marginBottom: 26 }}>
                <span className="arc">⟳</span>
                <span>沿着光环旋转，找到此刻的感受</span>
              </div>
            </>
          )}

          <button className={primaryActionClass} onClick={() => setStep('word')}>
            就是这种感觉
          </button>
        </>
      ) : (
        <>
          <div style={{ textAlign: 'center', marginTop: 6 }}>
            <h1 className="title" style={{ fontSize: 22 }}>
              如果要给它一个名字
            </h1>
          </div>

          {/* 词环拨盘 */}
          <div
            ref={wordDial}
            className="dial"
            data-descriptor-polarity={descriptorPolarity}
            data-selected-mood-id={selectedMood.emotionId}
            style={{ width: DIAL + 60, height: DIAL + 60, marginTop: 30 }}
          >
            <div
              style={{
                position: 'absolute',
                inset: 0,
                display: 'grid',
                placeItems: 'center',
                pointerEvents: 'none',
              }}
            >
              {echoVoid ? (
                <MoodPlanetImage className="echo-word-orb" moodId={echoMood.id} size={144} />
              ) : (
                <MoodOrb valence={valence} size={118} spin={ringAngle * 1.4} />
              )}
            </div>
            <div className="word-ring">
              {descriptorWords.map((w, i) => {
                const a = ((i * wordStepAngle - 90 + ringAngle) * Math.PI) / 180
                const x = Math.cos(a) * WORD_R
                const y = Math.sin(a) * WORD_R
                const cls = [
                  'word-item',
                  i === focusIdx ? 'focus' : '',
                  labels.includes(w) ? 'picked' : '',
                  smooth ? 'smooth' : '',
                ]
                  .filter(Boolean)
                  .join(' ')
                return (
                  <button
                    type="button"
                    key={w}
                    className={cls}
                    style={{ transform: `translate(-50%, -50%) translate(${x}px, ${y}px)` }}
                    aria-pressed={labels.includes(w)}
                    onClick={() => toggleWord(w)}
                  >
                    {w}
                  </button>
                )
              })}
            </div>
          </div>

          <div className="dial-hint" style={{ marginTop: 18 }}>
            <span className="arc">⟳</span>
            <span>旋转词环，点选最多 3 个词</span>
          </div>

          <div style={{ textAlign: 'center', minHeight: 30, marginTop: 12, marginBottom: 14 }}>
            {labels.length > 0 && (
              <span className="subtitle" style={{ fontSize: 15, color: '#c9befc' }}>
                {labels.join(' · ')}
              </span>
            )}
          </div>

          <button
            className={primaryActionClass}
            onClick={() => onNext({
              valence: selectedMood.valence,
              labels,
              ...(selectedMood.emotionId ? { emotionId: selectedMood.emotionId } : {}),
            })}
          >
            继续
          </button>
          <p className="hint" style={{ textAlign: 'center', marginTop: 12 }}>
            不选也可以。
          </p>
        </>
      )}
    </div>
  )
}
