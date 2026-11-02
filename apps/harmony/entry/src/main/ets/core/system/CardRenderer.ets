import {
  type DiaryEntry,
  type MoodId,
  type StickerTemplateId,
  DEFAULT_STICKER_TEMPLATE,
  VALID_STICKER_TEMPLATES,
} from '../../core/model/Domain';
import { moodPalette, moodLabel, moodWord } from '../../core/model/MoodAssets';

const CARD_WIDTH: number = 1080;
const MAX_BODY_LINES: number = 8;
const BODY_WIDTH: number = 796;
export const CARD_BODY_FONT_SIZE: number = 64;
export const CARD_BODY_LINE_HEIGHT: number = 88;

export interface CardTheme {
  backgroundTop: string;
  backgroundMid: string;
  backgroundBottom: string;
  silver: string;
  silverBright: string;
  lavender: string;
  panel: string;
  panelBorder: string;
  bodyText: string;
  secondaryText: string;
  faintText: string;
}

export const CARD_THEME: CardTheme = {
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
};

export interface StickerTemplateMeta {
  id: StickerTemplateId;
  name: string;
  tone: string;
}

export const STICKER_TEMPLATES: StickerTemplateMeta[] = [
  { id: 'planet-letter', name: '星球卡片', tone: '雾紫卡纸' },
  { id: 'orbit-theatre', name: '轨道剧场', tone: '社交海报' },
];

export function normalizeStickerTemplate(value: string | undefined): StickerTemplateId {
  if (value === undefined) {
    return DEFAULT_STICKER_TEMPLATE;
  }
  for (let index = 0; index < VALID_STICKER_TEMPLATES.length; index += 1) {
    if (VALID_STICKER_TEMPLATES[index] === value) {
      return value;
    }
  }
  return DEFAULT_STICKER_TEMPLATE;
}

export interface CardMoodArtwork {
  sheet: string;
  sourceXRatio: number;
  sourceWidthRatio: number;
  sourceYRatio: 0;
  sourceHeightRatio: 1;
}

export class CardMoodArtworkImpl implements CardMoodArtwork {
  sheet: string;
  sourceXRatio: number;
  sourceWidthRatio: number;
  sourceYRatio: 0 = 0;
  sourceHeightRatio: 1 = 1;

  constructor(sheet: string, sourceXRatio: number, sourceWidthRatio: number) {
    this.sheet = sheet;
    this.sourceXRatio = sourceXRatio;
    this.sourceWidthRatio = sourceWidthRatio;
  }
}

export function cardMoodArtwork(emotionId: MoodId | undefined): CardMoodArtwork | null {
  if (emotionId === undefined) {
    return null;
  }
  const sheet: string = `mood_orb_${emotionId}.png`;
  const sheetLeftPercent: number = 0;
  const panelCount: number = 1;
  return new CardMoodArtworkImpl(sheet, -sheetLeftPercent / (panelCount * 100), 1 / panelCount);
}

export interface CardRenderContract {
  templateId: StickerTemplateId;
  palette: string[];
  artwork: CardMoodArtwork | null;
  moodTintAlpha: number;
}

export class CardRenderContractImpl implements CardRenderContract {
  templateId: StickerTemplateId;
  palette: string[];
  artwork: CardMoodArtwork | null;
  moodTintAlpha: number;

  constructor(templateId: StickerTemplateId, palette: string[], artwork: CardMoodArtwork | null, moodTintAlpha: number) {
    this.templateId = templateId;
    this.palette = palette;
    this.artwork = artwork;
    this.moodTintAlpha = moodTintAlpha;
  }
}

export function cardRenderContract(
  valence: number,
  emotionId: MoodId | undefined,
  templateId: StickerTemplateId = DEFAULT_STICKER_TEMPLATE,
): CardRenderContract {
  return new CardRenderContractImpl(
    normalizeStickerTemplate(templateId),
    moodPalette(valence, emotionId),
    cardMoodArtwork(emotionId),
    0.16,
  );
}

export interface RectBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class RectBoundsImpl implements RectBounds {
  x: number;
  y: number;
  width: number;
  height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

export type RenderSectionKind = 'background' | 'artwork' | 'panel' | 'heading' | 'labels' | 'body' | 'ticket';

export interface RenderSection {
  kind: RenderSectionKind;
  bounds: RectBounds;
  text?: string;
  color?: string;
  fontSize?: number;
}

export class RenderSectionImpl implements RenderSection {
  kind: RenderSectionKind;
  bounds: RectBounds;
  text: string;
  color: string;
  fontSize: number;

