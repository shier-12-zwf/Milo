import { image } from '@kit.ImageKit';
import {
  type DiaryEntry,
  type MoodId,
  type StickerTemplateId,
} from '../model/Domain';
import {
  getMoodAsset,
  moodAssetSheetLeftPercent,
  moodLabel,
  moodPalette,
  MOOD_SHEET_PANEL_COUNT,
  type MoodAssetSheetName,
} from '../model/MoodAssets';
import { MOODS } from '../model/Moods';
import {
  CARD_BODY_FONT_SIZE,
  CARD_BODY_LINE_HEIGHT,
  getStickerCopy,
  memoryTicketId,
  normalizeStickerTemplate,
} from './CardRenderer';

/**
 * Both sticker templates use a 1080-unit design grid. ArkUI's default
 * canvas coordinates are vp, so font sizes must also use vp: Web-style px
 * fonts shrink relative to the artwork on high-density screens. The caller
 * scales the entire context once by the preview width / 1080.
 */

export const CARD_DESIGN_WIDTH: number = 1080;
/** Base design height of the "planet-letter" memory ticket template. */
export const CARD_DESIGN_HEIGHT: number = 1434;
/** Base design height of the "orbit-theatre" template (taller playback panel). */
export const ORBIT_THEATRE_DESIGN_HEIGHT: number = 1530;

/** Artwork crop ratios for the 3-panel mood sheet, mirroring web `cardMoodArtwork`. */
export interface CardArtworkSource {
  sheet: MoodAssetSheetName;
  sourceXRatio: number;
  sourceWidthRatio: number;
  sourceYRatio: number;
  sourceHeightRatio: number;
}

/** Loaded sprite-sheet pixel map plus its intrinsic pixel dimensions. */
export interface CardArtworkImage {
  pixelMap: image.PixelMap;
  pixelWidth: number;
  pixelHeight: number;
}

export interface CardArtContract {
  templateId: StickerTemplateId;
  palette: string[];
  artwork: CardArtworkSource | null;
  moodTintAlpha: number;
}

const TEMPLATE_SEEDS: Record<StickerTemplateId, number> = {
  'planet-letter': 0x2d16a43f,
  'orbit-theatre': 0x418be2c7,
};

/** Chinese label for a mood state; mirrors web `moodLabel` (emotionId → label). */
export function cardMoodLabel(valence: number, emotionId: MoodId | undefined): string {
  if (emotionId !== undefined) {
    for (let index = 0; index < MOODS.length; index += 1) {
      const definition = MOODS[index];
      if (definition.id === emotionId && definition.labels.length > 0) {
        return definition.labels[0];
      }
    }
  }
  return moodLabel(valence, undefined);
}

export function cardArtContract(entry: DiaryEntry, templateId: StickerTemplateId): CardArtContract {
  const asset = entry.mood.emotionId !== undefined ? getMoodAsset(entry.mood.emotionId) : undefined;
  let artwork: CardArtworkSource | null = null;
  if (asset !== undefined) {
    const source: CardArtworkSource = {
      sheet: asset.sheet,
      sourceXRatio: -moodAssetSheetLeftPercent(asset) / (MOOD_SHEET_PANEL_COUNT * 100),
      sourceWidthRatio: 1 / MOOD_SHEET_PANEL_COUNT,
      sourceYRatio: 0,
      sourceHeightRatio: 1,
    };
    artwork = source;
  }
  const contract: CardArtContract = {
    templateId: normalizeStickerTemplate(templateId),
    palette: moodPalette(entry.mood.valence, entry.mood.emotionId),
    artwork: artwork,
    moodTintAlpha: 0.16,
  };
  return contract;
}

