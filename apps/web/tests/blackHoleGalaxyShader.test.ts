import assert from 'node:assert/strict'
import test from 'node:test'
import { BLACK_HOLE_FRAGMENT_SHADER, BLACK_HOLE_VERTEX_SHADER } from '../src/components/blackHoleGalaxyShader.ts'

test('shader exposes every settings and interaction uniform', () => {
  assert.match(BLACK_HOLE_VERTEX_SHADER, /attribute vec2 aPosition/)
  for (const name of [
    'uResolution', 'uTime', 'uPointer', 'uPointerActive', 'uStarSpeed', 'uDensity',
    'uHueShift', 'uSpeed', 'uGlowIntensity', 'uSaturation', 'uRepulsionStrength',
    'uTwinkleIntensity', 'uRotationSpeed',
  ]) {
    assert.match(BLACK_HOLE_FRAGMENT_SHADER, new RegExp(`uniform .* ${name};`))
  }
})

test('fragment shader renders a layered starfield without vortex stages', () => {
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float layeredStarField/)
  for (const removed of ['tinyVortex', 'spiralDust', 'echoStream', 'vortexCenter', 'VORTEX_CORE_RADIUS']) {
    assert.doesNotMatch(BLACK_HOLE_FRAGMENT_SHADER, new RegExp(removed))
  }
})

test('stars use a larger core, restrained halo, and stronger pointer displacement', () => {
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float STAR_SIZE_GAIN = 1\.65/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float POINTER_REPULSION_SCALE = 0\.055/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float starCore/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float starHalo/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /layeredStarField\(repelPointer/)
})

test('starfield uses six depth layers with micro dust and irregular density masks', () => {
  const layerCalls = (BLACK_HOLE_FRAGMENT_SHADER.match(/animatedStarLayer\(/g) ?? []).length - 1

  assert.equal(layerCalls, 6)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float microStarDust/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float clusterA/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float clusterB/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float MICRO_DUST_POPULATION = 0\.16/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float FINE_STAR_POPULATION = 0\.079/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float MID_STAR_POPULATION = 0\.056/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /const float STARFIELD_DENSITY_FLOOR = 0\.52/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float densityFloor = STARFIELD_DENSITY_FLOOR/)
})

test('star layers cycle through restrained depth and ambient rotation', () => {
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /float galaxyDepth/)
  assert.match(
    BLACK_HOLE_FRAGMENT_SHADER,
    /fract\(phase \+ uTime \* uStarSpeed \* uSpeed \* 0\.022\)/,
  )
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /mix\(0\.84, 1\.24, depth\)/)
  assert.match(
    BLACK_HOLE_FRAGMENT_SHADER,
    /float starRotation = uTime \* uRotationSpeed \* 0\.18/,
  )
  assert.match(
    BLACK_HOLE_FRAGMENT_SHADER,
    /layeredStarField\(repelPointer\(starUv, pointer\)\)/,
  )
})

test('individual stars drift without a fixed vortex layer', () => {
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /vec2 stellarDrift/)
  assert.match(BLACK_HOLE_FRAGMENT_SHADER, /local - offset \* 0\.58 - stellarDrift/)
  assert.doesNotMatch(BLACK_HOLE_FRAGMENT_SHADER, /vortex/i)
})
