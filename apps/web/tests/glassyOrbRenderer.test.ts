import assert from 'node:assert/strict'
import test from 'node:test'
import {
  compileShader,
  createGlassyOrbRenderer,
  resizeDrawingBuffer,
  settleFactor,
} from '../src/components/glassyOrbRenderer.ts'

test('resizeDrawingBuffer uses capped DPR and only mutates changed dimensions', () => {
  const canvas = { clientWidth: 188, clientHeight: 188, width: 0, height: 0 } as HTMLCanvasElement
  assert.equal(resizeDrawingBuffer(canvas, 3), true)
  assert.equal(canvas.width, 376)
  assert.equal(canvas.height, 376)
  assert.equal(resizeDrawingBuffer(canvas, 3), false)
})

test('compileShader deletes a shader and reports its compiler log on failure', () => {
  let deleted = false
  const gl = {
    COMPILE_STATUS: 1,
    createShader: () => ({}),
    shaderSource: () => undefined,
    compileShader: () => undefined,
    getShaderParameter: () => false,
    getShaderInfoLog: () => 'bad fragment shader',
    deleteShader: () => { deleted = true },
  } as unknown as WebGLRenderingContext

  assert.throws(() => compileShader(gl, 7, 'source'), /bad fragment shader/)
  assert.equal(deleted, true)
})

test('createGlassyOrbRenderer returns null and invokes fallback when WebGL is unavailable', () => {
  let failed = false
  const canvas = { getContext: () => null } as unknown as HTMLCanvasElement
  const renderer = createGlassyOrbRenderer(canvas, () => undefined, () => { failed = true })
  assert.equal(renderer, null)
  assert.equal(failed, true)
})

test('settleFactor eases renderer state over the approved seven hundred milliseconds', () => {
  assert.equal(settleFactor(0, 700), 0)
  assert.ok(settleFactor(350, 700) > 0 && settleFactor(350, 700) < 1)
  assert.ok(settleFactor(700, 700) > 0.6)
  assert.equal(settleFactor(16, 0), 1)
})
