import assert from 'node:assert/strict'
import test from 'node:test'
import { FRAGMENT_SHADER, VERTEX_SHADER } from '../src/components/glassyOrbShader.ts'

test('shader exposes every renderer attribute and uniform', () => {
  assert.match(VERTEX_SHADER, /attribute vec2 aPosition/)
  for (const uniform of [
    'uResolution', 'uTime', 'uSpin', 'uPulse', 'uColorMain', 'uColorDeep', 'uColorLight',
    'uSilverTone', 'uNebulaFlow', 'uStarDensity', 'uLightBias', 'uTurbulence', 'uMoodPulse',
  ]) {
    assert.match(FRAGMENT_SHADER, new RegExp(`uniform .* ${uniform};`))
  }
})

test('shader drives internal flow, density, light position, turbulence, and mood pulse from uniforms', () => {
  assert.match(FRAGMENT_SHADER, /uNebulaFlow \* uTime/)
  assert.match(FRAGMENT_SHADER, /uStarDensity/)
  assert.match(FRAGMENT_SHADER, /uLightBias/)
  assert.match(FRAGMENT_SHADER, /uTurbulence/)
  assert.match(FRAGMENT_SHADER, /uMoodPulse/)
})

test('fragment shader contains nebula, stars, Fresnel glass, and prismatic rim stages', () => {
  assert.match(FRAGMENT_SHADER, /float nebulaDensity/)
  assert.match(FRAGMENT_SHADER, /float starLayer/)
  assert.match(FRAGMENT_SHADER, /float stellarDust/)
  assert.match(FRAGMENT_SHADER, /float cellularVeins/)
  assert.match(FRAGMENT_SHADER, /float cloudShelf/)
  assert.match(FRAGMENT_SHADER, /float cloudBoundary/)
  assert.match(FRAGMENT_SHADER, /float cloudRim/)
  assert.match(FRAGMENT_SHADER, /float fresnel/)
  assert.match(FRAGMENT_SHADER, /vec3 prism/)
})

test('shader remaps emotion colors into a saturated cosmic palette', () => {
  assert.match(FRAGMENT_SHADER, /vec3 cosmicMain/)
  assert.match(FRAGMENT_SHADER, /vec3 cosmicDeep/)
  assert.match(FRAGMENT_SHADER, /vec3 cosmicLight/)
})

test('shader can blend the orb into a moon-silver graphite palette', () => {
  assert.match(FRAGMENT_SHADER, /vec3 silverMain/)
  assert.match(FRAGMENT_SHADER, /mix\(cosmicMain, silverMain, uSilverTone\)/)
})

test('shader keeps the galactic core compact at mood-orb scale', () => {
  assert.match(FRAGMENT_SHADER, /float galaxyCore/)
  assert.match(FRAGMENT_SHADER, /exp\(-72\.0/)
})

test('shader uses fine star sand instead of oversized light dots', () => {
  assert.match(FRAGMENT_SHADER, /const float STAR_RADIUS = 0\.072/)
  assert.match(FRAGMENT_SHADER, /stellarDust\(starUv/)
  assert.match(FRAGMENT_SHADER, /cellularVeins\(starUv \* 5\.4/)
})

test('shader preserves each mood palette without forcing every orb toward purple', () => {
  assert.doesNotMatch(FRAGMENT_SHADER, /uColorDeep\.g \* 0\.25/)
  assert.match(FRAGMENT_SHADER, /mix\(uColorMain, uColorLight, 0\.24\)/)
})

test('lower cloud shelf stays palette-tinted instead of blowing out to solid white', () => {
  assert.match(FRAGMENT_SHADER, /pow\(abs\(point\.x\), 1\.7\) \* 0\.28/)
  assert.match(FRAGMENT_SHADER, /cosmicMain \* \(shelf \* 0\.10 \+ shelfRim \* 0\.34\)/)
  assert.match(FRAGMENT_SHADER, /cosmicLight \* \(shelf \* 0\.025 \+ shelfRim \* 0\.28\)/)
})
