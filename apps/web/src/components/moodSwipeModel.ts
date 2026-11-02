export type MoodSwipeDirection = -1 | 1

export const ECHO_MOOD_ROTARY_LOCK_PX = 6
export const ECHO_MOOD_MIN_TRACKING_RADIUS_PX = 28
export const ECHO_MOOD_ORBIT_TRAVEL_PX = 116
export const ECHO_MOOD_PROJECTION_MS = 140
export const ECHO_MOOD_MAX_FLING_STEPS = 2

export interface OrbitalMoodPose {
  visible: boolean
  x: number
  y: number
  scale: number
  opacity: number
  zIndex: number
}

export interface MoodOrbitTextPose {
  visible: boolean
  angle: number
  distance: number
  opacity: number
  scale: number
}

export interface MoodDragTargetDescriptor {
  readonly tagName?: string
  readonly isContentEditable?: boolean
  readonly allowsMoodDrag?: boolean
}

const INTERACTIVE_MOOD_TAGS = new Set(['a', 'button', 'input', 'label', 'select', 'textarea'])

export function isMoodDragStartAllowed(path: readonly MoodDragTargetDescriptor[]): boolean {
  if (path.some((target) => target.allowsMoodDrag === true)) return true
  return !path.some((target) => (
    target.isContentEditable === true
    || (target.tagName ? INTERACTIVE_MOOD_TAGS.has(target.tagName.toLowerCase()) : false)
  ))
}

export function shouldSuppressMoodClick(
  rotated: boolean,
  cancelled: boolean,
): boolean {
  return rotated && !cancelled
}

export function wrapMoodIndex(index: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) return 0
  return ((Math.round(index) % count) + count) % count
}

export function activeMoodIndex(position: number, count: number): number {
  return wrapMoodIndex(Math.round(position), count)
}

/** Screen-space polar angle; positive movement is clockwise. */
export function moodPointerAngle(
  x: number,
  y: number,
  centerX: number,
  centerY: number,
): number {
  return Math.atan2(y - centerY, x - centerX) * (180 / Math.PI)
}

/** Unwraps the ±180° seam so one circular gesture remains continuous. */
export function shortestMoodAngleDelta(fromDegrees: number, toDegrees: number): number {
  const delta = ((toDegrees - fromDegrees + 540) % 360) - 180
  return delta === -180 ? 180 : delta
}

export function moodPositionFromRotation(
  startPosition: number,
  rotationDegrees: number,
  count: number,
): number {
  if (!Number.isInteger(count) || count < 1) return startPosition
  return startPosition - rotationDegrees / (360 / count)
}

export function moodRotationTravelPx(rotationDegrees: number, radiusPx: number): number {
  if (!Number.isFinite(radiusPx) || radiusPx <= 0) return 0
  return Math.abs(rotationDegrees) * (Math.PI / 180) * radiusPx
}

export function nearestMoodPosition(position: number, targetIndex: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) return 0
  const wrappedTarget = wrapMoodIndex(targetIndex, count)
  const cycle = Math.round((position - wrappedTarget) / count)
  return wrappedTarget + cycle * count
}

function moodOrbitDistance(index: number, position: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) return 0
  return nearestMoodPosition(position, index, count) - position
}

/** Uses one unbounded rotation frame so every tick moves as part of the same rigid dial. */
export function moodTickAngle(index: number, position: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) return 180
  return 180 + (index - position) * (360 / count)
}

/** Every mood remains represented by a tick, with focus falling off into graphite silver. */
export function moodTickOpacity(index: number, position: number, count: number): number {
  const distance = Math.abs(moodOrbitDistance(index, position, count))
  return Math.max(0.22, 1 - distance * 0.3)
}

/** The collapsed ring keeps one focused word; expansion reveals the complete mood vocabulary. */
export function moodOrbitTextPose(
  index: number,
  position: number,
  count: number,
  expanded: boolean,
): MoodOrbitTextPose {
  const distance = moodOrbitDistance(index, position, count)
  const isActive = wrapMoodIndex(index, count) === activeMoodIndex(position, count)
  const focus = Math.max(0, 1 - Math.abs(distance))
  const opacity = expanded ? 0.56 + focus * 0.44 : isActive ? 1 : 0

  return {
    visible: opacity > 0.01,
    angle: moodTickAngle(index, position, count),
    distance,
    opacity,
    scale: 0.9 + focus * 0.1,
  }
}

export function projectMoodSnap(
  position: number,
  velocityStepsPerMs: number,
  projectionMs = ECHO_MOOD_PROJECTION_MS,
  maxSteps = ECHO_MOOD_MAX_FLING_STEPS,
): number {
  const projectedSteps = velocityStepsPerMs * projectionMs
  const boundedSteps = Math.max(-Math.abs(maxSteps), Math.min(Math.abs(maxSteps), projectedSteps))
  return Math.round(position + boundedSteps)
}

export function orbitalMoodPose(index: number, position: number, count: number): OrbitalMoodPose {
  const distance = nearestMoodPosition(position, index, count) - position
  const absoluteDistance = Math.abs(distance)
  const isActive = wrapMoodIndex(index, count) === activeMoodIndex(position, count)

  if (!isActive) {
    return {
      visible: false,
      x: distance * ECHO_MOOD_ORBIT_TRAVEL_PX,
      y: 0,
      scale: 0.96,
      opacity: 0,
      zIndex: 0,
    }
  }

  return {
    visible: true,
    x: distance * ECHO_MOOD_ORBIT_TRAVEL_PX,
    y: absoluteDistance * 10,
    scale: 1 - absoluteDistance * 0.14,
    opacity: 1,
    zIndex: 30,
  }
}

// Kept for the legacy seven-level rotary path while Echo mode uses continuous positions.
export function stepMoodLevel(current: number, direction: MoodSwipeDirection): number {
  const normalized = Math.max(-3, Math.min(3, Math.round(current)))
  if (direction === 1 && normalized === 3) return -3
  if (direction === -1 && normalized === -3) return 3
  return normalized + direction
}

export function stepMoodIndex(current: number, direction: MoodSwipeDirection, count: number): number {
  return wrapMoodIndex(Math.round(current) + direction, count)
}
