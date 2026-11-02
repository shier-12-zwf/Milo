import type { CSSProperties } from 'react'

import type { MoodSwipePhase } from '../lib/useMoodSwipe'
import { MoodPlanetImage } from './MoodPlanetImage'
import { ECHO_SELECTOR_MOODS, polarityFromValence } from './moodTaxonomyModel'
import {
  moodOrbitTextPose,
  moodTickAngle,
  moodTickOpacity,
  orbitalMoodPose,
} from './moodSwipeModel'

const ORB_VIEWPORT_SIZE = 244

interface Props {
  position: number
  activeIndex: number
  phase: MoodSwipePhase | 'idle'
  expanded: boolean
  onSelect: (index: number) => void
  onExpandedChange: (expanded: boolean) => void
}

export function MoodOrbitCarousel({
  position,
  activeIndex,
  phase,
  expanded,
  onSelect,
  onExpandedChange,
}: Props) {
  const revealOrbit = () => onExpandedChange(true)
  const activeMood = ECHO_SELECTOR_MOODS[activeIndex]
  const pose = orbitalMoodPose(activeIndex, position, ECHO_SELECTOR_MOODS.length)
  const style: CSSProperties = {
    opacity: pose.opacity,
    zIndex: pose.zIndex,
    transform: `translate3d(calc(-50% + ${pose.x}px), calc(-50% + ${pose.y}px), 0) scale(${pose.scale})`,
  }
  const selectMood = (index: number) => {
    onExpandedChange(true)
    onSelect(index)
  }

  return (
    <div
      className={`mood-orbit-carousel is-${phase} ${expanded ? 'is-expanded' : 'is-collapsed'}`}
      data-orbit-phase={phase}
      data-orbit-expanded={expanded}
    >
      <div className="mood-orbit-lane" aria-hidden="true">
        <div key={activeMood.id} className="mood-orbit-item is-active" data-mood-id={activeMood.id} style={style}>
          <MoodPlanetImage moodId={activeMood.id} alt="" size={ORB_VIEWPORT_SIZE} />
        </div>
      </div>

      <button
        type="button"
        className="mood-orbit-toggle"
        data-mood-drag-surface="true"
        aria-label={expanded ? '情绪文字已展开' : '显示全部情绪'}
        aria-expanded={expanded}
        onPointerDown={revealOrbit}
        onClick={() => onExpandedChange(true)}
      >
        <span className="sr-only">{expanded ? '情绪文字已展开' : '显示全部情绪'}</span>
      </button>

      <div className="mood-orbit-texts" aria-live="off">
        {ECHO_SELECTOR_MOODS.map((mood, index) => {
          const textPose = moodOrbitTextPose(index, position, ECHO_SELECTOR_MOODS.length, expanded)
          const textStyle: CSSProperties = {
            opacity: textPose.opacity,
            transform: [
              'translate(-50%, -50%)',
              `rotate(${textPose.angle}deg)`,
              'translateY(-174px)',
              `rotate(${-textPose.angle}deg)`,
              `scale(${textPose.scale})`,
            ].join(' '),
          }
          return (
            <button
              key={mood.id}
              type="button"
              className="mood-orbit-text"
              data-active={index === activeIndex ? true : undefined}
              data-visible={textPose.visible ? true : undefined}
              data-polarity={polarityFromValence(mood.valence)}
              aria-label={`选择${mood.label}`}
              aria-pressed={index === activeIndex}
              aria-hidden={!textPose.visible}
              tabIndex={textPose.visible ? 0 : -1}
              style={textStyle}
              onClick={() => selectMood(index)}
            >
              {mood.label}
            </button>
          )
        })}
      </div>

      <div className="mood-orbit-steps" aria-label="全部情绪">
        {ECHO_SELECTOR_MOODS.map((mood, index) => {
          const tickStyle: CSSProperties = {
            opacity: moodTickOpacity(index, position, ECHO_SELECTOR_MOODS.length),
            transform: `translate(-50%, -50%) rotate(${moodTickAngle(index, position, ECHO_SELECTOR_MOODS.length)}deg) translateY(-143px)`,
          }
          return (
            <button
              key={mood.id}
              type="button"
              className="mood-orbit-step"
              data-active={index === activeIndex ? true : undefined}
              aria-label={`选择${mood.label}`}
              aria-pressed={index === activeIndex}
              style={tickStyle}
              onClick={() => selectMood(index)}
            >
              <span className="sr-only">{mood.label}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
