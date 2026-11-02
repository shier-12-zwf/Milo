import { describe, expect, it } from '@ohos/hypium';
import { ConversationController, initialConversationState, conciseReply, type OpenResult, type RespondResult } from '../../../main/ets/features/conversation/ConversationController';
import { FallbackGuide } from '../../../main/ets/features/conversation/FallbackGuide';
import {
  type AiGatewayClient,
  type GatewayResult,
  type GatewaySuccess,
  type GatewayFailure,
  type OpenArg,
  type RespondArg,
  type DiaryArg,
} from '../../../main/ets/core/network/AiGatewayClient';
import { type ChatMessage, type Draft, type MoodId } from '../../../main/ets/core/model/Domain';

class FakeGateway implements AiGatewayClient {
  openReply: GatewayResult = success('AI 写的开场白');
  respondReply: GatewayResult = success('AI 写的回复');
  diaryReply: GatewayResult = success('AI 写的日记');
  openCalls: number = 0;
  respondCalls: number = 0;
  diaryCalls: number = 0;
  throwOnRespond: boolean = false;
  lastRespond: RespondArg | undefined = undefined;

  async open(_request: OpenArg): Promise<GatewayResult> {
    this.openCalls += 1;
    return this.openReply;
  }

  async respond(request: RespondArg): Promise<GatewayResult> {
    this.respondCalls += 1;
    this.lastRespond = request;
    if (this.throwOnRespond) throw new Error('provider failed');
    return this.respondReply;
  }

  async createDiary(_request: DiaryArg): Promise<GatewayResult> {
    this.diaryCalls += 1;
    return this.diaryReply;
  }
}

function success(text: string): GatewaySuccess {
  return { ok: true, text: text, requestId: 'req-success' };
}

function failure(code: 'AI_UNAVAILABLE' | 'RATE_LIMITED' | 'CONTENT_BLOCKED' | 'OFFLINE' | 'INVALID_REQUEST'): GatewayFailure {
  return {
    ok: false,
    error: { code: code, retryable: code !== 'CONTENT_BLOCKED' && code !== 'INVALID_REQUEST', requestId: 'req-fail', message: '' },
  };
}

function draft(timeMark: string): Draft {
  return {
    mood: { valence: 0, labels: ['平静'], emotionId: 'calm' as MoodId },
    kind: 'past',
    timeMark: timeMark,
    transcript: [],
    diaryEnabled: true,
  };
}

function newController(gateway: FakeGateway): ConversationController {
  return new ConversationController({
    gateway: gateway,
    aiAvailable: true,
    newGuide: (d: Draft) => new FallbackGuide(d.timeMark ?? '过去的某一天'),
  });
}

