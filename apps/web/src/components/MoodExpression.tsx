import type { CSSProperties } from 'react'
import type { MoodStroke, MoodVisual } from './moodEmotionModel'

type MoodExpressionStyle = CSSProperties & {
  '--mood-ink': string
  '--mood-blush': string
  '--mood-accent': string
}

function StrokeGroup({ name, strokes }: { name: string; strokes: readonly MoodStroke[] }) {
  return (
    <g className={`mood-expression__${name}`}>
      {strokes.map((stroke, index) => (
        <path
          key={`${stroke.layer}-${index}-${stroke.d}`}
          className={`mood-stroke mood-stroke--${stroke.layer}`}
          d={stroke.d}
          fill={stroke.fill ? 'currentColor' : 'none'}
        />
      ))}
    </g>
  )
}

/** Decorative hand-drawn expression layer; the glass sphere remains a separate perfect circle. */
export function MoodExpression({ mood, phase = 'enter' }: { mood: MoodVisual; phase?: 'enter' | 'exit' }) {
  const style: MoodExpressionStyle = {
    '--mood-ink': mood.ink,
    '--mood-blush': mood.blush,
    '--mood-accent': mood.accent,
  }
  const blush = mood.accents.filter(({ layer }) => layer === 'blush')
  const accents = mood.accents.filter(({ layer }) => layer !== 'blush')
  const phaseClass = phase === 'exit' ? 'mood-expression--exit' : 'mood-expression--enter'

  return (
    <svg
      className={`mood-expression ${phaseClass} mood-expression--${mood.motion}`}
      viewBox="-24 -24 248 248"
      aria-hidden="true"
      style={style}
    >
      <StrokeGroup name="blush" strokes={blush} />
      <StrokeGroup name="face" strokes={[...mood.brows, ...mood.eyes, ...mood.mouth]} />
      <StrokeGroup name="hands" strokes={mood.hands} />
      <StrokeGroup name="accents" strokes={accents} />
    </svg>
  )
}
