import { describe, expect, it } from '@ohos/hypium';
import {
  CARD_BODY_FONT_SIZE,
  CARD_THEME,
  STICKER_TEMPLATES,
  cardMoodArtwork,
  cardRenderContract,
  cardSummary,
  fitLines,
  getStickerCopy,
  memoryTicketId,
  normalizeStickerTemplate,
  renderCardLayout,
  stickerRenderKey,
  wrapText,
  type CardMoodArtwork,
} from '../../../main/ets/core/system/CardRenderer';
import { type DiaryEntry, type MoodId, type StickerTemplateId, DEFAULT_STICKER_TEMPLATE } from '../../../main/ets/core/model/Domain';

function sampleEntry(): DiaryEntry {
  return {
    id: 'memory-1',
    createdAt: new Date('2026-07-25T08:00:00+08:00').getTime(),
    kind: 'past',
    mood: { valence: 2, labels: ['平静', '释然'], emotionId: 'bright' as MoodId },
    timeMark: '去年夏天',
    diary: '这一天一直安静地住在我心里。',
    diaryEnabled: true,
  };
}

function cardSuite() {
  describe('cardRendererTest', () => {
    it('exposes the deep-space silver-purple theme', 0, () => {
      expect(CARD_THEME.backgroundTop).assertEqual('#11111d');
      expect(CARD_THEME.backgroundMid).assertEqual('#070810');
      expect(CARD_THEME.backgroundBottom).assertEqual('#020308');
      expect(CARD_THEME.silver).assertEqual('#d9dce7');
      expect(CARD_THEME.lavender).assertEqual('#aaa4c4');
    });

    it('lists exactly the two sticker templates with the mist-violet card first', 0, () => {
      expect(STICKER_TEMPLATES.length).assertEqual(2);
      expect(STICKER_TEMPLATES[0].id).assertEqual('planet-letter');
      expect(STICKER_TEMPLATES[1].id).assertEqual('orbit-theatre');
      expect(DEFAULT_STICKER_TEMPLATE).assertEqual('planet-letter');
    });

    it('normalizeStickerTemplate falls back to default for unknown or empty values', 0, () => {
      expect(normalizeStickerTemplate(undefined)).assertEqual('planet-letter');
      expect(normalizeStickerTemplate('')).assertEqual('planet-letter');
      expect(normalizeStickerTemplate('mystery')).assertEqual('planet-letter');
      expect(normalizeStickerTemplate('orbit-theatre')).assertEqual('orbit-theatre');
    });

    it('cardMoodArtwork returns null for legacy valence-only records', 0, () => {
      const artwork: CardMoodArtwork | null = cardMoodArtwork(undefined);
      expect(artwork === null).assertTrue();
    });

    it('cardMoodArtwork returns the same sheet for every named mood', 0, () => {
      const ids: MoodId[] = ['very-low', 'low', 'heavy', 'calm', 'okay', 'bright', 'joyful', 'lonely', 'sad', 'angry', 'afraid', 'disappointed', 'anxious', 'aggrieved', 'embarrassed'];
      for (let index = 0; index < ids.length; index += 1) {
        const art = cardMoodArtwork(ids[index]);
        expect(art !== null).assertTrue();
      }
    });

    it('cardRenderContract preserves template id and tint bounds', 0, () => {
      const contract = cardRenderContract(2, 'bright' as MoodId, 'orbit-theatre');
      expect(contract.templateId).assertEqual('orbit-theatre');
      expect(contract.moodTintAlpha > 0).assertTrue();
      expect(contract.moodTintAlpha <= 0.18).assertTrue();
      expect(contract.artwork !== null).assertTrue();
    });

    it('cardRenderContract returns null artwork for valence-only moods', 0, () => {
      const contract = cardRenderContract(-2, undefined);
      expect(contract.artwork).assertEqual(null);
      expect(contract.palette.length).assertEqual(3);
    });

    it('getStickerCopy falls back to a quiet message when diary and note are both empty', 0, () => {
      const entry = sampleEntry();
      entry.diary = undefined;
      entry.note = undefined;
      const copy = getStickerCopy(entry);
      expect(copy.body.indexOf('收藏') >= 0).assertTrue();
    });

    it('getStickerCopy summarises the diary into its first sentence', 0, () => {
      const entry = sampleEntry();
      entry.diary = '那一天，我在海边坐了很久。后来风把云吹开了，我也就放下了。';
      const copy = getStickerCopy(entry);
      expect(copy.body).assertEqual('那一天，我在海边坐了很久。');
    });

    it('cardSummary summarises the note when the diary is missing', 0, () => {
      const entry = sampleEntry();
      entry.diary = undefined;
      entry.note = '今天把旧照片整理了一遍，突然很想她。';
      expect(cardSummary(entry)).assertEqual('今天把旧照片整理了一遍，突然很想她。');
    });

    it('cardSummary falls back to the longest spoken answer', 0, () => {
      const entry = sampleEntry();
      entry.diary = undefined;
      entry.note = undefined;
      entry.transcript = [
        { role: 'ai', text: '那段时间里，最先浮现在你眼前的，是怎样的一个画面？', ts: 1 },
        { role: 'user', text: '嗯。', ts: 2 },
        { role: 'user', text: '我看见了那年夏天的海边，傍晚有风，我们光着脚追浪花。', ts: 3 },
      ];
      expect(cardSummary(entry)).assertEqual('我看见了那年夏天的海边，傍晚有风，我们光着脚追浪花。');
    });

    it('cardSummary truncates overlong sources with an ellipsis', 0, () => {
      const entry = sampleEntry();
      entry.diary = undefined;
      entry.note = undefined;
      entry.transcript = [
        {
          role: 'user',
          text: '那是一个特别漫长的下午我在老家的院子里坐着看云一朵一朵慢慢地飘过去整个人放空了什么都不想做就只是安安静静地待着听风的声音',
          ts: 1,
        },
      ];
      const summary = cardSummary(entry);
      expect(summary.length <= 49).assertTrue();
      expect(summary.charAt(summary.length - 1)).assertEqual('…');
    });

    it('cardSummary composes from mood labels when nothing else exists', 0, () => {
      const entry = sampleEntry();
      entry.diary = undefined;
      entry.note = undefined;
      entry.transcript = [];
      const summary = cardSummary(entry);
      expect(summary.indexOf('平静') >= 0).assertTrue();
      expect(summary.indexOf('释然') >= 0).assertTrue();
      expect(summary.indexOf('收藏') >= 0).assertTrue();
    });

    it('memoryTicketId has the expected stable format', 0, () => {
      const id = memoryTicketId(sampleEntry());
      expect(id.indexOf('ML-') === 0).assertTrue();
      expect(id.length).assertEqual(17);
      // `ML-YYMMDD-LL-XXXX`
      expect(id.charAt(2)).assertEqual('-');
      expect(id.charAt(9)).assertEqual('-');
      expect(id.charAt(12)).assertEqual('-');
    });

    it('memoryTicketId is deterministic', 0, () => {
      const entry = sampleEntry();
      expect(memoryTicketId(entry)).assertEqual(memoryTicketId(entry));
    });

    it('wrapText splits long Chinese paragraphs into multiple lines', 0, () => {
      const lines = wrapText('今天下雨了，我一直坐在窗边想着那一年的事情。', 8);
      expect(lines.length > 1).assertTrue();
      for (let i = 0; i < lines.length; i += 1) {
        expect(lines[i].length <= 8).assertTrue();
      }
    });

    it('fitLines truncates with an ellipsis on the last visible line', 0, () => {
      const source = '第一行\n第二行\n第三行\n第四行\n第五行\n第六行';
      const visible = fitLines(source.split('\n'), 4);
      expect(visible.length).assertEqual(4);
      expect(visible[3].indexOf('…') >= 0).assertTrue();
    });

    it('renderCardLayout produces a 1080-wide layout with stable sections', 0, () => {
      const layout = renderCardLayout(sampleEntry(), 'planet-letter');
      expect(layout.width).assertEqual(1080);
      expect(layout.height >= 1350).assertTrue();
      expect(layout.templateId).assertEqual('planet-letter');
      expect(layout.sections.length > 0).assertTrue();
    });

    it('renderCardLayout contains heading, body and ticket sections', 0, () => {
      const layout = renderCardLayout(sampleEntry());
      let hasHeading = false;
      let hasBody = false;
      let hasTicket = false;
      for (let i = 0; i < layout.sections.length; i += 1) {
        const section = layout.sections[i];
        if (section.kind === 'heading') hasHeading = true;
        if (section.kind === 'body') hasBody = true;
        if (section.kind === 'ticket') hasTicket = true;
      }
      expect(hasHeading).assertTrue();
      expect(hasBody).assertTrue();
      expect(hasTicket).assertTrue();
    });

    it('card body remains readable when the 1080-unit design is shown at phone width', 0, () => {
      const layout = renderCardLayout(sampleEntry());
      for (let index = 0; index < layout.sections.length; index += 1) {
        const section = layout.sections[index];
        if (section.kind === 'body') {
          const previewFontSize: number = (section.fontSize ?? 0) * 320 / layout.width;
          expect(previewFontSize >= 18).assertTrue();
        }
      }
    });

    it('wraps a long Chinese summary at the visible body width and leaves room for the ticket', 0, () => {
      const entry = sampleEntry();
      entry.diary = '那是一个特别漫长的下午我在老家的院子里坐着看云一朵一朵慢慢地飘过去整个人放空了什么都不想做';
      const layout = renderCardLayout(entry);
      const lines: string[] = layout.body.split('\n');
      expect(lines.length >= 4).assertTrue();
      for (let index = 0; index < layout.sections.length; index += 1) {
        const section = layout.sections[index];
        if (section.kind === 'body') {
          for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
            expect(lines[lineIndex].length * CARD_BODY_FONT_SIZE <= section.bounds.width).assertTrue();
          }
          expect(section.bounds.y + section.bounds.height < layout.height - 110).assertTrue();
        }
      }
    });

    it('renderCardLayout omits the artwork section for legacy valence-only entries', 0, () => {
      const entry = sampleEntry();
      entry.mood = { valence: -2, labels: [] };
      const layout = renderCardLayout(entry);
      let hasArtwork = false;
      for (let i = 0; i < layout.sections.length; i += 1) {
        if (layout.sections[i].kind === 'artwork') hasArtwork = true;
      }
      expect(hasArtwork).assertEqual(false);
    });

    it('renderCardLayout normalizes an invalid template id to the default', 0, () => {
      const layout = renderCardLayout(sampleEntry(), 'mystery' as StickerTemplateId);
      expect(layout.templateId).assertEqual('planet-letter');
    });

    it('stickerRenderKey ignores template selection but reacts to diary edits', 0, () => {
      const entry = sampleEntry();
      const base = stickerRenderKey(entry);
      const otherTemplate: DiaryEntry = {
        id: entry.id,
        createdAt: entry.createdAt,
        kind: entry.kind,
        mood: entry.mood,
        timeMark: entry.timeMark,
        diary: entry.diary,
        diaryEnabled: entry.diaryEnabled,
        stickerTemplate: 'orbit-theatre',
      };
      const sameTemplate = stickerRenderKey(otherTemplate);
      expect(base).assertEqual(sameTemplate);
      const edited: DiaryEntry = {
        id: entry.id,
        createdAt: entry.createdAt,
        kind: entry.kind,
        mood: entry.mood,
        timeMark: entry.timeMark,
        diary: '内容发生变化。',
        diaryEnabled: entry.diaryEnabled,
      };
      const editedKey = stickerRenderKey(edited);
      expect(base === editedKey).assertEqual(false);
    });
  });
}

export default function cardRendererTest() {
  cardSuite();
}
