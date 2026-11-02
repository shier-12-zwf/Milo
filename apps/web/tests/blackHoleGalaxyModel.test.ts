import assert from 'node:assert/strict'
import test from 'node:test'
import {
  BLACK_HOLE_GALAXY_SETTINGS,
  capBackgroundDpr,
  isBlackHoleGalaxyDemo,
  normalizePointer,
} from '../src/components/blackHoleGalaxyModel.ts'

test('black-hole background is the default and accepts the explicit query value', () => {
  assert.equal(isBlackHoleGalaxyDemo(''), true)
  assert.equal(isBlackHoleGalaxyDemo('?bgDemo=black-hole'), true)
  assert.equal(isBlackHoleGalaxyDemo('?bgDemo=galaxy'), false)
})

test('settings preserve the supplied Galaxy motion values', () => {
  assert.deepEqual(BLACK_HOLE_GALAXY_SETTINGS, {
    starSpeed: 0.7,
    density: 1.7,
    hueShift: 140,
    speed: 1.4,
    glowIntensity: 0.45,
    saturation: 0.15,
    mouseRepulsion: true,
    repulsionStrength: 2,
    twinkleIntensity: 0.4,
    rotationSpeed: 0.1,
    transparent: true,
  })
})

test('background DPR is capped at 1.5', () => {
  assert.equal(capBackgroundDpr(0.5), 1)
  assert.equal(capBackgroundDpr(2), 1.5)
})

test('pointer normalization converts DOM coordinates to bottom-left WebGL space', () => {
  const rect = { left: 10, top: 20, width: 200, height: 100 }
  assert.deepEqual(normalizePointer(110, 45, rect), [0.5, 0.75])
})
