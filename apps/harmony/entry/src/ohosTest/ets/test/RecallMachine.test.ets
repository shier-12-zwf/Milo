import { describe, expect, it } from '@ohos/hypium';
import { initialRecallState, RecallEvents, transition } from '../../../main/ets/core/flow/RecallMachine';
import { type ChatMessage } from '../../../main/ets/core/model/Domain';
import { RecallSessionRepository, parseDraft } from '../../../main/ets/core/data/RecallSessionRepository';
import { MapKVStorage } from '../../../main/ets/core/data/KVStorage';

export default function recallMachineTest() {
  describe('recallMachineTest', () => {
    it('a second recording never inherits the previous descriptor labels', 0, () => {
      const selected = ['舒心', '有盼头'];
      let state = transition(initialRecallState(), RecallEvents.selectMood('okay', selected));
      selected.push('温暖');
      expect(state.draft.mood.labels.length).assertEqual(2);
      state = transition(state, RecallEvents.reset());
      state = transition(state, RecallEvents.selectMood('calm', ['安稳']));
      expect(state.draft.mood.labels.join(',')).assertEqual('安稳');
      state = transition(state, RecallEvents.reset());
      state = transition(state, RecallEvents.selectMood('okay', []));
      expect(state.draft.mood.labels.join(',')).assertEqual('还不错');
    });
    it('persists each chat turn and replaces a resumed transcript without duplicates', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      const messages: ChatMessage[] = [
        { role: 'ai', text: '最先想起什么？', ts: 1 },
        { role: 'user', text: '和朋友散步', ts: 2 },
      ];
      state = transition(state, RecallEvents.updateChat(messages, '还有一点没写完', false));
      const repo = new RecallSessionRepository(new MapKVStorage());
      repo.saveDraft(state);
      const restored = repo.loadDraft()!;
      expect(restored.draft.transcript.length).assertEqual(2);
      expect(restored.draft.aiEnabled).assertEqual(false);
      expect(restored.draft.inputText).assertEqual('还有一点没写完');
      state = transition(restored, RecallEvents.setDiary('和朋友散步'));
      state = transition(state, RecallEvents.back());
      expect(state.draft.aiEnabled).assertEqual(false);
      expect(state.draft.inputText).assertEqual('还有一点没写完');
      state = transition(state, RecallEvents.updateChat(messages, '还有一点没写完', false));
      expect(state.draft.transcript.length).assertEqual(2);
      messages[1].text = '改写外部消息';
      expect(state.draft.transcript[1].text).assertEqual('和朋友散步');
    });

    it('starts a fresh conversation when selecting a different memory time', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      state = transition(state, RecallEvents.appendMessage('user', '去散步', 1));
      state = transition(state, RecallEvents.updateChat(state.draft.transcript, '散步时还想起', false));
      state = transition(state, RecallEvents.back());
      state = transition(state, RecallEvents.setTimeMark('去年'));
      expect(state.draft.transcript.length).assertEqual(0);
      expect(state.draft.inputText).assertEqual('');
      expect(state.draft.aiEnabled).assertEqual(false);
    });

    it('restores an unsent input exactly and persists both AI toggle positions', 0, () => {
      const storage = new MapKVStorage();
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      const input = '  还有一点\n没想好怎么说  ';
      state = transition(state, RecallEvents.updateChat([], input, false));
      new RecallSessionRepository(storage).saveDraft(state);
      let restored = new RecallSessionRepository(storage).loadDraft()!;
      expect(restored.screen.name).assertEqual('chat');
      expect(restored.draft.transcript.length).assertEqual(0);
      expect(restored.draft.inputText).assertEqual(input);
      expect(restored.draft.aiEnabled).assertEqual(false);
      restored = transition(restored, RecallEvents.updateChat([], '', true));
      new RecallSessionRepository(storage).saveDraft(restored);
      restored = new RecallSessionRepository(storage).loadDraft()!;
      expect(restored.draft.inputText).assertEqual('');
      expect(restored.draft.aiEnabled).assertEqual(true);
    });

    it('keeps chat preferences and unsent input when returning to the same memory time', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      state = transition(state, RecallEvents.updateChat([], '刚刚想到', false));
      state = transition(state, RecallEvents.back());
      state = transition(state, RecallEvents.setTimeMark(' 昨天 '));
      expect(state.draft.inputText).assertEqual('刚刚想到');
      expect(state.draft.aiEnabled).assertEqual(false);
    });

    it('loads an existing schema 1 draft without the new optional chat fields', 0, () => {
      const restored = parseDraft('{"schemaVersion":1,"state":{"screenName":"chat","draft":{"valence":0,"labels":[],"kind":"past","timeMark":"昨天","diaryEnabled":true,"transcript":[]}}}');
      expect(restored !== undefined).assertTrue();
      expect(restored!.draft.timeMark).assertEqual('昨天');
      expect(restored!.draft.aiEnabled).assertEqual(undefined);
      expect(restored!.draft.inputText).assertEqual(undefined);
    });

    it('rejects invalid persisted chat preference and input types', 0, () => {
      const badPreference = parseDraft('{"schemaVersion":1,"state":{"screenName":"chat","draft":{"valence":0,"labels":[],"diaryEnabled":true,"transcript":[],"aiEnabled":"false"}}}');
      const badInput = parseDraft('{"schemaVersion":1,"state":{"screenName":"chat","draft":{"valence":0,"labels":[],"diaryEnabled":true,"transcript":[],"inputText":false}}}');
      expect(badPreference).assertEqual(undefined);
      expect(badInput).assertEqual(undefined);
    });

    it('routes a past draft through time and chat', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      expect(state.screen.name).assertEqual('past-time');
      state = transition(state, RecallEvents.setTimeMark('去年夏天'));
      expect(state.screen.name).assertEqual('chat');
      expect(state.draft.timeMark).assertEqual('去年夏天');
    });

    it('routes a current draft to note editing', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('bright'));
      state = transition(state, RecallEvents.classify('now'));
      state = transition(state, RecallEvents.setNote('窗外有光'));
      expect(state.screen.name).assertEqual('now-note');
      expect(state.draft.kind).assertEqual('now');
      expect(state.draft.note).assertEqual('窗外有光');
    });

    it('retains the draft when backing through recall screens', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('sad'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('去年冬天'));
      state = transition(state, RecallEvents.appendMessage('user', '下雪的晚上', 1));
      state = transition(state, RecallEvents.back());
      expect(state.screen.name).assertEqual('past-time');
      expect(state.draft.mood.emotionId).assertEqual('sad');
      expect(state.draft.timeMark).assertEqual('去年冬天');
      expect(state.draft.transcript[0].text).assertEqual('下雪的晚上');
    });

    it('returns the identical state for invalid forward events', 0, () => {
      const state = initialRecallState();
      const next = transition(state, RecallEvents.classify('past'));
      expect(next === state).assertTrue();
    });

    it('clears a populated draft only on reset', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('anxious'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      state = transition(state, RecallEvents.appendMessage('ai', '我在听', 2));
      state = transition(state, RecallEvents.reset());
      expect(state.screen.name).assertEqual('home');
      expect(state.draft.mood.valence).assertEqual(0);
      expect(state.draft.mood.labels.length).assertEqual(0);
      expect(state.draft.mood.emotionId === undefined).assertTrue();
      expect(state.draft.transcript.length).assertEqual(0);
      expect(state.draft.diaryEnabled).assertTrue();
    });

    it('canonicalizes time marks and rejects whitespace-only marks', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      const rejected = transition(state, RecallEvents.setTimeMark('  \n  '));
      expect(rejected === state).assertTrue();
      state = transition(state, RecallEvents.setTimeMark('  去年夏天  '));
      expect(state.screen.name).assertEqual('chat');
      expect(state.draft.timeMark).assertEqual('去年夏天');
    });

    it('preserves diary enablement changes across diary navigation', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.selectMood('calm'));
      state = transition(state, RecallEvents.classify('past'));
      state = transition(state, RecallEvents.setTimeMark('昨天'));
      state = transition(state, RecallEvents.setDiary('初稿'));
      state = transition(state, RecallEvents.setDiaryEnabled(false));
      expect(state.draft.diaryEnabled).assertFalse();
      state = transition(state, RecallEvents.setDiaryEnabled(true));
      state = transition(state, RecallEvents.back());
      expect(state.draft.diaryEnabled).assertTrue();
      expect(state.draft.diary).assertEqual('初稿');
    });

    it('rejects valid payload events on the wrong screen', 0, () => {
      const state = initialRecallState();
      const next = transition(state, RecallEvents.setTimeMark('昨天'));
      expect(next === state).assertTrue();
    });

    it('rejects an empty detail entry identifier', 0, () => {
      let state = initialRecallState();
      state = transition(state, RecallEvents.openTimeline());
      const next = transition(state, RecallEvents.openDetail(''));
      expect(next === state).assertTrue();
    });
  });
}
