import { useEffect, useRef, useState } from 'react'
import { BLACK_HOLE_GALAXY_SETTINGS } from './blackHoleGalaxyModel'
import {
  createBlackHoleGalaxyRenderer,
  type BlackHoleGalaxyRenderer,
} from './blackHoleGalaxyRenderer'

type RendererStatus = 'pending' | 'webgl' | 'fallback'

export function BlackHoleGalaxy() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const rendererRef = useRef<BlackHoleGalaxyRenderer | null>(null)
  const [status, setStatus] = useState<RendererStatus>('pending')

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    rendererRef.current = createBlackHoleGalaxyRenderer(
      canvas,
      BLACK_HOLE_GALAXY_SETTINGS,
      () => setStatus('webgl'),
      (error) => {
        setStatus('fallback')
        if (import.meta.env.DEV) console.warn('[BlackHoleGalaxy] WebGL fallback', error)
      },
    )

    return () => {
      rendererRef.current?.destroy()
      rendererRef.current = null
    }
  }, [])

  return (
    <div className="black-hole-galaxy" data-black-hole-container={status} aria-hidden="true">
      <canvas
        ref={canvasRef}
        className={`black-hole-galaxy-canvas ${status === 'webgl' ? 'is-ready' : ''}`}
        data-black-hole-status={status}
      />
      <div className={`black-hole-galaxy-fallback ${status === 'webgl' ? 'is-hidden' : ''}`} />
    </div>
  )
}