function conversationSuite() {
  describe('conversationControllerTest', () => {
    it('returns the AI greeting when the gateway replies successfully', 0, async () => {
      const controller = newController(new FakeGateway());
      const result: OpenResult = await controller.open(draft('去年夏天'));
      expect(result.usedAi).assertEqual(true);
      expect(result.message.role).assertEqual('ai');
      expect(result.message.text).assertEqual('AI 写的开场白');
      expect(controller.isOnFallback()).assertEqual(false);
    });

    it('falls back to the scripted opening when the gateway is offline', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('OFFLINE');
      const controller = newController(gateway);
      const result = await controller.open(draft('去年夏天'));
      expect(result.usedAi).assertEqual(false);
      expect(result.message.text.indexOf('去年夏天') >= 0).assertTrue();
      expect(controller.isOnFallback()).assertEqual(true);
    });

    it('records the gateway error so the UI can show a short recoverable status', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('RATE_LIMITED');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      const state = controller.getState();
      expect(state.source).assertEqual('script');
      expect(state.lastError !== undefined).assertTrue();
      expect(state.lastError!.code).assertEqual('RATE_LIMITED');
    });

    it('switches to the script after a timeout and never tries AI again', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('AI_UNAVAILABLE');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      const respondResult: RespondResult = await controller.respond(draft('去年夏天'), '那天是雨季', 1);
      expect(respondResult.usedAi).assertEqual(false);
      expect(gateway.respondCalls).assertEqual(0);
      expect(controller.getState().fallbackStep).assertEqual(1);
    });

    it('falls back on content block and surfaces the right error code', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('CONTENT_BLOCKED');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      expect(controller.getState().lastError!.code).assertEqual('CONTENT_BLOCKED');
    });

    it('falls back when the gateway returns an empty body', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = success('');
      const controller = newController(gateway);
      const result = await controller.open(draft('去年夏天'));
      expect(result.usedAi).assertEqual(false);
      expect(controller.isOnFallback()).assertEqual(true);
    });

    it('uses fallbackDiary when AI diary generation fails', 0, async () => {
      const gateway = new FakeGateway();
      gateway.diaryReply = failure('OFFLINE');
      const controller = newController(gateway);
      const draftWithChat: Draft = {
        mood: { valence: 0, labels: ['平静'], emotionId: 'calm' as MoodId },
        kind: 'past',
        timeMark: '去年夏天',
        transcript: [
          { role: 'ai', text: '回到那段时光', ts: 1 },
          { role: 'user', text: '那天是雨季', ts: 2 },
        ],
        diaryEnabled: true,
      };
      const result = await controller.createDiary(draftWithChat);
      expect(result.usedAi).assertEqual(false);
      expect(result.diary).assertEqual('那天是雨季');
    });

    it('preserves the user message even when the AI call fails', 0, async () => {
      const gateway = new FakeGateway();
      gateway.respondReply = failure('AI_UNAVAILABLE');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      const before = draft('去年夏天');
      before.transcript = [{ role: 'ai', text: '回到那段时光', ts: 1 }];
      await controller.respond(before, '那天是雨季', 2);
      const state = controller.getState();
      expect(state.fallbackStep).assertEqual(1);
      expect(controller.isScriptComplete()).assertEqual(false);
    });

    it('restores the fallback step so the guide resumes where it left off', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('OFFLINE');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      await controller.respond(draft('去年夏天'), '回答 1', 1);
      await controller.respond(draft('去年夏天'), '回答 2', 2);
      const savedState = controller.getState();

      const restored = newController(new FakeGateway());
      restored.restoreState(savedState);
      const reply: ChatMessage = (await restored.respond(draft('去年夏天'), '新答案', 99)).message;
      expect(reply.text).assertEqual('现在想起它，心里有什么变化？');
      expect(restored.getState().fallbackStep).assertEqual(3);
    });

    it('marks isScriptComplete after five scripted turns', 0, async () => {
      const gateway = new FakeGateway();
      gateway.openReply = failure('OFFLINE');
      const controller = newController(gateway);
      await controller.open(draft('去年夏天'));
      // 已经推进了 0 步 (opening)
      for (let index = 0; index < 5; index += 1) {
        await controller.respond(draft('去年夏天'), `回答 ${index}`, index + 1);
      }
      expect(controller.isScriptComplete()).assertEqual(true);
    });

    it('preserves context and continues the guide after a later AI failure', 0, async () => {
      const gateway = new FakeGateway();
      const controller = newController(gateway);
      const ongoing = draft('去年夏天');
      const first = await controller.respond(ongoing, '那天是雨季', 1);
      ongoing.transcript = [
        { role: 'user', text: '那天是雨季', ts: 1 }, first.message,
      ];
      gateway.respondReply = failure('OFFLINE');
      const reply = await controller.respond(ongoing, '和朋友去了河边', 3);
      expect(reply.message.text).assertEqual('哪件小事让你记得最清楚？');
      expect(reply.state.fallbackStep).assertEqual(2);
      expect(gateway.lastRespond!.draft.transcript.length).assertEqual(3);
      expect(gateway.lastRespond!.draft.transcript[0].text).assertEqual('那天是雨季');
      expect(gateway.lastRespond!.draft.transcript[2].text).assertEqual('和朋友去了河边');
    });

    it('accepts an explicit pause before calling AI', 0, async () => {
      const gateway = new FakeGateway();
      const controller = newController(gateway);
      const reply = await controller.respond(draft('去年夏天'), '现在不想聊了', 1);
      expect(reply.message.text).assertEqual('好，先停在这里。');
      expect(gateway.respondCalls).assertEqual(0);
    });

    it('uses a complete short AI question instead of displaying a long paragraph', 0, async () => {
      const gateway = new FakeGateway();
      gateway.respondReply = success('听起来那是一段让人难忘的时光。河边有什么让你记得很清楚？你和朋友后来还有联系吗？');
      const controller = newController(gateway);
      const reply = await controller.respond(draft('去年夏天'), '和朋友去了河边', 1);
      expect(reply.usedAi).assertTrue();
      expect(reply.message.text).assertEqual('河边有什么让你记得很清楚？');
      expect(conciseReply('很长的内容'.repeat(20))).assertEqual(undefined);
    });

    it('falls back on oversized replies and thrown provider errors', 0, async () => {
      const gateway = new FakeGateway();
      gateway.respondReply = success('很长的内容'.repeat(20));
      const oversized = await newController(gateway).respond(draft('去年夏天'), '那天是雨季', 1);
      expect(oversized.usedAi).assertEqual(false);
      expect(oversized.message.text.length <= 24).assertTrue();
      gateway.throwOnRespond = true;
      const failed = await newController(gateway).respond(draft('去年夏天'), '那天是雨季', 1);
      expect(failed.usedAi).assertEqual(false);
      expect(failed.message.text).assertEqual('那一刻，你是什么感受？');
    });

    it('saves locally without requesting AI after AI is disabled or unavailable', 0, async () => {
      const gateway = new FakeGateway();
      const controller = newController(gateway);
      controller.restoreState({ source: 'script', fallbackStep: 1, lastError: undefined });
      const local = draft('去年夏天');
      local.transcript = [{ role: 'user', text: '那天是雨季', ts: 1 }];
      const result = await controller.createDiary(local);
      expect(result.usedAi).assertEqual(false);
      expect(result.diary.indexOf('那天是雨季') >= 0).assertTrue();
      expect(gateway.diaryCalls).assertEqual(0);
    });

    it('preserves every user line when a long diary exceeds the gateway context limit', 0, async () => {
      const gateway = new FakeGateway();
      const controller = newController(gateway);
      const longDraft = draft('去年夏天');
      for (let index = 0; index < 17; index += 1) {
        longDraft.transcript.push({ role: 'user', text: `我的第 ${index} 段回忆`, ts: index * 2 });
        longDraft.transcript.push({ role: 'ai', text: '嗯，我在听。', ts: index * 2 + 1 });
      }
      const result = await controller.createDiary(longDraft);
      expect(result.usedAi).assertEqual(false);
      expect(result.diary.indexOf('我的第 0 段回忆') >= 0).assertTrue();
      expect(result.diary.indexOf('我的第 16 段回忆') >= 0).assertTrue();
      expect(gateway.diaryCalls).assertEqual(0);
    });

    it('exposes initialConversationState for first-launch defaults', 0, () => {
      const state = initialConversationState();
      expect(state.source).assertEqual('ai');
      expect(state.fallbackStep).assertEqual(0);
      expect(state.lastError).assertEqual(undefined);
    });
  });
}

export default function conversationControllerTest() {
  conversationSuite();
}
