import { describe, expect, it } from '@ohos/hypium';
import {
  getMoodAsset,
  moodAssetSheetLeftPercent,
  MOOD_ASSET_SHEETS,
  MOOD_SHEET_HEIGHT,
  MOOD_SHEET_PANEL_COUNT,
  MOOD_SHEET_WIDTH,
} from '../../../main/ets/core/model/MoodAssets';
import { MOODS, type MoodId } from '../../../main/ets/core/model/Moods';

interface MoodAssetExpectation {
  id: MoodId;
  sheet: string;
  panel: 0 | 1 | 2;
}

export default function moodAssetsTest() {
  describe('moodAssetsTest', () => {
    it('matches the Web sheet constants (1748 x 2700, three panels)', 0, () => {
      expect(MOOD_SHEET_WIDTH).assertEqual(1748);
      expect(MOOD_SHEET_HEIGHT).assertEqual(2700);
      expect(MOOD_SHEET_PANEL_COUNT).assertEqual(3);
    });

    it('exposes exactly five original mood sheets', 0, () => {
      expect(MOOD_ASSET_SHEETS.length).assertEqual(5);
      const names = MOOD_ASSET_SHEETS.slice().sort().join(',');
      expect(names).assertEqual(
        'mood_sheet_01,mood_sheet_02,mood_sheet_03,mood_sheet_04,mood_sheet_05',
      );
    });

    it('maps every catalogue mood to one of five sheets and a valid panel', 0, () => {
      for (let index = 0; index < MOODS.length; index += 1) {
        const mood = MOODS[index];
        const asset = getMoodAsset(mood.id as MoodId);
        expect(asset !== undefined).assertTrue();
        const sheetIndex = MOOD_ASSET_SHEETS.indexOf(asset!.sheet);
        expect(sheetIndex >= 0 && sheetIndex < 5).assertTrue();
        expect(asset!.panel === 0 || asset!.panel === 1 || asset!.panel === 2).assertTrue();
      }
    });

    it('lays out panels left-to-right in Web order', 0, () => {
      const expected: MoodAssetExpectation[] = [
        { id: 'very-low', sheet: 'mood_sheet_01', panel: 0 },
        { id: 'low', sheet: 'mood_sheet_01', panel: 1 },
        { id: 'heavy', sheet: 'mood_sheet_01', panel: 2 },
        { id: 'calm', sheet: 'mood_sheet_02', panel: 0 },
        { id: 'okay', sheet: 'mood_sheet_02', panel: 1 },
        { id: 'bright', sheet: 'mood_sheet_02', panel: 2 },
        { id: 'joyful', sheet: 'mood_sheet_03', panel: 0 },
        { id: 'lonely', sheet: 'mood_sheet_03', panel: 1 },
        { id: 'sad', sheet: 'mood_sheet_03', panel: 2 },
        { id: 'angry', sheet: 'mood_sheet_04', panel: 0 },
        { id: 'afraid', sheet: 'mood_sheet_04', panel: 1 },
        { id: 'disappointed', sheet: 'mood_sheet_04', panel: 2 },
        { id: 'anxious', sheet: 'mood_sheet_05', panel: 0 },
        { id: 'aggrieved', sheet: 'mood_sheet_05', panel: 1 },
        { id: 'embarrassed', sheet: 'mood_sheet_05', panel: 2 },
      ];
      for (let index = 0; index < expected.length; index += 1) {
        const want = expected[index];
        const got = getMoodAsset(want.id);
        expect(got !== undefined).assertTrue();
        expect(got!.sheet).assertEqual(want.sheet);
        expect(got!.panel).assertEqual(want.panel);
      }
    });

    it('overrides anxious focus offset to align its planet', 0, () => {
      const anxious = getMoodAsset('anxious');
      expect(anxious !== undefined).assertTrue();
      expect(anxious!.focusOffsetPercent).assertEqual(-9);
      // Other sheets use the Web defaults -11 / 0 / +11
      const calm = getMoodAsset('calm');
      const okay = getMoodAsset('okay');
      const bright = getMoodAsset('bright');
      expect(calm !== undefined && okay !== undefined && bright !== undefined).assertTrue();
      expect(calm!.focusOffsetPercent).assertEqual(-11);
      expect(okay!.focusOffsetPercent).assertEqual(0);
      expect(bright!.focusOffsetPercent).assertEqual(11);
    });

    it('computes the sheet left percent as panel * -100 + focus offset', 0, () => {
      const veryLow = getMoodAsset('very-low');
      const anxious = getMoodAsset('anxious');
      const bright = getMoodAsset('bright');
      expect(veryLow !== undefined && anxious !== undefined && bright !== undefined).assertTrue();
      // Panel 0 with default focus -11 -> 0 * -100 + -11 = -11
      expect(moodAssetSheetLeftPercent(veryLow!)).assertEqual(-11);
      // anxious panel 0 with override focus -9 -> 0 * -100 + -9 = -9
      expect(moodAssetSheetLeftPercent(anxious!)).assertEqual(-9);
      // Panel 2 with default focus +11 -> 2 * -100 + 11 = -189
      expect(moodAssetSheetLeftPercent(bright!)).assertEqual(-189);
    });

    it('rejects unknown mood ids without throwing and without partial data', 0, () => {
      const missing = getMoodAsset('nope' as MoodId);
      expect(missing === undefined).assertTrue();
    });
  });
}