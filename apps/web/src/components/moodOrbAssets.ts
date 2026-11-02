import type { MoodId } from '../types'

export interface MoodOrbAsset {
  readonly id: MoodId
  readonly sheet: string
  readonly panel: 0 | 1 | 2
  readonly focusOffsetPercent: number
}

export const MOOD_ORB_SHEET_PANEL_COUNT = 3
export const MOOD_ORB_VIEWPORT_WIDTH = 1748
export const MOOD_ORB_VIEWPORT_HEIGHT = 2700

const PANEL_FOCUS_OFFSETS = [-11, 0, 11] as const

function moodOrbAsset(
  id: MoodId,
  sheet: string,
  panel: 0 | 1 | 2,
  focusOffsetPercent: number = PANEL_FOCUS_OFFSETS[panel],
): Readonly<MoodOrbAsset> {
  return Object.freeze({ id, sheet, panel, focusOffsetPercent })
}

const VERY_LOW_LOW_HEAVY_SHEET = new URL(
  '../../../../docs/superpowers/concepts/mood-orbs/01-very-low-low-heavy-transparent.png',
  import.meta.url,
).href

const CALM_OKAY_BRIGHT_SHEET = new URL(
  '../../../../docs/superpowers/concepts/mood-orbs/02-calm-okay-bright-transparent.png',
  import.meta.url,
).href

const JOYFUL_LONELY_SAD_SHEET = new URL(
  '../../../../docs/superpowers/concepts/mood-orbs/03-joyful-lonely-sad-transparent.png',
  import.meta.url,
).href

const ANGRY_AFRAID_DISAPPOINTED_SHEET = new URL(
  '../../../../docs/superpowers/concepts/mood-orbs/04-angry-afraid-disappointed-transparent.png',
  import.meta.url,
).href

const ANXIOUS_AGGRIEVED_EMBARRASSED_SHEET = new URL(
  '../../../../docs/superpowers/concepts/mood-orbs/05-anxious-aggrieved-embarrassed-transparent.png',
  import.meta.url,
).href

export const MOOD_ORB_ASSETS: readonly Readonly<MoodOrbAsset>[] = Object.freeze([
  moodOrbAsset('very-low', VERY_LOW_LOW_HEAVY_SHEET, 0),
  moodOrbAsset('low', VERY_LOW_LOW_HEAVY_SHEET, 1),
  moodOrbAsset('heavy', VERY_LOW_LOW_HEAVY_SHEET, 2),
  moodOrbAsset('calm', CALM_OKAY_BRIGHT_SHEET, 0),
  moodOrbAsset('okay', CALM_OKAY_BRIGHT_SHEET, 1),
  moodOrbAsset('bright', CALM_OKAY_BRIGHT_SHEET, 2),
  moodOrbAsset('joyful', JOYFUL_LONELY_SAD_SHEET, 0),
  moodOrbAsset('lonely', JOYFUL_LONELY_SAD_SHEET, 1),
  moodOrbAsset('sad', JOYFUL_LONELY_SAD_SHEET, 2),
  moodOrbAsset('angry', ANGRY_AFRAID_DISAPPOINTED_SHEET, 0),
  moodOrbAsset('afraid', ANGRY_AFRAID_DISAPPOINTED_SHEET, 1),
  moodOrbAsset('disappointed', ANGRY_AFRAID_DISAPPOINTED_SHEET, 2),
  moodOrbAsset('anxious', ANXIOUS_AGGRIEVED_EMBARRASSED_SHEET, 0, -9),
  moodOrbAsset('aggrieved', ANXIOUS_AGGRIEVED_EMBARRASSED_SHEET, 1),
  moodOrbAsset('embarrassed', ANXIOUS_AGGRIEVED_EMBARRASSED_SHEET, 2),
])

export function moodOrbSheetLeftPercent(asset: Readonly<MoodOrbAsset>): number {
  return asset.panel * -100 + asset.focusOffsetPercent
}

export function getMoodOrbAsset(id: MoodId): Readonly<MoodOrbAsset> {
  const asset = MOOD_ORB_ASSETS.find((candidate) => candidate.id === id)

  if (!asset) {
    throw new Error(`Missing mood orb asset for mood: ${id}`)
  }

  return asset
}
