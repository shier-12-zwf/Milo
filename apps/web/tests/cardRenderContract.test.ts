import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { ECHO_MOODS, getMoodVisual, moodPalette } from '../src/components/moodEmotionModel.ts'
import {
  getMoodOrbAsset,
  MOOD_ORB_SHEET_PANEL_COUNT,
  moodOrbSheetLeftPercent,
} from '../src/components/moodOrbAssets.ts'
import {
  CARD_THEME,
  cardMoodArtwork,
  cardRenderContract,
} from '../src/lib/card.ts'

const sampleEntry = {
  id: 'memory-1',
  createdAt: new Date('2026-07-25T08:00:00+08:00').getTime(),
  kind: 'past' as const,
  mood: { valence: 2, labels: ['平静', '释然'], emotionId: 'bright' as const },
  timeMark: '去年夏天',
  diary: '这一天一直安静地住在我心里。',
  diaryEnabled: true,
}

test('named moods reuse the exact MoodPlanetImage sheet and crop contract', () => {
  for (const mood of ECHO_MOODS) {
    const asset = getMoodOrbAsset(mood.id)
    const artwork = cardMoodArtwork(mood.id)

    assert.ok(artwork)
    assert.equal(artwork.sheet, asset.sheet)
    assert.equal(
      artwork.sourceXRatio,
      -moodOrbSheetLeftPercent(asset) / (MOOD_ORB_SHEET_PANEL_COUNT * 100),
    )
    assert.equal(artwork.sourceWidthRatio, 1 / MOOD_ORB_SHEET_PANEL_COUNT)
    assert.equal(artwork.sourceYRatio, 0)
    assert.equal(artwork.sourceHeightRatio, 1)
  }
})

test('legacy valence-only records keep the gradient-orb fallback', () => {
  const contract = cardRenderContract({ valence: -2, labels: [] })

  assert.equal(contract.artwork, null)
  assert.deepEqual(contract.palette, moodPalette(-2))
})

test('named mood cards preserve their palette while keeping tint restrained', () => {
  const contract = cardRenderContract({ valence: 3, labels: [], emotionId: 'angry' })

  assert.equal(contract.palette, getMoodVisual('angry').palette)
  assert.ok(contract.moodTintAlpha > 0)
  assert.ok(contract.moodTintAlpha <= 0.18)
})

test('the card theme is deep-space silver-purple instead of mood-owned', () => {
  assert.deepEqual(
    [
      CARD_THEME.backgroundTop,
      CARD_THEME.backgroundMid,
      CARD_THEME.backgroundBottom,
      CARD_THEME.silver,
      CARD_THEME.lavender,
    ],
    ['#11111d', '#070810', '#020308', '#d9dce7', '#aaa4c4'],
  )
})

test('the card page awaits async rendering and cancels stale or unmounted work', () => {
  const cardPage = readFileSync(new URL('../src/pages/Card.tsx', import.meta.url), 'utf8')

  assert.match(cardPage, /const controller = new AbortController\(\)/)
  assert.match(cardPage, /await renderCard\(entryToRender, template\.id, \{ signal: controller\.signal \}\)/)
  assert.match(cardPage, /if \(active\)/)
  assert.match(cardPage, /return \(\) => \{\s*active = false\s*controller\.abort\(\)\s*\}/s)
})

test('the card registry removes the second template and keeps the mist-violet card first', async () => {
  const cardModule = await import('../src/lib/card.ts')
  const templates = Reflect.get(cardModule, 'STICKER_TEMPLATES')

  assert.deepEqual(templates, [
    { id: 'planet-letter', name: '星球卡片', tone: '雾紫卡纸' },
    { id: 'orbit-theatre', name: '轨道剧场', tone: '社交海报' },
  ])
})

test('invalid or missing template IDs fall back to A', async () => {
  const cardModule = await import('../src/lib/card.ts')
  const normalize = Reflect.get(cardModule, 'normalizeStickerTemplate')
  const fallback = Reflect.get(cardModule, 'DEFAULT_STICKER_TEMPLATE')

  assert.equal(typeof normalize, 'function')
  assert.equal(fallback, 'planet-letter')
  assert.equal(normalize(undefined), fallback)
  assert.equal(normalize('unknown'), fallback)
  assert.equal(normalize('orbit-theatre'), 'orbit-theatre')
})

test('every template keeps the exact homepage mood artwork contract', () => {
  const mood = sampleEntry.mood

  for (const templateId of ['planet-letter', 'orbit-theatre']) {
    const contract = cardRenderContract(mood, templateId)
    assert.equal(Reflect.get(contract, 'templateId'), templateId)
    assert.deepEqual(contract.artwork, cardMoodArtwork('bright'))
  }
})

