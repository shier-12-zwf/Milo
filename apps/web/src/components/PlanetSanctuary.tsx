import { useEffect, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'
import type { MoodId } from '../types'
import { ECHO_MOODS, type MoodVisual } from './moodEmotionModel'
import { MoodPlanetImage } from './MoodPlanetImage'
import { CosmicSky } from './CosmicSky'
import { PLANET_FRAGMENT, PLANET_VERTEX } from './planetSpaceShader'
import './planetSanctuary.css'

function color(value: string): [number, number, number] {
  return [1, 3, 5].map((at) => parseInt(value.slice(at, at + 2), 16) / 255) as [number, number, number]
}

/** Draw the existing vector expressions as a transparent surface decal. */
function expression(mood: MoodVisual) {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 512
  const ctx = canvas.getContext('2d')!
  ctx.scale(512 / 200, 512 / 200)
  ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.lineWidth = 2.2
  for (const stroke of [...mood.eyes, ...mood.brows, ...mood.mouth, ...mood.hands, ...mood.accents.filter((stroke) => stroke.layer === 'blush' || stroke.layer === 'tear')]) {
    ctx.strokeStyle = stroke.layer === 'tear' ? '#9eb8ea' : stroke.layer === 'blush' ? mood.blush : mood.ink
    ctx.fillStyle = stroke.layer === 'tear' ? '#9eb8ea' : stroke.layer === 'blush' ? mood.blush : mood.ink
    const path = new Path2D(stroke.d)
    if (stroke.fill) ctx.fill(path)
    else ctx.stroke(path)
  }
  return canvas
}

function PlanetScene({ mood, expanded, paused, onExpand }: {
  mood: MoodVisual; expanded?: boolean; paused: boolean; onExpand?: () => void
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [status, setStatus] = useState('pending')
  const [orbit, setOrbit] = useState<[number, number]>([0, 0])
  const [close, setClose] = useState(false)
  const [warm, setWarm] = useState(true)
  const drag = useRef<{ x: number; y: number; id: number } | null>(null)
  const state = useRef({ mood, orbit, close, warm, paused })
  const wake = useRef<() => void>(() => {})
  useEffect(() => { state.current = { mood, orbit, close, warm, paused }; wake.current() }, [mood, orbit, close, warm, paused])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const gl = canvas.getContext('webgl', { alpha: true, antialias: false, premultipliedAlpha: false, powerPreference: 'low-power' })
    if (!gl) { setStatus('fallback'); return }
    let disposed = false, contextLost = false, frame = 0, last = 0, clock = 0, visible = true
    let yaw = 0, pitch = 0, zoom = 0, warmth = 1, lastMood = ''
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)')
    const shaders: WebGLShader[] = []
    let program: WebGLProgram | null = null, buffer: WebGLBuffer | null = null, texture: WebGLTexture | null = null
    const release = () => {
      cancelAnimationFrame(frame)
      if (texture) gl.deleteTexture(texture)
      if (buffer) gl.deleteBuffer(buffer)
      if (program) gl.deleteProgram(program)
      shaders.forEach((shader) => gl.deleteShader(shader))
    }
    try {
      const compile = (type: number, source: string) => {
        const shader = gl.createShader(type)
        if (!shader) throw new Error('Shader unavailable')
        shaders.push(shader); gl.shaderSource(shader, source); gl.compileShader(shader)
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) ?? 'Shader compilation failed')
        return shader
      }
      program = gl.createProgram()
      if (!program) throw new Error('Program unavailable')
      gl.attachShader(program, compile(gl.VERTEX_SHADER, PLANET_VERTEX))
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, PLANET_FRAGMENT))
      gl.linkProgram(program)
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error('Program link failed')
      gl.useProgram(program)
      buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]), gl.STATIC_DRAW)
      const at = gl.getAttribLocation(program, 'a_position')
      gl.enableVertexAttribArray(at); gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0)
      texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true)
      const uniform = Object.fromEntries(['resolution','orbit','time','zoom','warm','base','accent','face'].map((name) => [name, gl.getUniformLocation(program!, `u_${name}`)]))
      gl.uniform1i(uniform.face, 0)
      const resize = () => {
        const rect = canvas.getBoundingClientRect()
        // Cap the pixel budget on high-DPI phones and full-screen displays.
        const ratio = Math.min(window.devicePixelRatio || 1, 1.5, Math.sqrt(1000000 / Math.max(1, rect.width * rect.height)))
        canvas.width = Math.max(1, Math.round(rect.width * ratio)); canvas.height = Math.max(1, Math.round(rect.height * ratio))
        gl.viewport(0, 0, canvas.width, canvas.height)
      }
      const draw = (now: number) => {
        if (disposed || contextLost) return
        const current = state.current
        const delta = Math.min((now - last) / 1000, 0.06)
        if (now - last >= 32 || motion.matches || current.paused) {
          last = now
          if (!current.paused && !motion.matches) clock += delta
          const ease = motion.matches ? 1 : 0.09
          yaw += (current.orbit[0] - yaw) * ease; pitch += (current.orbit[1] - pitch) * ease
          zoom += (Number(current.close) - zoom) * ease
          warmth += (Number(current.warm) - warmth) * ease
          if (lastMood !== current.mood.id) {
            gl.bindTexture(gl.TEXTURE_2D, texture)
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, expression(current.mood))
            lastMood = current.mood.id
          }
          gl.uniform2f(uniform.resolution, canvas.width, canvas.height)
          gl.uniform2f(uniform.orbit, yaw + Math.sin(clock * .13) * .035, pitch)
          gl.uniform1f(uniform.time, clock); gl.uniform1f(uniform.zoom, zoom); gl.uniform1f(uniform.warm, warmth)
          gl.uniform3fv(uniform.base, color(current.mood.palette[1]))
          gl.uniform3fv(uniform.accent, color(current.mood.palette[2]))
          gl.drawArrays(gl.TRIANGLES, 0, 6)
        }
        const settling = Math.abs(current.orbit[0]-yaw) + Math.abs(current.orbit[1]-pitch) + Math.abs(Number(current.close)-zoom) + Math.abs(Number(current.warm)-warmth) > 0.002
        if (visible && !document.hidden && ((!current.paused && !motion.matches) || settling)) frame = requestAnimationFrame(draw)
      }
      const schedule = () => { cancelAnimationFrame(frame); if (visible && !document.hidden && !contextLost) frame = requestAnimationFrame(draw) }
      wake.current = schedule
      const observer = new ResizeObserver(() => { resize(); schedule() }); observer.observe(canvas)
      const intersection = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; schedule() }); intersection.observe(canvas)
      const lost = (event: Event) => { event.preventDefault(); contextLost = true; cancelAnimationFrame(frame); setStatus('fallback') }
      canvas.addEventListener('webglcontextlost', lost)
      document.addEventListener('visibilitychange', schedule)
      motion.addEventListener('change', schedule)
      resize(); setStatus('webgl'); schedule()
      return () => {
        disposed = true; wake.current = () => {}; observer.disconnect(); intersection.disconnect()
        motion.removeEventListener('change', schedule)
        document.removeEventListener('visibilitychange', schedule); canvas.removeEventListener('webglcontextlost', lost)
        release()
      }
    } catch (error) {
      release(); setStatus('fallback')
      if (import.meta.env.DEV) console.warn('[Milo planet] static fallback', error)
    }
  }, [])

  const move = (event: ReactPointerEvent<HTMLCanvasElement>) => {
    const previous = drag.current
    if (!previous || previous.id !== event.pointerId) return
    const dx = event.clientX - previous.x, dy = event.clientY - previous.y
    setOrbit(([x, y]) => [x + dx * 0.007, Math.max(-0.65, Math.min(0.65, y + (expanded || event.pointerType === 'mouse' ? dy * .005 : 0)))])
    drag.current = { x: event.clientX, y: event.clientY, id: event.pointerId }
  }
  return (
    <div className={`planet-sanctuary ${expanded ? 'is-immersive' : ''}`} data-renderer={status} data-mood={mood.id} data-near={close} data-orbit={orbit.map((value) => value.toFixed(2)).join(',')}>
      <div className="planet-surface">
        <canvas ref={canvasRef} className={`planet-canvas ${status === 'webgl' ? 'is-ready' : ''}`} aria-label={`拖动环顾${mood.label}星球，也可用方向键旋转`} role="img" tabIndex={status === 'webgl' ? 0 : -1}
          onPointerDown={(event) => { if (status !== 'webgl') return; drag.current = { x: event.clientX, y: event.clientY, id: event.pointerId }; event.currentTarget.setPointerCapture(event.pointerId) }}
          onPointerMove={move}
          onPointerUp={() => { drag.current = null }} onPointerCancel={() => { drag.current = null }} onLostPointerCapture={() => { drag.current = null }}
          onKeyDown={(event) => {
            if (['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) {
              event.preventDefault()
              setOrbit(([x,y]) => [x + (event.key === 'ArrowLeft' ? -.15 : event.key === 'ArrowRight' ? .15 : 0), Math.max(-.65, Math.min(.65, y + (event.key === 'ArrowUp' ? -.1 : event.key === 'ArrowDown' ? .1 : 0)))])
            }
          }} />
        {status !== 'webgl' && <MoodPlanetImage moodId={mood.id} size={320} className="planet-fallback-art" />}
        <span className="planet-coordinate" aria-hidden="true">MILO · YOUR LITTLE UNIVERSE</span>
        <span className="planet-home-light"><i /> 一盏灯，为你亮着</span>
      </div>
      <div className="planet-story" aria-live="polite">
        <span className="planet-eyebrow">此刻的星球 · {mood.label}</span>
        <p>{close ? '靠近一点，这里有你的位置。' : '宇宙很大，这里刚好容得下你。'}</p>
      </div>
      <div className="planet-controls" aria-label="星球交互">
        <button type="button" aria-pressed={close} onClick={() => setClose(!close)} disabled={status !== 'webgl'}>{close ? '退后看星空' : '靠近这颗星球'} <span aria-hidden="true">{close ? '−' : '+'}</span></button>
        <button type="button" className="planet-icon-control" onClick={() => { setOrbit([0,0]); setClose(false) }} aria-label="回到最初视角" disabled={status !== 'webgl'}>↺</button>
        {expanded && <button type="button" className="planet-icon-control" aria-label={warm ? '调暗星球暖光' : '点亮星球暖光'} aria-pressed={warm} onClick={() => setWarm(!warm)} disabled={status !== 'webgl'}>☼</button>}
        {onExpand && <button type="button" className="planet-expand" onClick={onExpand}>仰望星空 <span aria-hidden="true">↗</span></button>}
      </div>
      <p className="planet-gesture-hint">{status === 'webgl' ? '轻轻拖动，换个角度看自己' : '每一种感受，都在这里被接住'}</p>
    </div>
  )
}

