import { describe, expect, it } from '@ohos/hypium';
import { getMoodDescriptorWords } from '../../../main/ets/core/model/Moods';
import {
  wordRingPoint,
  wordRingRowLimit,
  type WordRingPoint,
} from '../../../main/ets/features/home/WordRingLayout';

const CENTER = 165;
const RADIUS = 128;

function near(a: number, b: number): boolean {
  return Math.abs(a - b) < 0.001;
}

function wordRingLayoutSuite() {
  describe('wordRingLayoutTest', () => {
    it('puts the bottom word on the same baseline as its two neighbours (AGC align review)', 0, () => {
      const count = getMoodDescriptorWords('calm', 0).length;
      expect(count).assertEqual(12);
      // calm ring at rest, bottom row: 柔和 (index 7, left) · 宁静 (index 6) · 淡然 (index 5, right)
      const right: WordRingPoint = wordRingPoint(5, count, 0, CENTER, RADIUS);
      const bottom: WordRingPoint = wordRingPoint(6, count, 0, CENTER, RADIUS);
      const left: WordRingPoint = wordRingPoint(7, count, 0, CENTER, RADIUS);
      expect(near(bottom.y, left.y)).assertTrue();
      expect(near(bottom.y, right.y)).assertTrue();
      expect(near(bottom.x, CENTER)).assertTrue();
      expect(bottom.x < right.x).assertTrue();
      expect(bottom.x > left.x).assertTrue();
    });

    it('puts the focused top word on the same baseline as its neighbours', 0, () => {
      const top = wordRingPoint(0, 12, 0, CENTER, RADIUS);
      expect(near(top.y, wordRingPoint(1, 12, 0, CENTER, RADIUS).y)).assertTrue();
      expect(near(top.y, wordRingPoint(11, 12, 0, CENTER, RADIUS).y)).assertTrue();
    });

    it('mirror pairs stay level and the other words keep their circular position', 0, () => {
      for (let index = 1; index < 6; index += 1) {
        const a = wordRingPoint(index, 12, 0, CENTER, RADIUS);
        const b = wordRingPoint(12 - index, 12, 0, CENTER, RADIUS);
        expect(near(a.y, b.y)).assertTrue();
      }
      const side = wordRingPoint(3, 12, 0, CENTER, RADIUS);
      expect(near(side.x, CENTER + RADIUS)).assertTrue();
      expect(near(side.y, CENTER)).assertTrue();
      const diagonal = wordRingPoint(2, 12, 0, CENTER, RADIUS);
      expect(near(diagonal.y, CENTER - RADIUS * Math.sin(Math.PI / 6))).assertTrue();
    });

    it('moves continuously while the ring is dragged', 0, () => {
      let previous = wordRingPoint(6, 12, 0, CENTER, RADIUS);
      for (let step = 1; step <= 360; step += 1) {
        const next = wordRingPoint(6, 12, step, CENTER, RADIUS);
        expect(Math.abs(next.y - previous.y) < 2.5).assertTrue();
        expect(Math.abs(next.x - previous.x) < 2.5).assertTrue();
        previous = next;
      }
    });

    it('never flattens small rings into the planet', 0, () => {
      expect(wordRingRowLimit(4, RADIUS)).assertEqual(RADIUS);
      expect(wordRingRowLimit(12, RADIUS) > 72 + 20).assertTrue();
    });
  });
}

export default function wordRingLayoutTest() {
  wordRingLayoutSuite();
}
