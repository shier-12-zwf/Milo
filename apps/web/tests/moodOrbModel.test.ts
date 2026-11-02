import assert from 'node:assert/strict'
import test from 'node:test'
import {
  capRenderDpr,
  echoMoodColorsF,
  hexToRgb01,
  moodColors,
  moodColorsF,
  pulseStrength,
  spinDegreesToRadians,
} from '../src/components/moodOrbModel.ts'

test('moodColors clamps and rounds integer emotion levels', () => {
  assert.deepEqual(moodColors(-99), ['#3b4370', '#232849', '#6a7ab0'])
  assert.deepEqual(moodColors(99), ['#e8b8c8', '#b57d94', '#ffe3c4'])
  assert.deepEqual(moodColors(0.6), ['#9c8ad0', '#66549e', '#cfc0ee'])
})

test('moodColorsF interpolates continuously between adjacent levels', () => {
  assert.deepEqual(moodColorsF(0.5), ['#8d84c8', '#5a5196', '#c1baeb'])
})

test('echoMoodColorsF keeps every mood inside the moon-silver violet-gray family', () => {
  assert.deepEqual(echoMoodColorsF(0), ['#737786', '#272b34', '#c6cad4'])
  assert.deepEqual(echoMoodColorsF(0.5), ['#797884', '#2b2c34', '#cbc8d0'])
})

test('hexToRgb01 produces normalized WebGL color channels', () => {
  assert.deepEqual(hexToRgb01('#ff8040'), [1, 128 / 255, 64 / 255])
})

test('render helpers cap DPR, convert spin, and decay pulse deterministically', () => {
  assert.equal(capRenderDpr(0.5), 1)
  assert.equal(capRenderDpr(3), 2)
  assert.equal(spinDegreesToRadians(180), Math.PI)
  assert.equal(pulseStrength(0), 1)
  assert.equal(pulseStrength(225), 0.5)
  assert.equal(pulseStrength(450), 0)
  assert.equal(pulseStrength(900), 0)
})
