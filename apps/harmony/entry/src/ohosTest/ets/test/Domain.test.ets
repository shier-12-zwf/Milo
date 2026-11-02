import { describe, expect, it } from '@ohos/hypium';
import { Screen } from '../../../main/ets/core/model/Domain';
import { moodStateForId, MOODS } from '../../../main/ets/core/model/Moods';

export default function domainTest() {
  describe('domainTest', () => {
    it('keeps the exact web mood order', 0, () => {
      expect(MOODS.map((item) => item.id).join(',')).assertEqual(
        'very-low,low,heavy,calm,okay,bright,joyful,lonely,sad,angry,afraid,disappointed,anxious,aggrieved,embarrassed'
      );
    });

    it('preserves the web mood labels, valences, and emotion identifiers', 0, () => {
      expect(MOODS.map((item) => item.labels[0]).join(',')).assertEqual(
        '非常低落,低落,有些沉,平静,还不错,明亮,雀跃,孤独,悲伤,愤怒,害怕,失望,焦虑,委屈,尴尬'
      );
      expect(MOODS.map((item) => item.valence).join(',')).assertEqual(
        '-3,-2,-1,0,1,2,3,-2,-3,-2,-2,-2,-1,-2,-1'
      );
      expect(MOODS.map((item) => item.emotionId).join(',')).assertEqual(
        'very-low,low,heavy,calm,okay,bright,joyful,lonely,sad,angry,afraid,disappointed,anxious,aggrieved,embarrassed'
      );
    });

    it('returns a mutable draft copy without changing catalogue labels', 0, () => {
      const selected = moodStateForId('calm');
      if (selected === undefined) {
        expect(false).assertTrue();
        return;
      }
      selected.labels[0] = '自定义标签';
      expect(MOODS[3].labels[0]).assertEqual('平静');
    });

    it('creates entry screens with required identifiers', 0, () => {
      const home = Screen.home();
      const card = Screen.card('entry-card');
      const detail = Screen.detail('entry-detail');
      expect(home.name).assertEqual('home');
      expect(home.entryId === undefined).assertTrue();
      expect(card.name).assertEqual('card');
      expect(card.entryId).assertEqual('entry-card');
      expect(detail.name).assertEqual('detail');
      expect(detail.entryId).assertEqual('entry-detail');
    });
  });
}
