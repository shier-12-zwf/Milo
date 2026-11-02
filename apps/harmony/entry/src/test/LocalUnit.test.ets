import { describe, it, expect } from '@ohos/hypium';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    it('assertContain', 0, () => {
      const value = 'abc';
      expect(value).assertContain('b');
      expect(value).assertEqual(value);
    });
  });
}