  constructor(kind: RenderSectionKind, bounds: RectBounds, text: string, color: string, fontSize: number) {
    this.kind = kind;
    this.bounds = bounds;
    this.text = text;
    this.color = color;
    this.fontSize = fontSize;
  }
}

function section(kind: RenderSectionKind, x: number, y: number, width: number, height: number, text: string, color: string, fontSize: number): RenderSection {
  return new RenderSectionImpl(kind, new RectBoundsImpl(x, y, width, height), text, color, fontSize);
}

export interface CardLayout {
  templateId: StickerTemplateId;
  width: number;
  height: number;
  theme: CardTheme;
  palette: string[];
  moodTintAlpha: number;
  sections: RenderSection[];
  body: string;
}

export class CardLayoutImpl implements CardLayout {
  templateId: StickerTemplateId;
  width: number;
  height: number;
  theme: CardTheme;
  palette: string[];
  moodTintAlpha: number;
  sections: RenderSection[];
  body: string;

  constructor(templateId: StickerTemplateId, width: number, height: number, theme: CardTheme, palette: string[], moodTintAlpha: number, sections: RenderSection[], body: string) {
    this.templateId = templateId;
    this.width = width;
    this.height = height;
    this.theme = theme;
    this.palette = palette;
    this.moodTintAlpha = moodTintAlpha;
    this.sections = sections;
    this.body = body;
  }
}

export interface CardCopy {
  heading: string;
  labels: string;
  body: string;
}

export function getStickerCopy(entry: DiaryEntry): CardCopy {
  const heading: string = entry.kind === 'past' ? entry.timeMark ?? '过去的某一天' : '此刻';
  const labels: string = entry.mood.labels.join(' · ');
  const body: string = cardSummary(entry);
  return { heading: heading, labels: labels, body: body };
}

const CARD_SUMMARY_LIMIT = 48;
const SENTENCE_ENDS: string[] = ['。', '！', '？', '…', '!', '?', '；', ';'];

function isSpace(ch: string): boolean {
  return ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t';
}

/** Extract the leading sentence from a text, trimmed and capped at `limit` chars. */
function firstSentence(text: string, limit: number): string {
  let start = 0;
  while (start < text.length && isSpace(text.charAt(start))) {
    start += 1;
  }
  if (start >= text.length) {
    return '';
  }
  let end = start;
  while (end < text.length) {
    const ch = text.charAt(end);
    end += 1;
    if (SENTENCE_ENDS.indexOf(ch) >= 0) {
      break;
    }
  }
  let sentence = text.slice(start, end);
  if (sentence.length > limit) {
    sentence = `${sentence.slice(0, limit)}…`;
  }
  return sentence;
}

function longestUserLine(entry: DiaryEntry): string {
  if (entry.transcript === undefined) {
    return '';
  }
  let longest = '';
  for (let index = 0; index < entry.transcript.length; index += 1) {
    const message = entry.transcript[index];
    if (message.role !== 'user') {
      continue;
    }
    const text = message.text.trim();
    if (text.length > longest.length) {
      longest = text;
    }
  }
  return longest;
}

/**
 * One-sentence summary for the share card, built fully offline from the
 * diary/note text, the user's spoken answers, and the picked mood words.
 */
export function cardSummary(entry: DiaryEntry): string {
  const sources: string[] = [];
  if (entry.diary !== undefined && entry.diary.trim().length > 0) {
    sources.push(entry.diary);
  }
  if (entry.note !== undefined && entry.note.trim().length > 0) {
    sources.push(entry.note);
  }
  const spoken = longestUserLine(entry);
  if (spoken.length > 0) {
    sources.push(spoken);
  }
  for (let index = 0; index < sources.length; index += 1) {
    const sentence = firstSentence(sources[index], CARD_SUMMARY_LIMIT);
    if (sentence.length > 0) {
      return sentence;
    }
  }
  const labels = entry.mood.labels.slice(0, 3);
  if (labels.length > 0) {
    return `带着${labels.join('、')}的心情，这一刻被安静地收藏。`;
  }
  return '这一刻，被安静地收藏了。';
}

export function memoryTicketId(entry: DiaryEntry): string {
  const date: Date = new Date(entry.createdAt);
  const year: string = String(date.getFullYear()).slice(-2);
  const month: string = String(date.getMonth() + 1).padStart(2, '0');
  const day: string = String(date.getDate()).padStart(2, '0');
  const stamp: string = `${year}${month}${day}`;
  const clamped: number = Math.max(-3, Math.min(3, Math.round(entry.mood.valence)));
  const level: string = String(clamped + 3).padStart(2, '0');
  const hash = stableHash(entry.id);
  const suffix: string = hash.toString(36).toUpperCase().padStart(4, '0').slice(-4);
  return `ML-${stamp}-${level}-${suffix}`;
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

/** Greedy per-character wrap used by the card body text. */
export function wrapText(text: string, maxChars: number): string[] {
  const lines: string[] = [];
  const paragraphs = text.split('\n');
  for (let p = 0; p < paragraphs.length; p += 1) {
    const para = paragraphs[p];
    if (para.trim().length === 0) {
      lines.push('');
      continue;
    }
    let line = '';
    for (let i = 0; i < para.length; i += 1) {
      const ch = para.charAt(i);
      if (line.length > 0 && line.length + 1 > maxChars) {
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

export function fitLines(lines: string[], maxLines: number): string[] {
  const visible: string[] = [];
  for (let index = 0; index < lines.length && index < maxLines; index += 1) {
    visible.push(lines[index]);
  }
  if (lines.length > maxLines && visible.length > 0) {
    const lastIndex = visible.length - 1;
    const last = visible[lastIndex];
    const trimmed = last.replace(/[。，！？…]+$/u, '');
    visible[lastIndex] = `${trimmed}…`;
  }
  return visible;
}

/**
 * Compute deterministic layout sections for a given entry + template.
 * The actual `PixelMap` materialization is the UI layer's job; tests focus on
 * the deterministic layout contract.
 */
export function renderCardLayout(
  entry: DiaryEntry,
  templateId: StickerTemplateId = DEFAULT_STICKER_TEMPLATE,
): CardLayout {
  const normalized = normalizeStickerTemplate(templateId);
  const contract = cardRenderContract(entry.mood.valence, entry.mood.emotionId, normalized);
  const copy = getStickerCopy(entry);
  const lines = fitLines(wrapText(copy.body, Math.floor(BODY_WIDTH / CARD_BODY_FONT_SIZE)), MAX_BODY_LINES);
  const bodyHeight = lines.length * CARD_BODY_LINE_HEIGHT;
  const height = Math.max(1350, 860 + bodyHeight + 164);

  const sections: RenderSection[] = [];
  sections.push(section('background', 0, 0, CARD_WIDTH, height, '', CARD_THEME.backgroundTop, 0));
  sections.push(section('panel', 60, 80, CARD_WIDTH - 120, height - 160, '', CARD_THEME.panel, 0));
  if (contract.artwork !== null) {
    sections.push(section('artwork', 120, 140, CARD_WIDTH - 240, 540, '', contract.palette[0], 0));
  }
  sections.push(section('heading', 120, 720, CARD_WIDTH - 240, 64, copy.heading, CARD_THEME.silverBright, 52));
  if (copy.labels.length > 0) {
    sections.push(section('labels', 120, 800, CARD_WIDTH - 240, 44, copy.labels, CARD_THEME.lavender, 36));
  }
  sections.push(section('body', 120, 860, BODY_WIDTH, bodyHeight, lines.join('\n'), CARD_THEME.bodyText, CARD_BODY_FONT_SIZE));
  sections.push(section('ticket', 120, height - 110, CARD_WIDTH - 240, 40, memoryTicketId(entry), CARD_THEME.secondaryText, 28));

  return new CardLayoutImpl(
    normalized,
    CARD_WIDTH,
    height,
    CARD_THEME,
    contract.palette,
    contract.moodTintAlpha,
    sections,
    lines.join('\n'),
  );
}

/**
 * Stable key for memoising rendered stickers: changing template does not
 * invalidate, but the diary / note content does. Matches web `stickerRenderKey`.
 */
export function stickerRenderKey(entry: DiaryEntry): string {
  const parts: string[] = [
    entry.id,
    String(entry.createdAt),
    entry.kind,
    String(entry.mood.valence),
    entry.mood.labels.join(','),
    entry.mood.emotionId ?? '',
    entry.timeMark ?? '',
    entry.note ?? '',
    entry.diary ?? '',
  ];
  return parts.join('|');
}

/** Re-export mood helpers so card consumers don't need to import both modules. */
export class CardMoodHelpers {
  static label(valence: number, emotionId: MoodId | undefined): string {
    return moodLabel(valence, emotionId);
  }
  static word(valence: number, emotionId: MoodId | undefined): string {
    return moodWord(valence, emotionId);
  }
  static palette(valence: number, emotionId: MoodId | undefined): string[] {
    return moodPalette(valence, emotionId);
  }
}
