import type { Entry, MoodId, MoodState, StickerTemplateId } from '../types.ts'
import { moodLabel, moodPalette } from '../components/moodEmotionModel.ts'
import {
  getMoodOrbAsset,
  MOOD_ORB_SHEET_PANEL_COUNT,
  MOOD_ORB_VIEWPORT_HEIGHT,
  MOOD_ORB_VIEWPORT_WIDTH,
  moodOrbSheetLeftPercent,
} from '../components/moodOrbAssets.ts'

const W = 1080
const H = 1350

export const CARD_THEME = Object.freeze({
  backgroundTop: '#11111d',
  backgroundMid: '#070810',
  backgroundBottom: '#020308',
  silver: '#d9dce7',
  silverBright: '#f0f1f6',
  lavender: '#aaa4c4',
  panel: 'rgba(19, 19, 32, 0.82)',
  panelBorder: 'rgba(218, 218, 232, 0.20)',
  bodyText: 'rgba(232, 231, 239, 0.90)',
  secondaryText: 'rgba(202, 199, 218, 0.62)',
  faintText: 'rgba(188, 186, 204, 0.42)',
})

export const DEFAULT_STICKER_TEMPLATE: StickerTemplateId = 'planet-letter'

export const STICKER_TEMPLATES = [
  { id: 'planet-letter', name: '星球卡片', tone: '雾紫卡纸' },
  { id: 'orbit-theatre', name: '轨道剧场', tone: '社交海报' },
] as const

const TEMPLATE_IDS = new Set<string>(STICKER_TEMPLATES.map((item) => item.id))

const TEMPLATE_SEEDS: Record<StickerTemplateId, number> = {
  'planet-letter': 0x2d16a43f,
  'orbit-theatre': 0x418be2c7,
}

export interface CardMoodArtwork {
  readonly sheet: string
  readonly sourceXRatio: number
  readonly sourceWidthRatio: number
  readonly sourceYRatio: 0
  readonly sourceHeightRatio: 1
}

export interface CardRenderContract {
  readonly templateId: StickerTemplateId
  readonly palette: readonly [string, string, string]
  readonly artwork: CardMoodArtwork | null
  readonly moodTintAlpha: number
}

export interface RenderCardOptions {
  signal?: AbortSignal
}

interface MoodArtworkDestination {
  x: number
  y: number
  width: number
}

interface LoadedMoodArtwork {
  image: HTMLImageElement
  artwork: CardMoodArtwork
}

type StickerRenderer = (
  ctx: CanvasRenderingContext2D,
  entry: Entry,
  contract: CardRenderContract,
  loadedArtwork: LoadedMoodArtwork | null,
  random: () => number,
) => void

export function normalizeStickerTemplate(value: unknown): StickerTemplateId {
  return typeof value === 'string' && TEMPLATE_IDS.has(value)
    ? (value as StickerTemplateId)
    : DEFAULT_STICKER_TEMPLATE
}

/**
 * 与 MoodPlanetImage 的 CSS 三联图裁切保持同一数学契约。
 * 归一化坐标让 Canvas 可在图片加载后按其真实像素尺寸取图。
 */
export function cardMoodArtwork(emotionId?: MoodId): CardMoodArtwork | null {
  if (!emotionId) return null

  const asset = getMoodOrbAsset(emotionId)
  return Object.freeze({
    sheet: asset.sheet,
    sourceXRatio: -moodOrbSheetLeftPercent(asset) / (MOOD_ORB_SHEET_PANEL_COUNT * 100),
    sourceWidthRatio: 1 / MOOD_ORB_SHEET_PANEL_COUNT,
    sourceYRatio: 0,
    sourceHeightRatio: 1,
  })
}

/** 两种版式共享同一份情绪星球裁切，旧记录则保留渐变球降级。 */
export function cardRenderContract(
  mood: MoodState,
  templateId: StickerTemplateId = DEFAULT_STICKER_TEMPLATE,
): CardRenderContract {
  return Object.freeze({
    templateId: normalizeStickerTemplate(templateId),
    palette: moodPalette(mood.valence, mood.emotionId),
    artwork: cardMoodArtwork(mood.emotionId),
    moodTintAlpha: 0.16,
  })
}

