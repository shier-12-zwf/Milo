import { compileShader } from './glassyOrbRenderer.ts'
import {
  capBackgroundDpr,
  normalizePointer,
  type BlackHoleGalaxySettings,
} from './blackHoleGalaxyModel.ts'
import {
  BLACK_HOLE_FRAGMENT_SHADER,
  BLACK_HOLE_VERTEX_SHADER,
} from './blackHoleGalaxyShader.ts'

export interface BlackHoleGalaxyRenderer {
  destroy(): void
}

export function resizeBlackHoleBuffer(canvas: HTMLCanvasElement, dpr: number): boolean {
  const ratio = capBackgroundDpr(dpr)
  const width = Math.max(1, Math.round(canvas.clientWidth * ratio))
  const height = Math.max(1, Math.round(canvas.clientHeight * ratio))
  if (canvas.width === width && canvas.height === height) return false
  canvas.width = width
  canvas.height = height
  return true
}

export function createBlackHoleGalaxyRenderer(
  canvas: HTMLCanvasElement,
  settings: BlackHoleGalaxySettings,
  onReady: () => void,
  onFailure: (error?: unknown) => void,
): BlackHoleGalaxyRenderer | null {
  const gl = canvas.getContext('webgl', {
    alpha: settings.transparent,
    antialias: false,
    premultipliedAlpha: false,
    powerPreference: 'high-performance',
  })
  if (!gl) {
    onFailure(new Error('WebGL unavailable'))
    return null
  }

  let vertexShader: WebGLShader | null = null
  let fragmentShader: WebGLShader | null = null
  let program: WebGLProgram | null = null
  let buffer: WebGLBuffer | null = null
  let attribute = -1
  let uniforms: {
    resolution: WebGLUniformLocation
    time: WebGLUniformLocation
    pointer: WebGLUniformLocation
    pointerActive: WebGLUniformLocation
    starSpeed: WebGLUniformLocation
    density: WebGLUniformLocation
    hueShift: WebGLUniformLocation
    speed: WebGLUniformLocation
    glowIntensity: WebGLUniformLocation
    saturation: WebGLUniformLocation
    repulsionStrength: WebGLUniformLocation
    twinkleIntensity: WebGLUniformLocation
    rotationSpeed: WebGLUniformLocation
  }

  try {
    vertexShader = compileShader(gl, gl.VERTEX_SHADER, BLACK_HOLE_VERTEX_SHADER)
    fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, BLACK_HOLE_FRAGMENT_SHADER)
    const allocatedProgram = gl.createProgram()
    if (!allocatedProgram) throw new Error('Unable to allocate WebGL program')
    program = allocatedProgram
    gl.attachShader(allocatedProgram, vertexShader)
    gl.attachShader(allocatedProgram, fragmentShader)
    gl.linkProgram(allocatedProgram)
    if (!gl.getProgramParameter(allocatedProgram, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(allocatedProgram) || 'Unknown program link failure')
    }

    buffer = gl.createBuffer()
    if (!buffer) throw new Error('Unable to allocate WebGL buffer')
    attribute = gl.getAttribLocation(allocatedProgram, 'aPosition')
    if (attribute < 0) throw new Error('Missing WebGL attribute: aPosition')

    const uniform = (name: string) => {
      const location = gl.getUniformLocation(allocatedProgram, name)
      if (location === null) throw new Error(`Missing WebGL uniform: ${name}`)
      return location
    }
    uniforms = {
      resolution: uniform('uResolution'),
      time: uniform('uTime'),
      pointer: uniform('uPointer'),
      pointerActive: uniform('uPointerActive'),
      starSpeed: uniform('uStarSpeed'),
      density: uniform('uDensity'),
      hueShift: uniform('uHueShift'),
      speed: uniform('uSpeed'),
      glowIntensity: uniform('uGlowIntensity'),
      saturation: uniform('uSaturation'),
      repulsionStrength: uniform('uRepulsionStrength'),
      twinkleIntensity: uniform('uTwinkleIntensity'),
      rotationSpeed: uniform('uRotationSpeed'),
    }

    gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      gl.STATIC_DRAW,
    )
    gl.useProgram(allocatedProgram)
    gl.enableVertexAttribArray(attribute)
    gl.vertexAttribPointer(attribute, 2, gl.FLOAT, false, 0, 0)
    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.clearColor(0, 0, 0, 0)
  } catch (error) {
    if (buffer) gl.deleteBuffer(buffer)
    if (program) gl.deleteProgram(program)
    if (vertexShader) gl.deleteShader(vertexShader)
    if (fragmentShader) gl.deleteShader(fragmentShader)
    onFailure(error)
    return null
  }

  const activeVertexShader = vertexShader
  const activeFragmentShader = fragmentShader
  const activeProgram = program
  const activeBuffer = buffer
  let pointerTarget: [number, number] = [0.5, 0.5]
  const pointer: [number, number] = [0.5, 0.5]
  let pointerActiveTarget = 0
  let pointerActive = 0
  let animationSeconds = 0
  let previousFrame = performance.now()
  let frameId = 0
  let ready = false
  let runtimeStopped = false
  let destroyed = false
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
  let resizeObserver: ResizeObserver | null = null

  function pointerMove(event: PointerEvent) {
    pointerTarget = normalizePointer(event.clientX, event.clientY, canvas.getBoundingClientRect())
    pointerActiveTarget = settings.mouseRepulsion ? 1 : 0
  }

  function pointerLeave() {
    pointerActiveTarget = 0
  }

  function pointerEnd() {
    pointerActiveTarget = 0
  }

  function stopRuntime() {
    if (runtimeStopped) return
    runtimeStopped = true
    cancelAnimationFrame(frameId)
    resizeObserver?.disconnect()
    window.removeEventListener('pointermove', pointerMove)
    window.removeEventListener('pointerleave', pointerLeave)
    window.removeEventListener('pointerup', pointerEnd)
    window.removeEventListener('pointercancel', pointerEnd)
    canvas.removeEventListener('webglcontextlost', contextLost)
  }

  function fail(error?: unknown) {
    if (destroyed) return
    destroyed = true
    stopRuntime()
    onFailure(error)
  }

  function contextLost(event: Event) {
    event.preventDefault()
    fail(new Error('Black-hole WebGL context lost'))
  }

  window.addEventListener('pointermove', pointerMove)
  window.addEventListener('pointerleave', pointerLeave)
  window.addEventListener('pointerup', pointerEnd)
  window.addEventListener('pointercancel', pointerEnd)
  canvas.addEventListener('webglcontextlost', contextLost)

  resizeObserver = typeof ResizeObserver === 'undefined'
    ? null
    : new ResizeObserver(() => resizeBlackHoleBuffer(canvas, window.devicePixelRatio))
  resizeObserver?.observe(canvas)

  const render = (now: number) => {
    if (destroyed || runtimeStopped) return
    const deltaSeconds = Math.min(0.05, Math.max(0, now - previousFrame) / 1000)
    previousFrame = now
    if (!reducedMotion.matches) animationSeconds += deltaSeconds
    resizeBlackHoleBuffer(canvas, window.devicePixelRatio)

    pointer[0] += (pointerTarget[0] - pointer[0]) * 0.12
    pointer[1] += (pointerTarget[1] - pointer[1]) * 0.12
    pointerActive += (pointerActiveTarget - pointerActive) * 0.12

    gl.viewport(0, 0, canvas.width, canvas.height)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.useProgram(activeProgram)
    gl.uniform2f(uniforms.resolution, canvas.width, canvas.height)
    gl.uniform1f(uniforms.time, animationSeconds)
    gl.uniform2f(uniforms.pointer, pointer[0], pointer[1])
    gl.uniform1f(uniforms.pointerActive, pointerActive)
    gl.uniform1f(uniforms.starSpeed, settings.starSpeed)
    gl.uniform1f(uniforms.density, settings.density)
    gl.uniform1f(uniforms.hueShift, settings.hueShift)
    gl.uniform1f(uniforms.speed, settings.speed)
    gl.uniform1f(uniforms.glowIntensity, settings.glowIntensity)
    gl.uniform1f(uniforms.saturation, settings.saturation)
    gl.uniform1f(uniforms.repulsionStrength, settings.repulsionStrength)
    gl.uniform1f(uniforms.twinkleIntensity, settings.twinkleIntensity)
    gl.uniform1f(uniforms.rotationSpeed, settings.rotationSpeed)
    gl.drawArrays(gl.TRIANGLES, 0, 6)

    if (!ready) {
      ready = true
      onReady()
    }
    frameId = requestAnimationFrame(render)
  }
  frameId = requestAnimationFrame(render)

  return {
    destroy() {
      if (destroyed) return
      destroyed = true
      stopRuntime()
      gl.deleteBuffer(activeBuffer)
      gl.deleteProgram(activeProgram)
      gl.deleteShader(activeVertexShader)
      gl.deleteShader(activeFragmentShader)
    },
  }
}
