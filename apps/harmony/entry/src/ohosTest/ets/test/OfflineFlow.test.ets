import { describe, expect, it } from '@ohos/hypium';
import {
  FallbackGuide,
  fallbackDiary,
  moodWord,
  transcriptToText,
  wantsToPause,
} from '../../../main/ets/features/conversation/FallbackGuide';
import { type ChatMessage, type Draft } from '../../../main/ets/core/model/Domain';
import {
  initialRecallState,
  RecallEvents,
  transition,
  type RecallState,
} from '../../../main/ets/core/flow/RecallMachine';

const USER_ANSWERS: string[] = [
  '阳光很刺眼，蝉鸣很响',
  '是期末结束后的那个下午',
  '我和最好的朋友骑车去了河边',
  '那天让我知道什么叫纯粹的快乐',
  '现在回想起来，那条路我一直走到今天',
];

function driveToChat(): RecallState {
  let state = initialRecallState();
  state = transition(state, RecallEvents.selectMood('calm'));
  state = transition(state, RecallEvents.classify('past'));
  state = transition(state, RecallEvents.setTimeMark('去年夏天'));
  return state;
}

function offlineFlowSuite() {
  describe('offlineFlowTest', () => {
    it('walks the home → past → chat flow on a single state machine', 0, () => {
      const home = initialRecallState();
      expect(home.screen.name).assertEqual('home');

      const classify = transition(home, RecallEvents.selectMood('calm'));
      expect(classify.screen.name).assertEqual('classify');

      const past = transition(classify, RecallEvents.classify('past'));
      expect(past.screen.name).assertEqual('past-time');

      const chat = transition(past, RecallEvents.setTimeMark('去年夏天'));
      expect(chat.screen.name).assertEqual('chat');
      expect(chat.draft.timeMark).assertEqual('去年夏天');
      expect(chat.draft.kind).assertEqual('past');
    });

    it('offers one short prompt at a time and leaves room after the guided turns', 0, () => {
      const guide = new FallbackGuide('去年夏天');
      expect(guide.opening().indexOf('去年夏天') >= 0).assertTrue();
      expect(guide.opening().length <= 36).assertTrue();
      for (let index = 0; index < 5; index += 1) {
        const reply = guide.next();
        expect(reply.length <= 24).assertTrue();
        expect(reply.split('？').length <= 2).assertTrue();
      }
      expect(guide.isWrappingUp()).assertTrue();
      expect(guide.next()).assertEqual('嗯，我在听。');
    });

    it('accepts a pause and gives space when the user has no words', 0, () => {
      const guide = new FallbackGuide('去年夏天');
      expect(guide.next('我不想说了')).assertEqual('好，先停在这里。');
      expect(guide.next('不知道怎么说')).assertEqual('没关系，慢慢来。');
      expect(wantsToPause('那时候我不想说，但现在想说说')).assertEqual(false);
    });

    it('keeps long time labels out of the opening question', 0, () => {
      const guide = new FallbackGuide('那是几年前一个特别长的夏天，我和朋友第一次去海边的时候');
      expect(guide.opening().length <= 36).assertTrue();
    });

    it('runs the full offline trip and saves a first-person diary', 0, () => {
      const state = driveToChat();
      const guide = new FallbackGuide(state.draft.timeMark ?? '过去的某一天');

      const transcript: ChatMessage[] = [{ role: 'ai', text: guide.opening(), ts: 1 }];
      for (let index = 0; index < USER_ANSWERS.length; index += 1) {
        transcript.push({ role: 'user', text: USER_ANSWERS[index], ts: index + 2 });
        transcript.push({ role: 'ai', text: guide.next(), ts: index + 100 });
      }

      const draft: Draft = {
        mood: state.draft.mood,
        kind: state.draft.kind,
        timeMark: state.draft.timeMark,
        transcript: transcript,
        diaryEnabled: true,
      };

      const diary = fallbackDiary(draft);
      // 第一人称
      expect(diary.indexOf('我') >= 0).assertTrue();
      expect(diary).assertEqual(USER_ANSWERS.join('\n\n'));
      expect(diary.indexOf('心情：') < 0).assertTrue();
      expect(diary.indexOf('回忆：') < 0).assertTrue();
      for (let index = 0; index < USER_ANSWERS.length; index += 1) {
        expect(diary.indexOf(USER_ANSWERS[index]) >= 0).assertTrue();
      }
      // 没有 AI 旁白
      expect(diary.indexOf('引导者') < 0).assertTrue();
      expect(diary.indexOf('回响') < 0).assertTrue();

      const formatted = transcriptToText(transcript);
      expect(formatted.split('\n').length).assertEqual(transcript.length);
    });

    it('does not add gratitude, relief or other invented feelings to a short entry', 0, () => {
      const diary = fallbackDiary({
        mood: { valence: -2, labels: ['低落'] },
        timeMark: '昨天',
        transcript: [
          { role: 'ai', text: '你一定很感激那一天。', ts: 1 },
          { role: 'user', text: '我只记得下雨了。', ts: 2 },
        ],
        diaryEnabled: true,
      });
      expect(diary).assertEqual('我只记得下雨了。');
    });

    it('moodWord returns the catalogue label for known emotion ids', 0, () => {
      expect(moodWord(0, 'calm')).assertEqual('平静');
      expect(moodWord(2, 'bright')).assertEqual('明亮');
      expect(moodWord(-3, 'sad')).assertEqual('悲伤');
    });

    it('moodWord falls back to the valence bucket when no emotion id is set', 0, () => {
      expect(moodWord(0)).assertEqual('平静');
      expect(moodWord(3)).assertEqual('雀跃');
      expect(moodWord(-2)).assertEqual('低落');
    });
  });
}

export default function offlineFlowTest() {
  offlineFlowSuite();
}
