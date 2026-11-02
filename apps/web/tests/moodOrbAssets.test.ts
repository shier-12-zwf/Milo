import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

import { ECHO_MOODS } from '../src/components/moodEmotionModel.ts'
import {
  getMoodOrbAsset,
  MOOD_ORB_ASSETS,
  moodOrbSheetLeftPercent,
} from '../src/components/moodOrbAssets.ts'

const EXPECTED_ASSETS = [
  ['very-low', '01-very-low-low-heavy-transparent.png', 0],
  ['low', '01-very-low-low-heavy-transparent.png', 1],
  ['heavy', '01-very-low-low-heavy-transparent.png', 2],
  ['calm', '02-calm-okay-bright-transparent.png', 0],
  ['okay', '02-calm-okay-bright-transparent.png', 1],
  ['bright', '02-calm-okay-bright-transparent.png', 2],
  ['joyful', '03-joyful-lonely-sad-transparent.png', 0],
  ['lonely', '03-joyful-lonely-sad-transparent.png', 1],
  ['sad', '03-joyful-lonely-sad-transparent.png', 2],
  ['angry', '04-angry-afraid-disappointed-transparent.png', 0],
  ['afraid', '04-angry-afraid-disappointed-transparent.png', 1],
  ['disappointed', '04-angry-afraid-disappointed-transparent.png', 2],
  ['anxious', '05-anxious-aggrieved-embarrassed-transparent.png', 0],
  ['aggrieved', '05-anxious-aggrieved-embarrassed-transparent.png', 1],
  ['embarrassed', '05-anxious-aggrieved-embarrassed-transparent.png', 2],
] as const

test('mood orb assets follow the canonical mood order exactly once', () => {
  const assetIds = MOOD_ORB_ASSETS.map(({ id }) => id)
  const moodIds = ECHO_MOODS.map(({ id }) => id)

  assert.deepEqual(assetIds, moodIds)
  assert.equal(new Set(assetIds).size, assetIds.length)
})

test('each three-mood sheet uses panels zero, one, and two in order', () => {
  assert.equal(MOOD_ORB_ASSETS.length % 3, 0)

  for (let index = 0; index < MOOD_ORB_ASSETS.length; index += 3) {
    const group = MOOD_ORB_ASSETS.slice(index, index + 3)

    assert.equal(new Set(group.map(({ sheet }) => sheet)).size, 1)
    assert.deepEqual(
      group.map(({ panel }) => panel),
      [0, 1, 2],
    )
  }
})

test('all five referenced sheets are transparent raster files on disk', () => {
  const sheets = [...new Set(MOOD_ORB_ASSETS.map(({ sheet }) => sheet))]

  assert.equal(sheets.length, 5)
  for (const sheet of sheets) {
    assert.match(sheet, /-transparent\.png$/)
    assert.equal(existsSync(fileURLToPath(sheet)), true, `Missing mood orb sheet: ${sheet}`)
  }
})

test('getMoodOrbAsset returns the exact registered asset', () => {
  for (const asset of MOOD_ORB_ASSETS) {
    assert.strictEqual(getMoodOrbAsset(asset.id), asset)
  }
})

test('every mood is locked to its approved source sheet and panel', () => {
  for (const [id, basename, panel] of EXPECTED_ASSETS) {
    const asset = getMoodOrbAsset(id)

    assert.equal(asset.sheet.endsWith(basename), true)
    assert.equal(asset.panel, panel)
  }
})

test('the registry and each registered asset are immutable at runtime', () => {
  assert.equal(Object.isFrozen(MOOD_ORB_ASSETS), true)
  for (const asset of MOOD_ORB_ASSETS) {
    assert.equal(Object.isFrozen(asset), true)
  }
})

test('left and right source panels compensate for their off-center sphere positions', () => {
  for (const asset of MOOD_ORB_ASSETS) {
    const expectedOffset = asset.id === 'anxious' ? -9 : [-11, 0, 11][asset.panel]
    assert.equal(asset.focusOffsetPercent, expectedOffset)
  }

  assert.equal(moodOrbSheetLeftPercent(getMoodOrbAsset('very-low')), -11)
  assert.equal(moodOrbSheetLeftPercent(getMoodOrbAsset('low')), -100)
  assert.equal(moodOrbSheetLeftPercent(getMoodOrbAsset('heavy')), -189)
  assert.equal(moodOrbSheetLeftPercent(getMoodOrbAsset('anxious')), -9)
})
