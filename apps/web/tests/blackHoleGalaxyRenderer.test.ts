import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import { BLACK_HOLE_GALAXY_SETTINGS } from '../src/components/blackHoleGalaxyModel.ts'
import {
  createBlackHoleGalaxyRenderer,
  resizeBlackHoleBuffer,
} from '../src/components/blackHoleGalaxyRenderer.ts'

test('resizeBlackHoleBuffer uses capped DPR and only mutates changed dimensions', () => {
  const canvas = { clientWidth: 100, clientHeight: 50, width: 0, height: 0 } as HTMLCanvasElement

  assert.equal(resizeBlackHoleBuffer(canvas, 2), true)
  assert.equal(canvas.width, 150)
  assert.equal(canvas.height, 75)
  assert.equal(resizeBlackHoleBuffer(canvas, 2), false)
})

test('createBlackHoleGalaxyRenderer returns null and invokes fallback when WebGL is unavailable', () => {
  let failure: unknown
  const canvas = { getContext: () => null } as unknown as HTMLCanvasElement

  const renderer = createBlackHoleGalaxyRenderer(
    canvas,
    BLACK_HOLE_GALAXY_SETTINGS,
    () => undefined,
    (error) => { failure = error },
  )

  assert.equal(renderer, null)
  assert.match(String(failure), /WebGL unavailable/)
})

test('renderer resets pointer activity when the pointer leaves the window', async () => {
  const source = await readFile(
    new URL('../src/components/blackHoleGalaxyRenderer.ts', import.meta.url),
    'utf8',
  )

  assert.match(source, /window\.addEventListener\('pointerleave', pointerLeave\)/)
  assert.match(source, /window\.removeEventListener\('pointerleave', pointerLeave\)/)
})

test('pointer end and cancellation release the background interaction', async () => {
  const source = await readFile(
    new URL('../src/components/blackHoleGalaxyRenderer.ts', import.meta.url),
    'utf8',
  )

  for (const type of ['pointerup', 'pointercancel']) {
    assert.match(source, new RegExp(`window\\.addEventListener\\('${type}', pointerEnd\\)`))
    assert.match(source, new RegExp(`window\\.removeEventListener\\('${type}', pointerEnd\\)`))
  }
})

test('context loss enters the shared terminal failure lifecycle', async () => {
  const source = await readFile(
    new URL('../src/components/blackHoleGalaxyRenderer.ts', import.meta.url),
    'utf8',
  )

  assert.match(source, /function fail\(error\?: unknown\)/)
  assert.match(source, /fail\(new Error\('Black-hole WebGL context lost'\)\)/)
})
