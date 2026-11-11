/**
 * Geometry for the「如果要给它一个名字」rotating word ring.
 *
 * Words sit on a circle, so with 12 words the single word at the very top
 * (270°) and the very bottom (90°) of the ring rest about 17vp further out
 * than their two neighbours (240°/300° and 60°/120°). On screen that reads as
 * one row of three labels with the middle one dropped below the others — the
 * AppGallery review flagged exactly this (「宁静」lower than「柔和」「淡然」).
 *
 * The vertical offset is therefore capped at the neighbours' row, which turns
 * the top and bottom arcs into flat chords: resting labels in those rows share
 * one baseline, every other label keeps its circular position, and the motion
 * stays continuous while the ring is dragged.
 */
export interface WordRingPoint {
  x: number;
  y: number;
}

/** Below this count the top/bottom words have no near neighbours to align with. */
export const WORD_RING_MIN_FLAT_COUNT = 8;

export function wordRingStepAngle(count: number): number {
  return count > 0 ? 360 / count : 360;
}

/** Largest vertical distance from the ring centre a word may sit at. */
export function wordRingRowLimit(count: number, radius: number): number {
  if (count < WORD_RING_MIN_FLAT_COUNT) {
    return radius;
  }
  return Math.cos(wordRingStepAngle(count) * Math.PI / 180) * radius;
}

export function wordRingPoint(
  index: number,
  count: number,
  ringAngle: number,
  center: number,
  radius: number,
): WordRingPoint {
  const angle = (index * wordRingStepAngle(count) - 90 + ringAngle) * Math.PI / 180;
  const limit = wordRingRowLimit(count, radius);
  let dy = Math.sin(angle) * radius;
  if (dy > limit) {
    dy = limit;
  } else if (dy < -limit) {
    dy = -limit;
  }
  const point: WordRingPoint = {
    x: center + Math.cos(angle) * radius,
    y: center + dy,
  };
  return point;
}
