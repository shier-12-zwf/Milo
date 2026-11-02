import assert from 'node:assert/strict'
import test from 'node:test'

import * as swipeModel from '../src/components/moodSwipeModel.ts'
import {
  activeMoodIndex,
  ECHO_MOOD_MAX_FLING_STEPS,
  ECHO_MOOD_MIN_TRACKING_RADIUS_PX,
  ECHO_MOOD_ORBIT_TRAVEL_PX,
  ECHO_MOOD_PROJECTION_MS,
  ECHO_MOOD_ROTARY_LOCK_PX,
  moodPointerAngle,
  moodPositionFromRotation,
  moodRotationTravelPx,
  nearestMoodPosition,
  moodOrbitTextPose,
  moodTickAngle,
  moodTickOpacity,
  orbitalMoodPose,
  projectMoodSnap,
  isMoodDragStartAllowed,
  shortestMoodAngleDelta,
  wrapMoodIndex,
} from '../src/components/moodSwipeModel.ts'

test('the active mood tick stays at the lower focus point while nearby ticks orbit it', () => {
  assert.equal(moodTickAngle(3, 3, 15), 180)
  assert.equal(moodTickAngle(4, 3, 15), 204)
  assert.equal(moodTickAngle(2, 3, 15), 156)
  assert.equal(moodTickOpacity(3, 3, 15), 1)
  assert.equal(moodTickOpacity(4, 3, 15), 0.7)
  assert.equal(moodTickOpacity(10, 3, 15), 0.22)
})

test('all ticks keep fixed spacing and rotate as one rigid dial', () => {
  const from = 3
  const to = nearestMoodPosition(from, 12, 15)
  const rotations = Array.from({ length: 15 }, (_, index) => (
    moodTickAngle(index, to, 15) - moodTickAngle(index, from, 15)
  ))

  assert.deepEqual([...new Set(rotations)], [144])
  assert.deepEqual(
    Array.from({ length: 14 }, (_, index) => (
      moodTickAngle(index + 1, to, 15) - moodTickAngle(index, to, 15)
    )),
    Array(14).fill(24),
  )
})

test('collapsed orbit text exposes only the active mood', () => {
  const active = moodOrbitTextPose(3, 3, 15, false)
  const neighbor = moodOrbitTextPose(4, 3, 15, false)

  assert.equal(active.visible, true)
  assert.equal(active.opacity, 1)
  assert.equal(active.angle, 180)
  assert.equal(neighbor.visible, false)
  assert.equal(neighbor.opacity, 0)
})

test('expanded orbit text reveals all fifteen moods while preserving a clear focus', () => {
  const poses = Array.from({ length: 15 }, (_, index) => moodOrbitTextPose(index, 3, 15, true))
  const active = poses[3]
  const neighbor = poses[4]
  const remote = poses[10]

  assert.equal(poses.filter(({ visible }) => visible).length, 15)
  assert.equal(active.opacity, 1)
  assert.equal(neighbor.opacity, 0.56)
  assert.equal(remote.opacity, 0.56)
  assert.ok(active.scale > neighbor.scale)
})

test('expanded labels blend continuously while the ring is being dragged', () => {
  const outgoing = moodOrbitTextPose(3, 3.4, 15, true)
  const incoming = moodOrbitTextPose(4, 3.4, 15, true)

  assert.ok(outgoing.opacity > incoming.opacity)
  assert.ok(outgoing.opacity < 1)
  assert.ok(incoming.opacity > 0.56)
})

test('continuous positions wrap and activate at the nearest half-step', () => {
  assert.equal(wrapMoodIndex(-1, 15), 14)
  assert.equal(wrapMoodIndex(15, 15), 0)
  assert.equal(activeMoodIndex(3.49, 15), 3)
  assert.equal(activeMoodIndex(3.51, 15), 4)
})

test('pointer angles follow the dial center in clockwise screen coordinates', () => {
  assert.equal(moodPointerAngle(110, 100, 100, 100), 0)
  assert.equal(moodPointerAngle(100, 110, 100, 100), 90)
  assert.equal(moodPointerAngle(90, 100, 100, 100), 180)
  assert.equal(moodPointerAngle(100, 90, 100, 100), -90)
})

test('angle deltas unwrap continuously while crossing the ±180 degree seam', () => {
  const angles = [170, 179, -179, -160]
  const rotation = angles.slice(1).reduce(
    (total, angle, index) => total + shortestMoodAngleDelta(angles[index], angle),
    0,
  )

  assert.equal(shortestMoodAngleDelta(179, -179), 2)
  assert.equal(shortestMoodAngleDelta(-179, 179), -2)
  assert.equal(rotation, 30)
})