export function getStickerCopy(entry: Entry) {
  return {
    heading: entry.kind === 'past' ? entry.timeMark ?? '过去的某一天' : '此刻',
    labels: entry.mood.labels.join(' · '),
    body: entry.diary || entry.note || '这一刻，被安静地收藏了。',
  }
}

/** 卡片内容变化时才重绘；模板选择本身复用已生成的图片。 */
export function stickerRenderKey(entry: Entry): string {
  return JSON.stringify({
    id: entry.id,
    createdAt: entry.createdAt,
    kind: entry.kind,
    mood: entry.mood,
    timeMark: entry.timeMark,
    note: entry.note,
    diary: entry.diary,
  })
}

function stableHash(value: string): number {
  let hash = 2166136261
  for (const char of value) {
    hash ^= char.codePointAt(0) ?? 0
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

function createSeededRandom(seed: number): () => number {
  let state = seed >>> 0
  return () => {
    state += 0x6d2b79f5
    let value = state
    value = Math.imul(value ^ (value >>> 15), value | 1)
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61)
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296
  }
}

export function memoryTicketId(entry: Entry): string {
  const date = new Date(entry.createdAt)
  const stamp = `${String(date.getFullYear()).slice(-2)}${String(date.getMonth() + 1).padStart(2, '0')}${String(date.getDate()).padStart(2, '0')}`
  const level = String(Math.max(-3, Math.min(3, Math.round(entry.mood.valence))) + 3).padStart(2, '0')
  const suffix = stableHash(entry.id).toString(36).toUpperCase().padStart(4, '0').slice(-4)
  return `ML-${stamp}-${level}-${suffix}`
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function wrapText(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
  const lines: string[] = []
  for (const para of text.split('\n')) {
    if (!para.trim()) {
      lines.push('')
      continue
    }
    let line = ''
    for (const ch of para) {
      if (line && ctx.measureText(line + ch).width > maxWidth) {
        lines.push(line)
        line = ch
      } else {
        line += ch
      }
    }
    if (line) lines.push(line)
  }
  return lines
}

function fitLines(lines: string[], maxLines: number): string[] {
  const visible = lines.slice(0, maxLines)
  if (lines.length > maxLines && visible.length) {
    const last = visible.length - 1
    visible[last] = `${visible[last].replace(/[。，！？…]$/u, '')}…`
  }
  return visible
}

function hexAlpha(hex: string, alpha: number): string {
  const normalized = hex.startsWith('#') ? hex.slice(1) : hex
  const value = Number.parseInt(normalized, 16)
  const red = (value >> 16) & 255
  const green = (value >> 8) & 255
  const blue = value & 255
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`
}

function abortError(): DOMException {
  return new DOMException('Card rendering was aborted', 'AbortError')
}

function throwIfAborted(signal?: AbortSignal) {
  if (signal?.aborted) throw abortError()
}

function loadImage(src: string, signal?: AbortSignal): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    throwIfAborted(signal)
    const image = new Image()
    image.decoding = 'async'

    const cleanup = () => {
      image.onload = null
      image.onerror = null
      signal?.removeEventListener('abort', onAbort)
    }
    const onAbort = () => {
      cleanup()
      image.src = ''
      reject(abortError())
    }

    image.onload = () => {
      cleanup()
      resolve(image)
    }
    image.onerror = () => {
      cleanup()
      reject(new Error(`Unable to load mood artwork: ${src}`))
    }
    signal?.addEventListener('abort', onAbort, { once: true })
    image.src = src
  })
}

function drawLegacyOrb(
  ctx: CanvasRenderingContext2D,
  destination: MoodArtworkDestination,
  palette: readonly [string, string, string],
) {
  const [main, deep, light] = palette
  const height = destination.width * (MOOD_ORB_VIEWPORT_HEIGHT / MOOD_ORB_VIEWPORT_WIDTH)
  const x = destination.x + destination.width / 2
  const y = destination.y + height / 2
  const radius = destination.width * 0.43
  const orb = ctx.createRadialGradient(x - radius * 0.3, y - radius * 0.32, radius * 0.12, x, y, radius)
  orb.addColorStop(0, light)
  orb.addColorStop(0.55, main)
  orb.addColorStop(1, deep)
  ctx.save()
  ctx.shadowColor = hexAlpha(main, 0.28)
  ctx.shadowBlur = radius * 0.65
  ctx.fillStyle = orb
  ctx.beginPath()
  ctx.arc(x, y, radius, 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}

function drawMoodArtwork(
  ctx: CanvasRenderingContext2D,
  loadedArtwork: LoadedMoodArtwork | null,
  palette: readonly [string, string, string],
  destination: MoodArtworkDestination,
) {
  if (!loadedArtwork) {
    drawLegacyOrb(ctx, destination, palette)
    return
  }

  const { image, artwork } = loadedArtwork
  const height = destination.width * (MOOD_ORB_VIEWPORT_HEIGHT / MOOD_ORB_VIEWPORT_WIDTH)
  const sourceX = image.naturalWidth * artwork.sourceXRatio
  const sourceWidth = image.naturalWidth * artwork.sourceWidthRatio
  const sourceY = image.naturalHeight * artwork.sourceYRatio
  const sourceHeight = image.naturalHeight * artwork.sourceHeightRatio

  ctx.save()
  ctx.shadowColor = hexAlpha(palette[0], 0.24)
  ctx.shadowBlur = Math.max(16, destination.width * 0.2)
  ctx.drawImage(
    image,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
    destination.x,
    destination.y,
    destination.width,
    height,
  )
  ctx.restore()
}

function paintStars(
  ctx: CanvasRenderingContext2D,
  random: () => number,
  count: number,
  color: string,
  yStart = 0,
  yEnd = ctx.canvas.height,
) {
  ctx.save()
  for (let index = 0; index < count; index++) {
    const x = random() * W
    const y = yStart + random() * (yEnd - yStart)
    const radius = random() * 2.1 + 0.45
    ctx.globalAlpha = random() * 0.56 + 0.16
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(x, y, radius, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.restore()
}

function drawDate(ctx: CanvasRenderingContext2D, entry: Entry, color: string, y = ctx.canvas.height - 104) {
  const date = new Date(entry.createdAt)
  const dateText = `${date.getFullYear()} 年 ${date.getMonth() + 1} 月 ${date.getDate()} 日 · 记于米洛`
  ctx.textAlign = 'center'
  ctx.font = '25px "PingFang SC", sans-serif'
  ctx.fillStyle = color
  ctx.fillText(dateText, W / 2, y)
}

function drawBrand(ctx: CanvasRenderingContext2D, color: string, y = ctx.canvas.height - 58) {
  ctx.textAlign = 'center'
  ctx.font = '600 22px "PingFang SC", sans-serif'
  ctx.letterSpacing = '8px'
  ctx.fillStyle = color
  ctx.fillText('M I L O', W / 2, y)
  ctx.letterSpacing = '0px'
}

function drawHatchRule(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  color: string,
) {
  ctx.save()
  ctx.strokeStyle = color
  ctx.lineWidth = 2
  for (let offset = 0; offset < width; offset += 10) {
    ctx.beginPath()
    ctx.moveTo(x + offset, y + 6)
    ctx.lineTo(x + offset + 5, y - 6)
    ctx.stroke()
  }
  ctx.restore()
}

function drawTicketTag(ctx: CanvasRenderingContext2D, text: string, x: number, y: number) {
  ctx.font = '700 22px "PingFang SC", sans-serif'
  const width = ctx.measureText(`# ${text}`).width + 34
  ctx.fillStyle = 'rgba(255,255,255,0.18)'
  ctx.strokeStyle = 'rgba(21,19,27,0.58)'
  ctx.lineWidth = 2
  roundRect(ctx, x, y, width, 42, 21)
  ctx.fill()
  ctx.stroke()
  ctx.fillStyle = '#17151d'
  ctx.textAlign = 'left'
  ctx.fillText(`# ${text}`, x + 17, y + 29)
}

function drawBurst(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  outerRadius: number,
  innerRadius: number,
) {
  ctx.beginPath()
  for (let index = 0; index < 24; index++) {
    const angle = -Math.PI / 2 + (index * Math.PI) / 12
    const radius = index % 2 === 0 ? outerRadius : innerRadius
    const pointX = x + Math.cos(angle) * radius
    const pointY = y + Math.sin(angle) * radius
    if (index === 0) ctx.moveTo(pointX, pointY)
    else ctx.lineTo(pointX, pointY)
  }
  ctx.closePath()
}

function drawMemoryTicket(
  ctx: CanvasRenderingContext2D,
  entry: Entry,
  contract: CardRenderContract,
  loadedArtwork: LoadedMoodArtwork | null,
  random: () => number,
) {
  const copy = getStickerCopy(entry)
  const [primary, deep] = contract.palette
  const canvasH = ctx.canvas.height
  const heightExtension = canvasH - H
  ctx.fillStyle = '#0b0b12'
  ctx.fillRect(0, 0, W, canvasH)

  const ambient = ctx.createRadialGradient(W * 0.74, 150, 20, W * 0.74, 150, 680)
  ambient.addColorStop(0, hexAlpha(primary, contract.moodTintAlpha))
  ambient.addColorStop(0.5, 'rgba(126,105,184,0.08)')
  ambient.addColorStop(1, 'rgba(0,0,0,0)')
  ctx.fillStyle = ambient
  ctx.fillRect(0, 0, W, canvasH * 0.72)
  paintStars(ctx, random, 76, '#ddd5f2')

  const ticketX = 88
  const ticketY = 44
  const ticketW = 904
  const ticketH = 1262 + heightExtension
  const ticketRadius = 58
  const tearY = 1008 + heightExtension

  ctx.save()
  roundRect(ctx, ticketX, ticketY, ticketW, ticketH, ticketRadius)
  ctx.clip()
  ctx.fillStyle = '#f0eff2'
  ctx.fillRect(ticketX, ticketY, ticketW, ticketH)

  const paper = ctx.createLinearGradient(ticketX, ticketY, ticketX + ticketW, tearY)
  paper.addColorStop(0, '#b8a7e9')
  paper.addColorStop(0.5, '#d6ccea')
  paper.addColorStop(1, '#e4def3')
  ctx.fillStyle = paper
  ctx.fillRect(ticketX, ticketY, ticketW, tearY - ticketY)

  ctx.fillStyle = 'rgba(255,255,255,0.2)'
  ctx.beginPath()
  ctx.moveTo(ticketX + 490, ticketY)
  ctx.lineTo(ticketX + ticketW, ticketY)
  ctx.lineTo(ticketX + ticketW, ticketY + 350)
  ctx.lineTo(ticketX + 330, ticketY + 720)
  ctx.closePath()
  ctx.fill()
  ctx.restore()

  ctx.save()
  ctx.shadowColor = 'rgba(0,0,0,0.38)'
  ctx.shadowBlur = 42
  ctx.strokeStyle = 'rgba(255,255,255,0.12)'
  ctx.lineWidth = 2
  roundRect(ctx, ticketX, ticketY, ticketW, ticketH, ticketRadius)
  ctx.stroke()
  ctx.restore()

  ctx.fillStyle = '#17151d'
  ctx.textAlign = 'left'
  ctx.font = '900 29px "Arial Black", "PingFang SC", sans-serif'
  ctx.fillText('MILO', 132, 111)
  ctx.fillText('MILO', 456, 111)
  ctx.fillText('MILO', 790, 111)
  drawHatchRule(ctx, 228, 101, 184, 'rgba(23,21,29,0.5)')
  drawHatchRule(ctx, 556, 101, 186, 'rgba(23,21,29,0.5)')

  drawMoodArtwork(ctx, loadedArtwork, contract.palette, { x: 130, y: 130, width: 86 })

  const mainMood = moodLabel(entry.mood.valence, entry.mood.emotionId)
  const secondaryMood = entry.mood.labels.find((label) => label !== mainMood)
  const identityMood = secondaryMood ? `${mainMood} · ${secondaryMood}` : mainMood
  ctx.fillStyle = '#17151d'
  ctx.font = '800 35px "PingFang SC", sans-serif'
  ctx.fillText(identityMood, 238, 204)
  ctx.font = '700 19px ui-monospace, "SFMono-Regular", monospace'
  ctx.fillStyle = 'rgba(23,21,29,0.66)'
  ctx.fillText(`PLANET ID: ${memoryTicketId(entry)}`, 238, 239)

  ctx.save()
  ctx.translate(846, 202)
  ctx.rotate(0.045)
  ctx.strokeStyle = '#17151d'
  ctx.lineWidth = 3
  ctx.strokeRect(-94, -41, 188, 82)
  ctx.fillStyle = '#17151d'
  ctx.textAlign = 'center'
  ctx.font = '800 16px ui-monospace, monospace'
  ctx.fillText('ORIGINAL', 0, -8)
  ctx.fillText('MEMORY', 0, 18)
  ctx.restore()

  const showcaseX = 140
  const showcaseY = 292
  const showcaseW = 800
  const showcaseH = 355
  ctx.fillStyle = 'rgba(248,246,251,0.7)'
  roundRect(ctx, showcaseX, showcaseY, showcaseW, showcaseH, 34)
  ctx.fill()
  ctx.strokeStyle = '#17151d'
  ctx.lineWidth = 5
  roundRect(ctx, showcaseX, showcaseY, showcaseW, showcaseH, 34)
  ctx.stroke()

  ctx.save()
  roundRect(ctx, showcaseX + 4, showcaseY + 4, showcaseW - 8, showcaseH - 8, 30)
  ctx.clip()
  ctx.translate(525, 465)
  ctx.rotate(-0.16)
  ctx.strokeStyle = 'rgba(91,72,132,0.2)'
  ctx.lineWidth = 2
  for (let index = 0; index < 3; index++) {
    ctx.beginPath()
    ctx.ellipse(0, 0, 470 + index * 72, 80 + index * 30, 0, 0, Math.PI * 2)
    ctx.stroke()
  }
  ctx.restore()

  ctx.save()
  roundRect(ctx, showcaseX + 4, showcaseY + 4, showcaseW - 8, showcaseH - 8, 30)
  ctx.clip()
  drawMoodArtwork(ctx, loadedArtwork, contract.palette, { x: 394, y: 239, width: 292 })
  ctx.restore()

  ctx.fillStyle = '#17151d'
  roundRect(ctx, 390, 591, 300, 58, 15)
  ctx.fill()
  ctx.fillStyle = '#fff'
  ctx.textAlign = 'center'
  ctx.font = '800 27px "PingFang SC", sans-serif'
  ctx.fillText(copy.heading, W / 2, 630)

  const tags = entry.mood.labels.length ? entry.mood.labels.slice(0, 3) : [mainMood]
  let tagX = 140
  for (const tag of tags) {
    drawTicketTag(ctx, tag, tagX, 694)
    ctx.font = '700 22px "PingFang SC", sans-serif'
    tagX += ctx.measureText(`# ${tag}`).width + 52
  }

  ctx.textAlign = 'left'
  ctx.fillStyle = 'rgba(23,21,29,0.62)'
  ctx.font = '800 17px ui-monospace, monospace'
  ctx.letterSpacing = '4px'
  ctx.fillText('MEMORY NOTE / 025', 142, 778)
  ctx.letterSpacing = '0px'
  ctx.fillStyle = '#17151d'
  ctx.font = '31px "Songti SC", "Noto Serif SC", serif'
  const lines = wrapText(ctx, copy.body, 796)
  lines.forEach((line, index) => ctx.fillText(line, 142, 835 + index * 48))

  ctx.save()
  ctx.setLineDash([16, 12])
  ctx.strokeStyle = 'rgba(23,21,29,0.68)'
  ctx.lineWidth = 3
  ctx.beginPath()
  ctx.moveTo(144, tearY)
  ctx.lineTo(936, tearY)
  ctx.stroke()
  ctx.restore()

  ctx.fillStyle = '#0b0b12'
  ctx.beginPath()
  ctx.arc(ticketX, tearY, 28, 0, Math.PI * 2)
  ctx.fill()
  ctx.beginPath()
  ctx.arc(ticketX + ticketW, tearY, 28, 0, Math.PI * 2)
  ctx.fill()

  ctx.fillStyle = '#c5b5ee'
  ctx.strokeStyle = '#17151d'
  ctx.lineWidth = 4
  drawBurst(ctx, 196, 1145 + heightExtension, 63, 48)
  ctx.fill()
  ctx.stroke()
  ctx.fillStyle = '#17151d'
  ctx.textAlign = 'center'
  ctx.font = '900 21px "Arial Black", sans-serif'
  ctx.fillText('HEY~', 196, 1153 + heightExtension)

  ctx.textAlign = 'left'
  ctx.fillStyle = '#17151d'
  ctx.font = '900 43px "PingFang SC", sans-serif'
  ctx.fillText('收下这颗星', 284, 1125 + heightExtension)
  ctx.font = '600 21px "PingFang SC", sans-serif'
  ctx.fillStyle = 'rgba(23,21,29,0.7)'
  ctx.fillText('记忆编号已与这颗星绑定。', 286, 1166 + heightExtension)

  ctx.font = '800 17px ui-monospace, monospace'
  ctx.fillStyle = '#17151d'
  ctx.fillText('MEMORY CODE', 720, 1080 + heightExtension)
  ctx.strokeStyle = 'rgba(23,21,29,0.48)'
  ctx.lineWidth = 2
  roundRect(ctx, 720, 1096 + heightExtension, 224, 58, 14)
  ctx.stroke()
  ctx.font = '700 17px ui-monospace, monospace'
  ctx.textAlign = 'center'
  ctx.fillText(memoryTicketId(entry), 832, 1132 + heightExtension)

  const date = new Date(entry.createdAt)
  const dateText = `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, '0')}.${String(date.getDate()).padStart(2, '0')}  /  MILO ARCHIVE`
  ctx.textAlign = 'center'
  ctx.font = '700 17px ui-monospace, monospace'
  ctx.fillStyle = 'rgba(23,21,29,0.45)'
  ctx.fillText(dateText, W / 2, 1272 + heightExtension)

  const edgeGlow = ctx.createLinearGradient(ticketX, tearY, ticketX + ticketW, tearY)
  edgeGlow.addColorStop(0, hexAlpha(deep, 0))
  edgeGlow.addColorStop(0.5, hexAlpha(primary, 0.08))
  edgeGlow.addColorStop(1, hexAlpha(deep, 0))
  ctx.fillStyle = edgeGlow
  ctx.fillRect(ticketX + 40, tearY + 2, ticketW - 80, 2)
}

function drawOrbitTheatre(
  ctx: CanvasRenderingContext2D,
  entry: Entry,
  contract: CardRenderContract,
  loadedArtwork: LoadedMoodArtwork | null,
  random: () => number,
) {
  const copy = getStickerCopy(entry)
  const canvasH = ctx.canvas.height
  const heightExtension = canvasH - H
  const bg = ctx.createLinearGradient(0, 0, W, H)
  bg.addColorStop(0, '#332a59')
  bg.addColorStop(0.55, '#171831')
  bg.addColorStop(1, '#080b18')
  ctx.fillStyle = bg
  ctx.fillRect(0, 0, W, canvasH)

  paintStars(ctx, random, 104, '#e5def7')

  ctx.save()
  ctx.translate(314, 300)
  ctx.rotate(-0.27)
  for (let index = 0; index < 3; index++) {
    ctx.beginPath()
    ctx.ellipse(0, 0, 300 + index * 72, 100 + index * 23, 0, 0, Math.PI * 2)
    ctx.strokeStyle = `rgba(197, 181, 238, ${0.46 - index * 0.1})`
    ctx.lineWidth = 2
    ctx.stroke()
  }
  ctx.restore()

  drawMoodArtwork(ctx, loadedArtwork, contract.palette, { x: 160, y: 82, width: 264 })

  ctx.textAlign = 'left'
  ctx.fillStyle = 'rgba(228,220,247,0.76)'
  ctx.font = '700 21px "PingFang SC", sans-serif'
  ctx.letterSpacing = '5px'
  ctx.fillText('ORBITAL MEMORY THEATRE', 566, 132)
  ctx.letterSpacing = '0px'

  ctx.fillStyle = '#ffffff'
  ctx.font = '800 72px "PingFang SC", sans-serif'
  const headingLines = fitLines(wrapText(ctx, copy.heading, 440), 3)
  headingLines.forEach((line, index) => ctx.fillText(line, 566, 224 + index * 78))

  if (copy.labels) {
    ctx.fillStyle = '#0c0c1b'
    roundRect(ctx, 566, 450, 390, 52, 26)
    ctx.fill()
    ctx.fillStyle = '#d5c9f1'
    ctx.font = '600 24px "PingFang SC", sans-serif'
    ctx.fillText(copy.labels, 592, 485)
  }

  ctx.fillStyle = 'rgba(7,8,22,0.58)'
  roundRect(ctx, 92, 634, 896, 462 + heightExtension, 34)
  ctx.fill()
  ctx.strokeStyle = 'rgba(202,187,239,0.48)'
  ctx.lineWidth = 2
  roundRect(ctx, 92, 634, 896, 462 + heightExtension, 34)
  ctx.stroke()

  ctx.fillStyle = '#c6b4ed'
  ctx.font = '700 20px "PingFang SC", sans-serif'
  ctx.letterSpacing = '5px'
  ctx.fillText('PLAYBACK / MEMORY 07', 140, 694)
  ctx.letterSpacing = '0px'

  ctx.fillStyle = 'rgba(246,244,252,0.9)'
  ctx.font = '34px "Songti SC", "Noto Serif SC", serif'
  const lines = wrapText(ctx, copy.body, 790)
  lines.forEach((line, index) => ctx.fillText(line, 140, 770 + index * 58))

  ctx.save()
  ctx.translate(843, 1172 + heightExtension)
  ctx.rotate(-0.07)
  ctx.strokeStyle = 'rgba(205,191,239,0.8)'
  ctx.lineWidth = 2
  ctx.strokeRect(-126, -35, 252, 70)
  ctx.fillStyle = '#d4c7f1'
  ctx.font = '700 18px "PingFang SC", sans-serif'
  ctx.textAlign = 'center'
  ctx.fillText('MILO ARCHIVE / 07', 0, 7)
  ctx.restore()

  drawDate(ctx, entry, 'rgba(221,213,241,0.58)', canvasH - 96)
  drawBrand(ctx, 'rgba(205,193,236,0.52)', canvasH - 50)
}

export const templateRenderers: Record<StickerTemplateId, StickerRenderer> = {
  'planet-letter': drawMemoryTicket,
  'orbit-theatre': drawOrbitTheatre,
}

function measureCardHeight(
  ctx: CanvasRenderingContext2D,
  entry: Entry,
  templateId: StickerTemplateId,
): number {
  const copy = getStickerCopy(entry)
  if (templateId === 'planet-letter') {
    ctx.font = '31px "Songti SC", "Noto Serif SC", serif'
    return H + Math.max(0, wrapText(ctx, copy.body, 796).length - 4) * 48
  }

  ctx.font = '34px "Songti SC", "Noto Serif SC", serif'
  return H + Math.max(0, wrapText(ctx, copy.body, 790).length - 6) * 58
}

/** 把一条回忆异步渲染成可分享、可随正文增高的 PNG 卡片。 */
export async function renderCard(
  entry: Entry,
  templateId: StickerTemplateId = DEFAULT_STICKER_TEMPLATE,
  options: RenderCardOptions = {},
): Promise<string> {
  const { signal } = options
  const contract = cardRenderContract(entry.mood, templateId)
  let loadedArtwork: LoadedMoodArtwork | null = null

  if (contract.artwork) {
    const image = await loadImage(contract.artwork.sheet, signal)
    loadedArtwork = { image, artwork: contract.artwork }
  }
  throwIfAborted(signal)

  const canvas = document.createElement('canvas')
  canvas.width = W
  canvas.height = H
  let ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('当前浏览器无法生成卡片。')

  const measuredHeight = measureCardHeight(ctx, entry, contract.templateId)
  if (measuredHeight !== H) {
    canvas.height = measuredHeight
    ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('当前浏览器无法生成卡片。')
  }

  const random = createSeededRandom(stableHash(entry.id) ^ TEMPLATE_SEEDS[contract.templateId])
  templateRenderers[contract.templateId](ctx, entry, contract, loadedArtwork, random)

  throwIfAborted(signal)
  return canvas.toDataURL('image/png')
}