function stableHash(value: string): number {
  let hash: number = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    const code: number = value.charCodeAt(index);
    hash ^= code;
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function createSeededRandom(seed: number): () => number {
  let state: number = seed >>> 0;
  return (): number => {
    state += 0x6d2b79f5;
    let value: number = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

const LINE_TAIL: RegExp = new RegExp('[。，！？…]+$', 'u');

function hexAlpha(hex: string, alpha: number): string {
  const normalized: string = hex.startsWith('#') ? hex.slice(1) : hex;
  const value: number = Number.parseInt(normalized, 16);
  const red: number = (value >> 16) & 255;
  const green: number = (value >> 8) & 255;
  const blue: number = value & 255;
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

function roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Keep measurement in the same design space for thumbnails and full cards. */
function measureTextDesign(ctx: CanvasRenderingContext2D, text: string): number {
  ctx.save();
  ctx.resetTransform();
  const width: number = ctx.measureText(text).width;
  ctx.restore();
  return width;
}

/** Character-wrap in design units, independent of the preview transform. */
function wrapTextDesign(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
  const lines: string[] = [];
  const paragraphs: string[] = text.split('\n');
  for (let p = 0; p < paragraphs.length; p += 1) {
    const para: string = paragraphs[p];
    if (para.trim().length === 0) {
      lines.push('');
      continue;
    }
    let line: string = '';
    for (let index = 0; index < para.length; index += 1) {
      const ch: string = para.charAt(index);
      if (line.length > 0 && measureTextDesign(ctx, line + ch) > maxWidth) {
        lines.push(line);
        line = ch;
      } else {
        line += ch;
      }
    }
    if (line.length > 0) {
      lines.push(line);
    }
  }
  return lines;
}

function fitTextDesign(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
  if (measureTextDesign(ctx, text) <= maxWidth) {
    return text;
  }
  let visible: string = text;
  while (visible.length > 0 && measureTextDesign(ctx, `${visible}…`) > maxWidth) {
    visible = visible.slice(0, visible.length - 1);
  }
  return `${visible}…`;
}

function fitLines(lines: string[], maxLines: number): string[] {
  const visible: string[] = [];
  for (let index = 0; index < lines.length && index < maxLines; index += 1) {
    visible.push(lines[index]);
  }
  if (lines.length > maxLines && visible.length > 0) {
    const lastIndex: number = visible.length - 1;
    visible[lastIndex] = `${visible[lastIndex].replace(LINE_TAIL, '')}…`;
  }
  return visible;
}

/**
 * Web relies on the canvas `letterSpacing` property which ArkUI does not
 * expose; this helper draws text with an equivalent extra tracking.
 */
function drawSpacedText(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  spacing: number,
  centered: boolean,
): void {
  const previousAlign: CanvasTextAlign = ctx.textAlign;
  ctx.textAlign = 'left';
  let total: number = 0;
  for (let index = 0; index < text.length; index += 1) {
    total += measureTextDesign(ctx, text.charAt(index));
  }
  total += spacing * Math.max(0, text.length - 1);
  let cursor: number = centered ? x - total / 2 : x;
  for (let index = 0; index < text.length; index += 1) {
    const ch: string = text.charAt(index);
    ctx.fillText(ch, cursor, y);
    cursor += measureTextDesign(ctx, ch) + spacing;
  }
  ctx.textAlign = previousAlign;
}

function paintStars(
  ctx: CanvasRenderingContext2D,
  random: () => number,
  count: number,
  color: string,
  yStart: number,
  yEnd: number,
): void {
  ctx.save();
  for (let index = 0; index < count; index += 1) {
    const x: number = random() * CARD_DESIGN_WIDTH;
    const y: number = yStart + random() * (yEnd - yStart);
    const radius: number = random() * 2.1 + 0.45;
    ctx.globalAlpha = random() * 0.56 + 0.16;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function drawDateLine(ctx: CanvasRenderingContext2D, entry: DiaryEntry, color: string, y: number): void {
  const date: Date = new Date(entry.createdAt);
  const dateText: string = `${date.getFullYear()} 年 ${date.getMonth() + 1} 月 ${date.getDate()} 日 · 记于米洛`;
  ctx.textAlign = 'center';
  ctx.font = '36vp sans-serif';
  ctx.fillStyle = color;
  ctx.fillText(dateText, CARD_DESIGN_WIDTH / 2, y);
}

function drawBrand(ctx: CanvasRenderingContext2D, color: string, y: number): void {
  ctx.font = 'bold 22vp sans-serif';
  ctx.fillStyle = color;
  drawSpacedText(ctx, 'M I L O', CARD_DESIGN_WIDTH / 2, y, 8, true);
}

function drawHatchRule(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, color: string): void {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  for (let offset = 0; offset < width; offset += 10) {
    ctx.beginPath();
    ctx.moveTo(x + offset, y + 6);
    ctx.lineTo(x + offset + 5, y - 6);
    ctx.stroke();
  }
  ctx.restore();
}

function drawTicketTag(ctx: CanvasRenderingContext2D, text: string, x: number, y: number): void {
  ctx.font = 'bold 34vp sans-serif';
  const label: string = `# ${text}`;
  const width: number = measureTextDesign(ctx, label) + 36;
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  ctx.strokeStyle = 'rgba(21,19,27,0.58)';
  ctx.lineWidth = 2;
  roundRectPath(ctx, x, y, width, 54, 27);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = '#17151d';
  ctx.textAlign = 'left';
  ctx.fillText(label, x + 18, y + 39);
}

function drawBurst(ctx: CanvasRenderingContext2D, x: number, y: number, outerRadius: number, innerRadius: number): void {
  ctx.beginPath();
  for (let index = 0; index < 24; index += 1) {
    const angle: number = -Math.PI / 2 + (index * Math.PI) / 12;
    const radius: number = index % 2 === 0 ? outerRadius : innerRadius;
    const pointX: number = x + Math.cos(angle) * radius;
    const pointY: number = y + Math.sin(angle) * radius;
    if (index === 0) {
      ctx.moveTo(pointX, pointY);
    } else {
      ctx.lineTo(pointX, pointY);
    }
  }
  ctx.closePath();
}

interface ArtworkDestination {
  x: number;
  y: number;
  width: number;
}

function drawLegacyOrb(
  ctx: CanvasRenderingContext2D,
  destination: ArtworkDestination,
  palette: string[],
): void {
  const main: string = palette[0];
  const deep: string = palette[1];
  const light: string = palette[2];
  const height: number = destination.width * (2700 / 1748);
  const x: number = destination.x + destination.width / 2;
  const y: number = destination.y + height / 2;
  const radius: number = destination.width * 0.43;
  const orb: CanvasGradient = ctx.createRadialGradient(x - radius * 0.3, y - radius * 0.32, radius * 0.12, x, y, radius);
  orb.addColorStop(0, light);
  orb.addColorStop(0.55, main);
  orb.addColorStop(1, deep);
  ctx.save();
  ctx.shadowColor = hexAlpha(main, 0.28);
  ctx.shadowBlur = radius * 0.65;
  ctx.fillStyle = orb;
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawMoodArtwork(
  ctx: CanvasRenderingContext2D,
  contract: CardArtContract,
  artworkImage: CardArtworkImage | null,
  destination: ArtworkDestination,
): void {
  const source: CardArtworkSource | null = contract.artwork;
  if (artworkImage === null || source === null) {
    drawLegacyOrb(ctx, destination, contract.palette);
    return;
  }
  const height: number = destination.width * (2700 / 1748);
  const sourceX: number = artworkImage.pixelWidth * source.sourceXRatio;
  const sourceWidth: number = artworkImage.pixelWidth * source.sourceWidthRatio;
  const sourceY: number = artworkImage.pixelHeight * source.sourceYRatio;
  const sourceHeight: number = artworkImage.pixelHeight * source.sourceHeightRatio;
  ctx.save();
  // Soft glow behind the artwork (the clipped draw below cannot cast shadows).
  const glowRadius: number = Math.max(destination.width, height) * 0.72;
  const glow: CanvasGradient = ctx.createRadialGradient(
    destination.x + destination.width / 2,
    destination.y + height / 2,
    glowRadius * 0.35,
    destination.x + destination.width / 2,
    destination.y + height / 2,
    glowRadius,
  );
  glow.addColorStop(0, hexAlpha(contract.palette[0], 0.24));
  glow.addColorStop(1, hexAlpha(contract.palette[0], 0));
  ctx.fillStyle = glow;
  ctx.fillRect(
    destination.x - glowRadius,
    destination.y - glowRadius,
    destination.width + glowRadius * 2,
    height + glowRadius * 2,
  );
  // NOTE: the 9-arg drawImage(pixelMap, sx, sy, sw, sh, dx, dy, dw, dh) samples
  // incorrectly on some devices (wrong source rect); emulate it with the
  // verified 5-arg overload + clip/translate/scale.
  const scaleX: number = destination.width / sourceWidth;
  const scaleY: number = height / sourceHeight;
  ctx.beginPath();
  ctx.rect(destination.x, destination.y, destination.width, height);
  ctx.clip();
  ctx.translate(destination.x - sourceX * scaleX, destination.y - sourceY * scaleY);
  ctx.scale(scaleX, scaleY);
  ctx.drawImage(
    artworkImage.pixelMap,
    0,
    0,
    artworkImage.pixelWidth,
    artworkImage.pixelHeight,
  );
  ctx.restore();
}

/**
 * Measure the card's design height for the given template; long diary text
 * extends the canvas exactly like web `measureCardHeight`. MUST be called on
 * an unscaled context (font sizes below are design units).
 */
export function measureCardDesignHeight(
  ctx: CanvasRenderingContext2D,
  entry: DiaryEntry,
  templateId: StickerTemplateId,
): number {
  const copy = getStickerCopy(entry);
  const normalized: StickerTemplateId = normalizeStickerTemplate(templateId);
  if (normalized === 'planet-letter') {
    ctx.font = `${CARD_BODY_FONT_SIZE}vp serif`;
    return CARD_DESIGN_HEIGHT + Math.max(0, wrapTextDesign(ctx, copy.body, 796).length - 3) * CARD_BODY_LINE_HEIGHT;
  }
  ctx.font = `${CARD_BODY_FONT_SIZE}vp serif`;
  return ORBIT_THEATRE_DESIGN_HEIGHT + Math.max(0, wrapTextDesign(ctx, copy.body, 790).length - 6) * CARD_BODY_LINE_HEIGHT;
}

function drawMemoryTicket(
  ctx: CanvasRenderingContext2D,
  canvasH: number,
  entry: DiaryEntry,
  contract: CardArtContract,
  artworkImage: CardArtworkImage | null,
  random: () => number,
): void {
  const copy = getStickerCopy(entry);
  const primary: string = contract.palette[0];
  const deep: string = contract.palette[1];
  const heightExtension: number = canvasH - CARD_DESIGN_HEIGHT;
  ctx.fillStyle = '#0b0b12';
  ctx.fillRect(0, 0, CARD_DESIGN_WIDTH, canvasH);

  const ambient: CanvasGradient = ctx.createRadialGradient(CARD_DESIGN_WIDTH * 0.74, 150, 20, CARD_DESIGN_WIDTH * 0.74, 150, 680);
  ambient.addColorStop(0, hexAlpha(primary, contract.moodTintAlpha));
  ambient.addColorStop(0.5, 'rgba(126,105,184,0.08)');
  ambient.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = ambient;
  ctx.fillRect(0, 0, CARD_DESIGN_WIDTH, canvasH * 0.72);
  paintStars(ctx, random, 76, '#ddd5f2', 0, canvasH);

  const ticketX: number = 88;
  const ticketY: number = 44;
  const ticketW: number = 904;
  const ticketH: number = 1346 + heightExtension;
  const ticketRadius: number = 58;
  const tearY: number = 1092 + heightExtension;

  ctx.save();
  roundRectPath(ctx, ticketX, ticketY, ticketW, ticketH, ticketRadius);
  ctx.clip();
  ctx.fillStyle = '#f0eff2';
  ctx.fillRect(ticketX, ticketY, ticketW, ticketH);

  const paper: CanvasGradient = ctx.createLinearGradient(ticketX, ticketY, ticketX + ticketW, tearY);
  paper.addColorStop(0, '#b8a7e9');
  paper.addColorStop(0.5, '#d6ccea');
  paper.addColorStop(1, '#e4def3');
  ctx.fillStyle = paper;
  ctx.fillRect(ticketX, ticketY, ticketW, tearY - ticketY);

  ctx.fillStyle = 'rgba(255,255,255,0.2)';
  ctx.beginPath();
  ctx.moveTo(ticketX + 490, ticketY);
  ctx.lineTo(ticketX + ticketW, ticketY);
  ctx.lineTo(ticketX + ticketW, ticketY + 350);
  ctx.lineTo(ticketX + 330, ticketY + 720);
  ctx.closePath();
  ctx.fill();
  ctx.restore();

  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.38)';
  ctx.shadowBlur = 42;
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 2;
  roundRectPath(ctx, ticketX, ticketY, ticketW, ticketH, ticketRadius);
  ctx.stroke();
  ctx.restore();

  ctx.fillStyle = '#17151d';
  ctx.textAlign = 'left';
  ctx.font = 'bold 29vp sans-serif';
  ctx.fillText('MILO', 132, 111);
  ctx.fillText('MILO', 456, 111);
  ctx.fillText('MILO', 790, 111);
  drawHatchRule(ctx, 228, 101, 184, 'rgba(23,21,29,0.5)');
  drawHatchRule(ctx, 556, 101, 186, 'rgba(23,21,29,0.5)');

  drawMoodArtwork(ctx, contract, artworkImage, { x: 130, y: 130, width: 86 });

  const mainMood: string = cardMoodLabel(entry.mood.valence, entry.mood.emotionId);
  let secondaryMood: string | undefined = undefined;
  for (let index = 0; index < entry.mood.labels.length; index += 1) {
    if (entry.mood.labels[index] !== mainMood) {
      secondaryMood = entry.mood.labels[index];
      break;
    }
  }
  const identityMood: string = secondaryMood !== undefined ? `${mainMood} · ${secondaryMood}` : mainMood;
  ctx.fillStyle = '#17151d';
  ctx.font = 'bold 46vp sans-serif';
  ctx.fillText(fitTextDesign(ctx, identityMood, 480), 238, 204);
  ctx.font = 'bold 24vp monospace';
  ctx.fillStyle = 'rgba(23,21,29,0.66)';
  ctx.fillText(`PLANET ID: ${memoryTicketId(entry)}`, 238, 239);

  ctx.save();
  ctx.translate(846, 202);
  ctx.rotate(0.045);
  ctx.strokeStyle = '#17151d';
  ctx.lineWidth = 3;
  ctx.strokeRect(-94, -41, 188, 82);
  ctx.fillStyle = '#17151d';
  ctx.textAlign = 'center';
  ctx.font = 'bold 16vp monospace';
  ctx.fillText('ORIGINAL', 0, -8);
  ctx.fillText('MEMORY', 0, 18);
  ctx.restore();

  const showcaseX: number = 140;
  const showcaseY: number = 292;
  const showcaseW: number = 800;
  const showcaseH: number = 355;
  ctx.fillStyle = 'rgba(248,246,251,0.7)';
  roundRectPath(ctx, showcaseX, showcaseY, showcaseW, showcaseH, 34);
  ctx.fill();
  ctx.strokeStyle = '#17151d';
  ctx.lineWidth = 5;
  roundRectPath(ctx, showcaseX, showcaseY, showcaseW, showcaseH, 34);
  ctx.stroke();

  ctx.save();
  roundRectPath(ctx, showcaseX + 4, showcaseY + 4, showcaseW - 8, showcaseH - 8, 30);
  ctx.clip();
  ctx.translate(525, 465);
  ctx.rotate(-0.16);
  ctx.strokeStyle = 'rgba(91,72,132,0.2)';
  ctx.lineWidth = 2;
  for (let index = 0; index < 3; index += 1) {
    ctx.beginPath();
    ctx.ellipse(0, 0, 470 + index * 72, 80 + index * 30, 0, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();

  ctx.save();
  roundRectPath(ctx, showcaseX + 4, showcaseY + 4, showcaseW - 8, showcaseH - 8, 30);
  ctx.clip();
  drawMoodArtwork(ctx, contract, artworkImage, { x: 394, y: 239, width: 292 });
  ctx.restore();

  ctx.fillStyle = '#17151d';
  roundRectPath(ctx, 320, 591, 440, 66, 15);
  ctx.fill();
  ctx.fillStyle = '#fff';
  ctx.textAlign = 'center';
  ctx.font = 'bold 40vp sans-serif';
  ctx.fillText(fitTextDesign(ctx, copy.heading, 400), CARD_DESIGN_WIDTH / 2, 638);

  const tags: string[] = entry.mood.labels.length > 0 ? entry.mood.labels.slice(0, 3) : [mainMood];
  let tagX: number = 140;
  for (let index = 0; index < tags.length; index += 1) {
    drawTicketTag(ctx, tags[index], tagX, 694);
    ctx.font = 'bold 34vp sans-serif';
    tagX += measureTextDesign(ctx, `# ${tags[index]}`) + 54;
  }

  ctx.textAlign = 'left';
  ctx.fillStyle = 'rgba(23,21,29,0.62)';
  ctx.font = 'bold 17vp monospace';
  drawSpacedText(ctx, 'MEMORY NOTE / 025', 142, 766, 4, false);
  ctx.fillStyle = '#17151d';
  ctx.font = `${CARD_BODY_FONT_SIZE}vp serif`;
  const lines: string[] = wrapTextDesign(ctx, copy.body, 796);
  for (let index = 0; index < lines.length; index += 1) {
    ctx.fillText(lines[index], 142, 860 + index * CARD_BODY_LINE_HEIGHT);
  }

  ctx.save();
  ctx.setLineDash([16, 12]);
  ctx.strokeStyle = 'rgba(23,21,29,0.68)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(144, tearY);
  ctx.lineTo(936, tearY);
  ctx.stroke();
  ctx.restore();

  ctx.fillStyle = '#0b0b12';
  ctx.beginPath();
  ctx.arc(ticketX, tearY, 28, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(ticketX + ticketW, tearY, 28, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = '#c5b5ee';
  ctx.strokeStyle = '#17151d';
  ctx.lineWidth = 4;
  drawBurst(ctx, 196, 1229 + heightExtension, 63, 48);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = '#17151d';
  ctx.textAlign = 'center';
  ctx.font = 'bold 21vp sans-serif';
  ctx.fillText('HEY~', 196, 1237 + heightExtension);

  ctx.textAlign = 'left';
  ctx.fillStyle = '#17151d';
  ctx.font = 'bold 43vp sans-serif';
  ctx.fillText('收下这颗星', 284, 1209 + heightExtension);
  ctx.font = 'normal 30vp sans-serif';
  ctx.fillStyle = 'rgba(23,21,29,0.7)';
  ctx.fillText('记忆编号已与这颗星绑定。', 286, 1250 + heightExtension);

  ctx.font = 'bold 17vp monospace';
  ctx.fillStyle = '#17151d';
  ctx.fillText('MEMORY CODE', 720, 1164 + heightExtension);
  ctx.strokeStyle = 'rgba(23,21,29,0.48)';
  ctx.lineWidth = 2;
  roundRectPath(ctx, 720, 1180 + heightExtension, 224, 58, 14);
  ctx.stroke();
  ctx.font = 'bold 17vp monospace';
  ctx.textAlign = 'center';
  ctx.fillText(memoryTicketId(entry), 832, 1216 + heightExtension);

  const date: Date = new Date(entry.createdAt);
  const month: string = String(date.getMonth() + 1).padStart(2, '0');
  const day: string = String(date.getDate()).padStart(2, '0');
  const dateText: string = `${date.getFullYear()}.${month}.${day}  /  MILO ARCHIVE`;
  ctx.textAlign = 'center';
  ctx.font = '32vp sans-serif';
  ctx.fillStyle = 'rgba(23,21,29,0.72)';
  ctx.fillText(dateText, CARD_DESIGN_WIDTH / 2, 1356 + heightExtension);

  const edgeGlow: CanvasGradient = ctx.createLinearGradient(ticketX, tearY, ticketX + ticketW, tearY);
  edgeGlow.addColorStop(0, hexAlpha(deep, 0));
  edgeGlow.addColorStop(0.5, hexAlpha(primary, 0.08));
  edgeGlow.addColorStop(1, hexAlpha(deep, 0));
  ctx.fillStyle = edgeGlow;
  ctx.fillRect(ticketX + 40, tearY + 2, ticketW - 80, 2);
}

function drawOrbitTheatre(
  ctx: CanvasRenderingContext2D,
  canvasH: number,
  entry: DiaryEntry,
  contract: CardArtContract,
  artworkImage: CardArtworkImage | null,
  random: () => number,
): void {
  const copy = getStickerCopy(entry);
  const heightExtension: number = canvasH - ORBIT_THEATRE_DESIGN_HEIGHT;
  const bg: CanvasGradient = ctx.createLinearGradient(0, 0, CARD_DESIGN_WIDTH, CARD_DESIGN_HEIGHT);
  bg.addColorStop(0, '#332a59');
  bg.addColorStop(0.55, '#171831');
  bg.addColorStop(1, '#080b18');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, CARD_DESIGN_WIDTH, canvasH);

  paintStars(ctx, random, 104, '#e5def7', 0, canvasH);

  ctx.save();
  ctx.translate(314, 300);
  ctx.rotate(-0.27);
  for (let index = 0; index < 3; index += 1) {
    ctx.beginPath();
    ctx.ellipse(0, 0, 300 + index * 72, 100 + index * 23, 0, 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(197, 181, 238, ${0.46 - index * 0.1})`;
    ctx.lineWidth = 2;
    ctx.stroke();
  }
  ctx.restore();

  drawMoodArtwork(ctx, contract, artworkImage, { x: 160, y: 82, width: 264 });

  ctx.textAlign = 'left';
  ctx.fillStyle = 'rgba(228,220,247,0.76)';
  ctx.font = 'bold 21vp sans-serif';
  drawSpacedText(ctx, 'ORBITAL MEMORY THEATRE', 566, 132, 5, false);

  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 72vp sans-serif';
  const headingLines: string[] = fitLines(wrapTextDesign(ctx, copy.heading, 440), 3);
  for (let index = 0; index < headingLines.length; index += 1) {
    ctx.fillText(fitTextDesign(ctx, headingLines[index], 440), 566, 224 + index * 78);
  }

  if (copy.labels.length > 0) {
    ctx.fillStyle = '#0c0c1b';
    roundRectPath(ctx, 566, 450, 390, 52, 26);
    ctx.fill();
    ctx.fillStyle = '#d5c9f1';
    ctx.font = 'bold 34vp sans-serif';
    ctx.fillText(fitTextDesign(ctx, copy.labels, 338), 592, 487);
  }

  ctx.fillStyle = 'rgba(7,8,22,0.58)';
  roundRectPath(ctx, 92, 634, 896, 640 + heightExtension, 34);
  ctx.fill();
  ctx.strokeStyle = 'rgba(202,187,239,0.48)';
  ctx.lineWidth = 2;
  roundRectPath(ctx, 92, 634, 896, 640 + heightExtension, 34);
  ctx.stroke();

  ctx.fillStyle = '#c6b4ed';
  ctx.font = 'bold 20vp sans-serif';
  drawSpacedText(ctx, 'PLAYBACK / MEMORY 07', 140, 694, 5, false);

  ctx.fillStyle = 'rgba(246,244,252,0.9)';
  ctx.font = `${CARD_BODY_FONT_SIZE}vp serif`;
  const lines: string[] = wrapTextDesign(ctx, copy.body, 790);
  for (let index = 0; index < lines.length; index += 1) {
    ctx.fillText(lines[index], 140, 784 + index * CARD_BODY_LINE_HEIGHT);
  }

  ctx.save();
  ctx.translate(843, 1350 + heightExtension);
  ctx.rotate(-0.07);
  ctx.strokeStyle = 'rgba(205,191,239,0.8)';
  ctx.lineWidth = 2;
  ctx.strokeRect(-126, -35, 252, 70);
  ctx.fillStyle = '#d4c7f1';
  ctx.font = 'bold 18vp sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('MILO ARCHIVE / 07', 0, 7);
  ctx.restore();

  drawDateLine(ctx, entry, 'rgba(221,213,241,0.82)', canvasH - 96);
  drawBrand(ctx, 'rgba(205,193,236,0.52)', canvasH - 50);
}

/** Draw the full card into `ctx` (already scaled so 1080 = component width). */
export function drawCardArt(
  ctx: CanvasRenderingContext2D,
  canvasH: number,
  entry: DiaryEntry,
  templateId: StickerTemplateId,
  artworkImage: CardArtworkImage | null,
): void {
  const contract: CardArtContract = cardArtContract(entry, templateId);
  const random: () => number = createSeededRandom(stableHash(entry.id) ^ TEMPLATE_SEEDS[contract.templateId]);
  if (contract.templateId === 'planet-letter') {
    drawMemoryTicket(ctx, canvasH, entry, contract, artworkImage, random);
    return;
  }
  drawOrbitTheatre(ctx, canvasH, entry, contract, artworkImage, random);
}
