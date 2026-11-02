import type { CSSProperties } from 'react'

import type { MoodId } from '../types'
import { ECHO_MOODS } from './moodEmotionModel'
import {
  getMoodOrbAsset,
  MOOD_ORB_SHEET_PANEL_COUNT,
  MOOD_ORB_VIEWPORT_HEIGHT,
  MOOD_ORB_VIEWPORT_WIDTH,
  moodOrbSheetLeftPercent,
} from './moodOrbAssets'

export interface MoodPlanetImageProps {
  moodId: MoodId
  alt?: string
  className?: string
  size?: CSSProperties['width']
  style?: CSSProperties
}

export function MoodPlanetImage({
  moodId,
  alt,
  className,
  size = '100%',
  style,
}: MoodPlanetImageProps) {
  const asset = getMoodOrbAsset(moodId)
  const mood = ECHO_MOODS.find(({ id }) => id === moodId)

  return (
    <span
      className={className}
      style={{
        ...style,
        position: 'relative',
        display: 'inline-block',
        width: size,
        aspectRatio: `${MOOD_ORB_VIEWPORT_WIDTH} / ${MOOD_ORB_VIEWPORT_HEIGHT}`,
        overflow: 'hidden',
        lineHeight: 0,
      }}
    >
      <img
        src={asset.sheet}
        alt={alt ?? `${mood?.label ?? moodId}情绪星球`}
        draggable={false}
        style={{
          position: 'absolute',
          top: 0,
          left: `${moodOrbSheetLeftPercent(asset)}%`,
          display: 'block',
          width: `${MOOD_ORB_SHEET_PANEL_COUNT * 100}%`,
          height: '100%',
          maxWidth: 'none',
        }}
      />
    </span>
  )
}
