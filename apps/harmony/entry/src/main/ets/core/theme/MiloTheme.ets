/**
 * Shared visual tokens for the native app. Values mirror the Web CSS in
 * `apps/web/src/styles.css` (the parts consumed by the screens we ship).
 * Anything here is a "knob" — change one place, the screens follow.
 */

interface ColorTokens {
  bg: string;
  bgSoft: string;
  surface: string;
  surfaceMuted: string;
  border: string;
  ink: string;
  inkDim: string;
  inkHint: string;
  accent: string;
  accentDim: string;
  warning: string;
  success: string;
}

interface RadiusTokens {
  chip: number;
  card: number;
  sticker: number;
  dial: number;
}

interface TypographyTokens {
  titleSize: number;
  subtitleSize: number;
  bodySize: number;
  captionSize: number;
  eyebrowSize: number;
}

interface SpacingTokens {
  edge: number;
  gutter: number;
  section: number;
}

const COLORS: ColorTokens = {
  bg: '#050608',
  bgSoft: '#0b0b10',
  surface: '#0f0f15',
  surfaceMuted: 'rgba(255, 255, 255, 0.04)',
  border: 'rgba(139, 124, 246, 0.30)',
  ink: '#ffffff',
  inkDim: '#c9befc',
  inkHint: '#8b87a6',
  accent: '#8b7cf6',
  accentDim: 'rgba(139, 124, 246, 0.18)',
  warning: '#f3b664',
  success: '#7fe2a7',
};

const RADIUS: RadiusTokens = {
  chip: 20,
  card: 14,
  sticker: 20,
  dial: 16,
};

const TYPOGRAPHY: TypographyTokens = {
  titleSize: 22,
  subtitleSize: 13,
  bodySize: 14,
  captionSize: 11,
  eyebrowSize: 12,
};

const SPACING: SpacingTokens = {
  edge: 16,
  gutter: 12,
  section: 24,
};

export const MILO_COLORS: ColorTokens = COLORS;
export const MILO_RADIUS: RadiusTokens = RADIUS;
export const MILO_TYPOGRAPHY: TypographyTokens = TYPOGRAPHY;
export const MILO_SPACING: SpacingTokens = SPACING;
