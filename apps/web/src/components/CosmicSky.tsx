import { useEffect, useRef } from 'react'

/** A perspective star field. It never handles gestures or blocks page scrolling. */
export function CosmicSky({ paused = false }: { paused?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const canvas = ref.current
    const ctx = canvas?.getContext('2d', { alpha: true })
    if (!canvas || !ctx) return
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)')
    let seed = 7319
    const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646
    const stars = Array.from({ length: 3000 }, () => ({
      x: (random() - 0.5) * 11, y: (random() - 0.5) * 8,
      z: 0.7 + random() * 4.5, radius: 0.3 + random() ** 5 * 1.7,
      phase: random() * 6.28, warm: random() > 0.76,
    }))
    const nebula = document.createElement('canvas')
    let width = 1, height = 1, frame = 0, last = 0
    let targetX = 0, targetY = 0, x = 0, y = 0, time = 0
    const resize = () => {
      const rect = canvas.getBoundingClientRect()
      width = rect.width; height = rect.height
      const ratio = Math.min(window.devicePixelRatio || 1, 1.5)
      canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio)
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
      nebula.width = Math.round(width + 100); nebula.height = Math.round(height + 100)
      const nc = nebula.getContext('2d')!
      // A sloping, feathered Milky Way, with dark space between the clouds.
      for (let i = 0; i < 36; i++) {
        const along = i / 35
        const cx = width * (0.22 + along * 0.95) + 50
        const cy = height * (0.02 + along * 0.62) + 50 + Math.sin(i * 1.8) * 35
        const r = width * (0.08 + (i % 4) * 0.015)
        const gradient = nc.createRadialGradient(cx, cy, 0, cx, cy, r)
        gradient.addColorStop(0, i % 3 ? 'rgba(108,104,176,.075)' : 'rgba(159,122,170,.09)')
        gradient.addColorStop(0.4, 'rgba(80,85,156,.04)')
        gradient.addColorStop(1, 'rgba(44,52,104,0)')
        nc.fillStyle = gradient; nc.fillRect(cx-r, cy-r, r*2, r*2)
      }
      seed = 5271
      for (let i = 0; i < 4600; i++) {
        const along = random()
        const spread = (random() + random() + random() - 1.5) * height * 0.16
        const sx = width * (0.16 + along * 1.06) + 50
        const sy = height * (0.01 + along * 0.68) + spread + 50
        nc.fillStyle = `rgba(202,200,241,${0.08 + random() * 0.36})`
        const size = random() > 0.99 ? 1.5 : 0.55
        nc.fillRect(sx, sy, size, size)
      }
      draw()
    }
    const draw = () => {
      ctx.clearRect(0, 0, width, height)
      ctx.drawImage(nebula, -50 - x * 15, -50 - y * 10)
      const focal = Math.max(width, height) * 0.55
      for (const star of stars) {
        const sx = width * 0.5 + (star.x - x * 0.09) / star.z * focal
        const sy = height * 0.46 + (star.y - y * 0.07) / star.z * focal
        if (sx < -8 || sx > width + 8 || sy < -8 || sy > height + 8) continue
        const radius = star.radius * (0.55 + 0.7 / star.z)
        const alpha = 0.42 + 0.32 * Math.sin(time * 0.3 + star.phase) ** 2
        ctx.fillStyle = star.warm ? `rgba(248,222,204,${alpha})` : `rgba(207,217,255,${alpha})`
        ctx.beginPath(); ctx.arc(sx, sy, radius, 0, Math.PI * 2); ctx.fill()
        if (radius > 1.65) {
          ctx.strokeStyle = `rgba(215,223,255,${alpha * 0.17})`
          ctx.lineWidth = 0.6; ctx.beginPath()
          ctx.moveTo(sx - radius * 4, sy); ctx.lineTo(sx + radius * 4, sy)
          ctx.moveTo(sx, sy - radius * 4); ctx.lineTo(sx, sy + radius * 4); ctx.stroke()
        }
      }
    }
    const tick = (now: number) => {
      if (now - last > 32) {
        const delta = Math.min((now - last) / 1000, 0.06); last = now
        if (!motion.matches) time += delta
        x += (targetX - x) * 0.035; y += (targetY - y) * 0.035
        draw()
      }
      frame = requestAnimationFrame(tick)
    }
    const schedule = () => {
      cancelAnimationFrame(frame)
      if (!paused && !document.hidden && !motion.matches) frame = requestAnimationFrame(tick)
      else draw()
    }
    const pointer = (event: PointerEvent) => {
      if (motion.matches || event.pointerType === 'touch') return
      targetX = event.clientX / window.innerWidth * 2 - 1
      targetY = event.clientY / window.innerHeight * 2 - 1
    }
    const observer = new ResizeObserver(resize)
    observer.observe(canvas)
    document.addEventListener('pointermove', pointer, { passive: true })
    document.addEventListener('visibilitychange', schedule)
    motion.addEventListener('change', schedule)
    resize(); schedule()
    return () => {
      cancelAnimationFrame(frame); observer.disconnect()
      document.removeEventListener('pointermove', pointer)
      document.removeEventListener('visibilitychange', schedule)
      motion.removeEventListener('change', schedule)
    }
  }, [paused])
  return <canvas ref={ref} className="cosmic-sky" aria-hidden="true" />
}
