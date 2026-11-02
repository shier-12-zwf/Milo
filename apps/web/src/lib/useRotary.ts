import { useEffect, useRef } from 'react'

const INTERACTIVE_SELECTOR = 'button, a, input, textarea, select, [role="button"]'

export function isInteractiveRotaryTarget(target: EventTarget | null): boolean {
  const closest = (target as { closest?: (selector: string) => unknown } | null)?.closest
  return typeof closest === 'function' && Boolean(closest.call(target, INTERACTIVE_SELECTOR))
}

/**
 * iPod 式旋转拨盘手势。
 * 在目标元素上做环形拖动（或滚轮/触控板滑动）时，回调旋转角度增量（度）。
 * 顺时针为正，逆时针为负。
 */
export function useRotary(onDelta: (deg: number) => void, onEnd?: () => void) {
  const ref = useRef<HTMLDivElement>(null)
  const onDeltaRef = useRef(onDelta)
  const onEndRef = useRef(onEnd)
  onDeltaRef.current = onDelta
  onEndRef.current = onEnd

  useEffect(() => {
    const el = ref.current
    if (!el) return

    let dragging = false
    let last = 0
    let wheelTimer: ReturnType<typeof setTimeout> | null = null

    const angleOf = (e: PointerEvent) => {
      const r = el.getBoundingClientRect()
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      return (Math.atan2(e.clientY - cy, e.clientX - cx) * 180) / Math.PI
    }

    const down = (e: PointerEvent) => {
      if (isInteractiveRotaryTarget(e.target)) return
      dragging = true
      last = angleOf(e)
      el.setPointerCapture(e.pointerId)
    }

    const move = (e: PointerEvent) => {
      if (!dragging) return
      const a = angleOf(e)
      let d = a - last
      if (d > 180) d -= 360
      if (d < -180) d += 360
      last = a
      onDeltaRef.current(d)
    }

    const up = (e: PointerEvent) => {
      if (!dragging) return
      dragging = false
      try {
        el.releasePointerCapture(e.pointerId)
      } catch {
        /* noop */
      }
      onEndRef.current?.()
    }

    const wheel = (e: WheelEvent) => {
      e.preventDefault()
      onDeltaRef.current((e.deltaY + e.deltaX) * 0.12)
      if (wheelTimer) clearTimeout(wheelTimer)
      wheelTimer = setTimeout(() => onEndRef.current?.(), 160)
    }

    el.addEventListener('pointerdown', down)
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', up)
    el.addEventListener('pointercancel', up)
    el.addEventListener('wheel', wheel, { passive: false })
    return () => {
      el.removeEventListener('pointerdown', down)
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerup', up)
      el.removeEventListener('pointercancel', up)
      el.removeEventListener('wheel', wheel)
      if (wheelTimer) clearTimeout(wheelTimer)
    }
  }, [])

  return ref
}
