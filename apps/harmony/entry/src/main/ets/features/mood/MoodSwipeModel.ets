/**
 * Continuous-rotation gesture model for the home orbit. Verbatim port of
 * `apps/web/src/components/moodSwipeModel.ts` (the parts that have no DOM
 * dependency) so that Home's web and native modes share one math model.
 */

export type MoodSwipeDirection = -1 | 1;

export const ECHO_MOOD_ROTARY_LOCK_PX = 6;
export const ECHO_MOOD_MIN_TRACKING_RADIUS_PX = 28;
export const ECHO_MOOD_ORBIT_TRAVEL_PX = 116;
export const ECHO_MOOD_PROJECTION_MS = 140;
export const ECHO_MOOD_MAX_FLING_STEPS = 2;

export interface OrbitalMoodPose {
  visible: boolean;
  x: number;
  y: number;
  scale: number;
  opacity: number;
  zIndex: number;
}

export interface MoodOrbitTextPose {
  visible: boolean;
  angle: number;
  distance: number;
  opacity: number;
  scale: number;
}

/** Wrap an integer index around the orbit length. */
export function wrapMoodIndex(index: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) {
    return 0;
  }
  return ((Math.round(index) % count) + count) % count;
}

/** Which mood the dial is focused on at the given continuous position. */
export function activeMoodIndex(position: number, count: number): number {
  return wrapMoodIndex(Math.round(position), count);
}

/** Screen-space polar angle in degrees. 0° = right, +90° = down (clockwise). */
export function moodPointerAngle(
  x: number,
  y: number,
  centerX: number,
  centerY: number,
): number {
  return Math.atan2(y - centerY, x - centerX) * (180 / Math.PI);
}

/** Unwrap the ±180° seam so one circular gesture stays continuous. */
export function shortestMoodAngleDelta(fromDegrees: number, toDegrees: number): number {
  const delta = ((toDegrees - fromDegrees + 540) % 360) - 180;
  return delta === -180 ? 180 : delta;
}

/** Continuous position from a total rotation in degrees. */
export function moodPositionFromRotation(
  startPosition: number,
  rotationDegrees: number,
  count: number,
): number {
  if (!Number.isInteger(count) || count < 1) {
    return startPosition;
  }
  return startPosition - rotationDegrees / (360 / count);
}

/** Arc length on the dial that the user's finger has traversed. */
export function moodRotationTravelPx(rotationDegrees: number, radiusPx: number): number {
  if (!Number.isFinite(radiusPx) || radiusPx <= 0) {
    return 0;
  }
  return Math.abs(rotationDegrees) * (Math.PI / 180) * radiusPx;
}

/** Move a target index onto the cycle closest to the current position. */
export function nearestMoodPosition(position: number, targetIndex: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) {
    return 0;
  }
  const wrappedTarget = wrapMoodIndex(targetIndex, count);
  const cycle = Math.round((position - wrappedTarget) / count);
  return wrappedTarget + cycle * count;
}

function moodOrbitDistance(index: number, position: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) {
    return 0;
  }
  return nearestMoodPosition(position, index, count) - position;
}

/** Angle (degrees) for one tick. 180° = bottom of the dial (the focus point). */
export function moodTickAngle(index: number, position: number, count: number): number {
  if (!Number.isInteger(count) || count < 1) {
    return 180;
  }
  return 180 + (index - position) * (360 / count);
}

/** Tick opacity falls off into graphite silver as we move away from the focus. */
export function moodTickOpacity(index: number, position: number, count: number): number {
  const distance = Math.abs(moodOrbitDistance(index, position, count));
  return Math.max(0.22, 1 - distance * 0.3);
}

/** Pose for one label in the orbit text ring. */
export function moodOrbitTextPose(
  index: number,
  position: number,
  count: number,
  expanded: boolean,
): MoodOrbitTextPose {
  const distance = moodOrbitDistance(index, position, count);
  const isActive = wrapMoodIndex(index, count) === activeMoodIndex(position, count);
  const focus = Math.max(0, 1 - Math.abs(distance));
  const opacity = expanded ? 0.56 + focus * 0.44 : isActive ? 1 : 0;
  return {
    visible: opacity > 0.01,
    angle: moodTickAngle(index, position, count),
    distance: distance,
    opacity: opacity,
    scale: 0.9 + focus * 0.1,
  };
}

/** Where the dial should settle after a fling, bounded by max steps. */
export function projectMoodSnap(
  position: number,
  velocityStepsPerMs: number,
  projectionMs: number = ECHO_MOOD_PROJECTION_MS,
  maxSteps: number = ECHO_MOOD_MAX_FLING_STEPS,
): number {
  const projectedSteps = velocityStepsPerMs * projectionMs;
  const boundedSteps = Math.max(-Math.abs(maxSteps), Math.min(Math.abs(maxSteps), projectedSteps));
  return Math.round(position + boundedSteps);
}

/** Pose for the orb image of one mood; only the active mood is rendered. */
export function orbitalMoodPose(index: number, position: number, count: number): OrbitalMoodPose {
  const distance = nearestMoodPosition(position, index, count) - position;
  const absoluteDistance = Math.abs(distance);
  const isActive = wrapMoodIndex(index, count) === activeMoodIndex(position, count);
  if (!isActive) {
    return {
      visible: false,
      x: distance * ECHO_MOOD_ORBIT_TRAVEL_PX,
      y: 0,
      scale: 0.96,
      opacity: 0,
      zIndex: 0,
    };
  }
  return {
    visible: true,
    x: distance * ECHO_MOOD_ORBIT_TRAVEL_PX,
    y: absoluteDistance * 10,
    scale: 1 - absoluteDistance * 0.14,
    opacity: 1,
    zIndex: 30,
  };
}

/** Legacy seven-step rotary path. Echo uses continuous positions. */
export function stepMoodLevel(current: number, direction: MoodSwipeDirection): number {
  const normalized = Math.max(-3, Math.min(3, Math.round(current)));
  if (direction === 1 && normalized === 3) return -3;
  if (direction === -1 && normalized === -3) return 3;
  return normalized + direction;
}

/** Step the active mood by one slot. */
export function stepMoodIndex(current: number, direction: MoodSwipeDirection, count: number): number {
  return wrapMoodIndex(Math.round(current) + direction, count);
}
