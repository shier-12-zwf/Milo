import { useEffect, useRef } from 'react'
import {
  ECHO_MOOD_MIN_TRACKING_RADIUS_PX,
  ECHO_MOOD_ROTARY_LOCK_PX,
  isMoodDragStartAllowed,
  moodPointerAngle,
  moodPositionFromRotation,
  moodRotationTravelPx,
  projectMoodSnap,
  shortestMoodAngleDelta,
  shouldSuppressMoodClick,
} from '../components/moodSwipeModel'

export type MoodSwipePhase = 'dragging' | 'settling'

interface PointerSample {
  rotation: number
  time: number
}

const VELOCITY_WINDOW_MS = 100

export function useMoodSwipe(
  position: number,
  onPositionChange: (position: number, phase: MoodSwipePhase) => void,
  count: number,
  disabled = false,
) {
  const ref = useRef<HTMLDivElement>(null)
  const positionRef = useRef(position)
  const onPositionChangeRef = useRef(onPositionChange)
  positionRef.current = position
  onPositionChangeRef.current = onPositionChange

  useEffect(() => {
    const element = ref.current
    if (!element || disabled || count < 2) return

    let startPosition = positionRef.current
    let livePosition = startPosition
    let activePointerId: number | null = null
    let centerX = 0
    let centerY = 0
    let lastAngle: number | null = null
    let accumulatedRotation = 0
    let trackingRadius = ECHO_MOOD_MIN_TRACKING_RADIUS_PX
    let rotated = false
    let samples: PointerSample[] = []
    const captureOptions = { capture: true } as const
    let suppressClick = false
    let suppressionTimer: number | null = null

    const clearClickSuppression = () => {
      suppressClick = false
      if (suppressionTimer !== null) {
        window.clearTimeout(suppressionTimer)
        suppressionTimer = null
      }
    }

    const armClickSuppression = () => {
      clearClickSuppression()
      suppressClick = true
      suppressionTimer = window.setTimeout(() => {
        suppressClick = false
        suppressionTimer = null
      }, 0)
    }

    const remember = (rotation: number, time: number) => {
      samples.push({ rotation, time })
      samples = samples.filter((sample) => time - sample.time <= VELOCITY_WINDOW_MS)
    }

    const down = (event: PointerEvent) => {
      if (!event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) return
      clearClickSuppression()
      const targetPath = event.composedPath().map((target) => (
        target instanceof HTMLElement
          ? {
              tagName: target.tagName,
              isContentEditable: target.isContentEditable,
              allowsMoodDrag: target.dataset.moodDragSurface === 'true',
            }
          : {}
      ))
      if (!isMoodDragStartAllowed(targetPath)) return

      activePointerId = event.pointerId
      startPosition = positionRef.current
      livePosition = startPosition
      const bounds = element.getBoundingClientRect()
      centerX = bounds.left + bounds.width / 2
      centerY = bounds.top + bounds.height / 2
      trackingRadius = Math.hypot(event.clientX - centerX, event.clientY - centerY)
      lastAngle = trackingRadius >= ECHO_MOOD_MIN_TRACKING_RADIUS_PX
        ? moodPointerAngle(event.clientX, event.clientY, centerX, centerY)
        : null
      accumulatedRotation = 0
      rotated = false
      samples = []
      remember(0, event.timeStamp)
      onPositionChangeRef.current(livePosition, 'dragging')
    }

    const track = (event: PointerEvent, emit: boolean) => {
      const radius = Math.hypot(event.clientX - centerX, event.clientY - centerY)
      if (radius < ECHO_MOOD_MIN_TRACKING_RADIUS_PX) return

      const angle = moodPointerAngle(event.clientX, event.clientY, centerX, centerY)
      if (lastAngle === null) {
        lastAngle = angle
        trackingRadius = radius
        remember(accumulatedRotation, event.timeStamp)
        return
      }

      accumulatedRotation += shortestMoodAngleDelta(lastAngle, angle)
      lastAngle = angle
      trackingRadius = Math.max(ECHO_MOOD_MIN_TRACKING_RADIUS_PX, (trackingRadius + radius) / 2)
      remember(accumulatedRotation, event.timeStamp)

      if (!rotated && moodRotationTravelPx(accumulatedRotation, trackingRadius) >= ECHO_MOOD_ROTARY_LOCK_PX) {
        rotated = true
        try {
          element.setPointerCapture(event.pointerId)
        } catch {
          /* The window listeners still own the active pointer session. */
        }
      }

      if (rotated) {
        livePosition = moodPositionFromRotation(startPosition, accumulatedRotation, count)
        if (emit) onPositionChangeRef.current(livePosition, 'dragging')
      }
    }

    const move = (event: PointerEvent) => {
      if (event.pointerId !== activePointerId) return
      const coalescedEvents = event.getCoalescedEvents?.()
      const pointerEvents = coalescedEvents?.length ? coalescedEvents : [event]
      for (const pointerEvent of pointerEvents) track(pointerEvent, true)
      if (rotated) event.preventDefault()
    }

    const finish = (event: PointerEvent, cancelled: boolean) => {
      if (event.pointerId !== activePointerId) return

      if (!cancelled) track(event, false)
      const first = samples.at(0)
      const last = samples.at(-1)
      const elapsed = first && last ? last.time - first.time : 0
      const rotationVelocity = first && last && elapsed > 0
        ? (last.rotation - first.rotation) / elapsed
        : 0
      const positionVelocity = rotated && !cancelled && count > 0
        ? -rotationVelocity / (360 / count)
        : 0
      const target = projectMoodSnap(livePosition, positionVelocity)
      const suppressFollowupClick = shouldSuppressMoodClick(rotated, cancelled)

      activePointerId = null
      lastAngle = null
      accumulatedRotation = 0
      rotated = false
      samples = []
      onPositionChangeRef.current(target, 'settling')

      try {
        element.releasePointerCapture(event.pointerId)
      } catch {
        /* Pointer capture may already be released by the browser. */
      }

      if (suppressFollowupClick) armClickSuppression()
    }

    const up = (event: PointerEvent) => finish(event, false)
    const cancel = (event: PointerEvent) => finish(event, true)
    const suppressDraggedClick = (event: MouseEvent) => {
      if (!suppressClick) return
      event.preventDefault()
      event.stopPropagation()
      clearClickSuppression()
    }

    element.addEventListener('pointerdown', down, captureOptions)
    element.addEventListener('click', suppressDraggedClick, captureOptions)
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    window.addEventListener('pointercancel', cancel)
    return () => {
      element.removeEventListener('pointerdown', down, captureOptions)
      element.removeEventListener('click', suppressDraggedClick, captureOptions)
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', cancel)
      clearClickSuppression()
    }
  }, [count, disabled])

  return ref
}