test('one circular tick of pointer rotation advances one mood without discontinuity', () => {
  assert.equal(moodPositionFromRotation(3, 24, 15), 2)
  assert.equal(moodPositionFromRotation(3, -48, 15), 5)
  assert.equal(moodPositionFromRotation(14, -24, 15), 15)
})

test('rotary lock uses physical arc travel and ignores the unstable dial center', () => {
  assert.equal(ECHO_MOOD_ROTARY_LOCK_PX, 6)
  assert.equal(ECHO_MOOD_MIN_TRACKING_RADIUS_PX, 28)
  assert.ok(moodRotationTravelPx(3, 120) > ECHO_MOOD_ROTARY_LOCK_PX)
  assert.ok(moodRotationTravelPx(2, 120) < ECHO_MOOD_ROTARY_LOCK_PX)
  assert.equal(moodRotationTravelPx(30, 0), 0)
})

test('fixed mood controls choose the nearest copy on the circular track', () => {
  assert.equal(nearestMoodPosition(14, 0, 15), 15)
  assert.equal(nearestMoodPosition(1, 14, 15), -1)
  assert.equal(nearestMoodPosition(31, 1, 15), 31)
})

test('release velocity projects in the rotation direction, caps momentum, and snaps', () => {
  assert.equal(ECHO_MOOD_PROJECTION_MS, 140)
  assert.equal(ECHO_MOOD_MAX_FLING_STEPS, 2)
  assert.equal(projectMoodSnap(4.1, 0.04), 6)
  assert.equal(projectMoodSnap(4.1, -0.04), 2)
  assert.equal(projectMoodSnap(4.1, 0.005), 5)
  assert.equal(projectMoodSnap(4.4, 0), 4)
})

test('orbital poses expose only the current mood', () => {
  const center = orbitalMoodPose(4, 4, 15)
  const previous = orbitalMoodPose(3, 4, 15)
  const next = orbitalMoodPose(5, 4, 15)
  const remote = orbitalMoodPose(10, 4, 15)

  assert.deepEqual(center, {
    visible: true,
    x: 0,
    y: 0,
    scale: 1,
    opacity: 1,
    zIndex: 30,
  })
  assert.equal(previous.visible, false)
  assert.equal(previous.opacity, 0)
  assert.equal(next.visible, false)
  assert.equal(next.opacity, 0)
  assert.equal(remote.visible, false)
  assert.equal(remote.opacity, 0)
})

test('visual planet travel stays independent from the short input threshold', () => {
  assert.equal(ECHO_MOOD_ORBIT_TRAVEL_PX, 116)
  const halfStep = orbitalMoodPose(4, 3.5, 15)

  assert.equal(halfStep.x, 58)
  assert.equal(halfStep.y, 5)
  assert.ok(Math.abs(halfStep.scale - 0.93) < 1e-9)
})

test('continuous movement never exposes more than one mood at once', () => {
  for (const position of [3, 3.49, 3.5, 3.51, 4, 14.75, 15]) {
    const visible = Array.from({ length: 15 }, (_, index) => index)
      .filter((index) => orbitalMoodPose(index, position, 15).visible)

    assert.deepEqual(visible, [activeMoodIndex(position, 15)])
  }
})

test('the abrupt impact and bounce timers are no longer public behavior', () => {
  assert.equal('ECHO_MOOD_IMPACT_MS' in swipeModel, false)
  assert.equal('ECHO_MOOD_BOUNCE_MS' in swipeModel, false)
})

test('dragging ignores buttons and their nested labels while preserving the carousel surface', () => {
  assert.equal(isMoodDragStartAllowed([
    { tagName: 'SPAN' },
    { tagName: 'BUTTON', allowsMoodDrag: true },
  ]), true)
  assert.equal(isMoodDragStartAllowed([{ tagName: 'SPAN' }, { tagName: 'BUTTON' }]), false)
  assert.equal(isMoodDragStartAllowed([{ tagName: 'A' }, { tagName: 'DIV' }]), false)
  assert.equal(isMoodDragStartAllowed([{ tagName: 'DIV' }, { tagName: 'SECTION' }]), true)
  assert.equal(isMoodDragStartAllowed([{ tagName: 'DIV', isContentEditable: true }]), false)
})

test('only a completed rotary-locked drag suppresses its follow-up click', () => {
  assert.equal('shouldSuppressMoodClick' in swipeModel, true)
  const shouldSuppressMoodClick = (
    swipeModel as typeof swipeModel & {
      shouldSuppressMoodClick: (rotated: boolean, cancelled: boolean) => boolean
    }
  ).shouldSuppressMoodClick

  assert.equal(shouldSuppressMoodClick(false, false), false)
  assert.equal(shouldSuppressMoodClick(true, false), true)
  assert.equal(shouldSuppressMoodClick(true, true), false)
})