export function PlanetSanctuary({ selected, onSelect, onImmersiveChange }: { selected: MoodId; onSelect: (id: MoodId) => void; onImmersiveChange: (expanded: boolean) => void }) {
  const [expanded, setExpanded] = useState(false)
  const [paused, setPaused] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const trigger = useRef<HTMLDivElement>(null)
  const mood = ECHO_MOODS.find((item) => item.id === selected) ?? ECHO_MOODS[3]
  useEffect(() => { onImmersiveChange(expanded); return () => onImmersiveChange(false) }, [expanded, onImmersiveChange])
  useEffect(() => {
    if (!expanded) return
    const node = dialog.current
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
    node?.showModal()
    const scroller = document.querySelector<HTMLElement>('.landing-page')
    const overflow = scroller?.style.overflowY ?? ''
    if (scroller) scroller.style.overflowY = 'hidden'
    return () => { node?.close(); if (scroller) scroller.style.overflowY = overflow; previous?.focus() }
  }, [expanded])
  return (
    <div ref={trigger} className="planet-hero-wrap">
      <div hidden={expanded}><PlanetScene mood={mood} paused={paused || expanded} onExpand={() => setExpanded(true)} /></div>
      {expanded && <dialog ref={dialog} className="planet-observatory" aria-labelledby="observatory-title" onCancel={() => setExpanded(false)} onClose={() => setExpanded(false)}>
        <CosmicSky paused={paused} />
        <header className="observatory-header">
          <div><span className="planet-eyebrow">MILO OBSERVATORY</span><h2 id="observatory-title">星海之中，给自己一个家。</h2></div>
          <button autoFocus type="button" className="observatory-close" onClick={() => setExpanded(false)} aria-label="退出星空，回到官网">关闭 <span aria-hidden="true">×</span></button>
        </header>
        <PlanetScene mood={mood} expanded paused={paused} />
        <div className="observatory-footer">
          <div className="observatory-moods" aria-label="选择你的情绪星球">
            {ECHO_MOODS.map((item) => <button type="button" key={item.id} aria-label={`进入${item.label}星球`} aria-pressed={selected === item.id} onClick={() => onSelect(item.id)} style={{ '--planet-tint': item.palette[2] } as CSSProperties}><i /><span>{item.label}</span></button>)}
          </div>
          <div className="observatory-bottom"><button type="button" aria-pressed={paused} onClick={() => setPaused(!paused)}>{paused ? '让星空慢慢流动' : '让星空静下来'}</button><a href={`${import.meta.env.BASE_URL}app`}>带着此刻，进入 Milo <span aria-hidden="true">↗</span></a></div>
        </div>
      </dialog>}
    </div>
  )
}