test('memory tickets receive a stable branded ID without a fake QR generator', async () => {
  const cardModule = await import('../src/lib/card.ts')
  const ticketId = Reflect.get(cardModule, 'memoryTicketId')
  const cardSource = readFileSync(new URL('../src/lib/card.ts', import.meta.url), 'utf8')

  assert.equal(typeof ticketId, 'function')
  assert.match(ticketId(sampleEntry), /^ML-\d{6}-\d{2}-[A-Z0-9]{4}$/)
  assert.equal(ticketId(sampleEntry), ticketId(sampleEntry))
  assert.doesNotMatch(cardSource, /memoryCodeGrid|drawMemoryCode/)
})

test('the selected sticker template is persisted on each memory entry', () => {
  const typesSource = readFileSync(new URL('../src/types.ts', import.meta.url), 'utf8')

  assert.match(typesSource, /export type StickerTemplateId = 'planet-letter' \| 'orbit-theatre'/)
  assert.match(typesSource, /stickerTemplate\?: StickerTemplateId/)
})

test('the card page renders all templates asynchronously and persists selection', () => {
  const cardPage = readFileSync(new URL('../src/pages/Card.tsx', import.meta.url), 'utf8')

  assert.match(cardPage, /Promise\.all\(/)
  assert.match(cardPage, /renderCard\(entryToRender, template\.id, \{ signal: controller\.signal \}\)/)
  assert.match(cardPage, /updateEntry\(entry\.id, \{ stickerTemplate: next \}\)/)
  assert.match(cardPage, /controller\.abort\(\)/)
})

test('named mood artwork failures reject instead of exporting the wrong fallback planet', async () => {
  const cardModule = await import('../src/lib/card.ts')
  const render = Reflect.get(cardModule, 'renderCard')
  const originalImage = Reflect.get(globalThis, 'Image')

  class FailingImage {
    decoding = ''
    onload: (() => void) | null = null
    onerror: (() => void) | null = null

    set src(_value: string) {
      queueMicrotask(() => this.onerror?.())
    }
  }

  Reflect.set(globalThis, 'Image', FailingImage)
  try {
    await assert.rejects(
      render(sampleEntry, 'planet-letter'),
      /Unable to load mood artwork/,
    )
  } finally {
    if (originalImage === undefined) Reflect.deleteProperty(globalThis, 'Image')
    else Reflect.set(globalThis, 'Image', originalImage)
  }
})

test('persisting template choice does not invalidate already rendered stickers', async () => {
  const cardModule = await import('../src/lib/card.ts')
  const renderKey = Reflect.get(cardModule, 'stickerRenderKey')

  assert.equal(typeof renderKey, 'function')
  assert.equal(
    renderKey(sampleEntry),
    renderKey({ ...sampleEntry, stickerTemplate: 'orbit-theatre' }),
  )
  assert.notEqual(
    renderKey(sampleEntry),
    renderKey({ ...sampleEntry, diary: '内容发生变化。' }),
  )
})

test('template switching reuses rendered URLs and failure state is not announced as busy', () => {
  const cardPage = readFileSync(new URL('../src/pages/Card.tsx', import.meta.url), 'utf8')

  assert.doesNotMatch(cardPage, /\}, \[entry\]\)/)
  assert.match(cardPage, /aria-busy=\{isLoading\}/)
  assert.match(cardPage, /renderError \? \(/)
})

test('all sticker layouts stay inside the moon-silver violet family', () => {
  const cardSource = readFileSync(new URL('../src/lib/card.ts', import.meta.url), 'utf8')

  assert.doesNotMatch(cardSource, /#4c6fe6/i)
})

test('card previews keep fixed thumbnails while full cards can grow and scroll', () => {
  const cardPage = readFileSync(new URL('../src/pages/Card.tsx', import.meta.url), 'utf8')
  const cardSource = readFileSync(new URL('../src/lib/card.ts', import.meta.url), 'utf8')
  const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')

  assert.match(cardPage, /你的情绪卡片/)
  assert.match(cardPage, /选择卡片模板/)
  assert.match(cardSource, /function measureCardHeight\(/)
  assert.match(cardSource, /const lines = wrapText\(ctx, copy\.body, 796\)/)
  assert.match(cardSource, /const lines = wrapText\(ctx, copy\.body, 790\)/)
  assert.match(css, /\.sticker-preview-shell\s*\{[^}]*max-height:[^}]*overflow-y:\s*auto/s)
  assert.match(css, /\.template-artwork\s*\{[^}]*aspect-ratio:\s*8\s*\/\s*5/s)
  assert.match(css, /\.template-artwork img\s*\{[^}]*object-position:\s*center top/s)
  assert.match(css, /\.sticker-actions\s*\{[^}]*position:\s*fixed/s)
  assert.match(cardPage, /onClick=\{onHome\}>\s*回到首页/s)
  assert.doesNotMatch(cardPage, /navigator\.share|navigator\.canShare/)
})
