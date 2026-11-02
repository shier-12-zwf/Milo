import { useEffect, useRef } from 'react'

interface Star {
  x: number
  y: number
  r: number
  tw: number
  spd: number
  drift: number
}

/** 缓慢漂移、闪烁的星尘背景 */
export function Starfield() {
  const ref = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    let raf = 0
    let stars: Star[] = []
    const dpr = Math.min(window.devicePixelRatio || 1, 2)

    const resize = () => {
      canvas.width = canvas.clientWidth * dpr
      canvas.height = canvas.clientHeight * dpr
      const count = Math.floor((canvas.clientWidth * canvas.clientHeight) / 4200)
      stars = Array.from({ length: count }, () => ({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        r: (Math.random() * 1.3 + 0.3) * dpr,
        tw: Math.random() * Math.PI * 2,
        spd: 0.4 + Math.random() * 1.2,
        drift: (Math.random() - 0.5) * 0.06 * dpr,
      }))
    }

    const tick = (t: number) => {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      for (const s of stars) {
        const a = 0.25 + 0.55 * Math.abs(Math.sin(s.tw + (t / 1000) * s.spd))
        ctx.beginPath()
        ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2)
        ctx.fillStyle = `rgba(220, 214, 255, ${a})`
        ctx.fill()
        s.y -= s.drift
        s.x += s.drift * 0.6
        if (s.y < -4) s.y = canvas.height + 4
        if (s.y > canvas.height + 4) s.y = -4
      }
      raf = requestAnimationFrame(tick)
    }

    resize()
    raf = requestAnimationFrame(tick)
    window.addEventListener('resize', resize)
    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener('resize', resize)
    }
  }, [])

  return <canvas ref={ref} className="starfield" style={{ width: '100%', height: '100%' }} />
}
