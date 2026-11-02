import { describe, expect, it } from '@ohos/hypium';
import { AI_AVAILABLE, effectiveAiEnabled } from '../../../main/ets/core/config/FeatureFlags';
import { defaultAiSettings, UserAiSettingsRepository } from '../../../main/ets/core/config/UserAiSettings';
import { MapKVStorage } from '../../../main/ets/core/data/KVStorage';
import { RecallSessionRepository, DRAFT_STORAGE_KEY } from '../../../main/ets/core/data/RecallSessionRepository';
import { initialRecallState } from '../../../main/ets/core/flow/RecallMachine';
import { Screen } from '../../../main/ets/core/model/Domain';
import { AiGatewayClient, GatewayResult, OpenArg, RespondArg, DiaryArg } from '../../../main/ets/core/network/AiGatewayClient';
import { ConversationController } from '../../../main/ets/features/conversation/ConversationController';
import { FallbackGuide } from '../../../main/ets/features/conversation/FallbackGuide';

class CountingGateway implements AiGatewayClient {
  calls: number = 0;
  async open(_request: OpenArg): Promise<GatewayResult> {
    this.calls += 1;
    return { ok: true, text: 'Unexpected remote opening', requestId: 'test' };
  }
  async respond(_request: RespondArg): Promise<GatewayResult> {
    this.calls += 1;
    return { ok: true, text: 'Unexpected remote reply', requestId: 'test' };
  }
  async createDiary(_request: DiaryArg): Promise<GatewayResult> {
    this.calls += 1;
    return { ok: true, text: 'Unexpected remote diary', requestId: 'test' };
  }
}

async function checkRestoredSettings(source: string): Promise<void> {
  const storage = new MapKVStorage();
  const settingsRepo = new UserAiSettingsRepository(storage, 'existing-user');
  const settings = defaultAiSettings();
  settings.source = source;
  settings.enabled = true;
  settings.consent = true;
  settings.provider = 'minimax';
  settings.baseUrl = 'https://api.minimaxi.com/v1';
  settings.model = 'saved-user-model';
  settingsRepo.save(settings);
  const settingsBefore = storage.read('milo.ai.settings.existing-user');
  const draftRepo = new RecallSessionRepository(storage);
  const state = initialRecallState();
  state.screen = Screen.chat();
  state.draft.kind = 'past';
  state.draft.timeMark = '昨天';
  state.draft.aiEnabled = true;
  state.draft.inputText = '未完成的输入';
  draftRepo.saveDraft(state);
  const draftBefore = storage.read(DRAFT_STORAGE_KEY);
  const restored = draftRepo.loadDraft()!;
  const gateway = new CountingGateway();
  const controller = new ConversationController({
    gateway: gateway,
    newGuide: () => new FallbackGuide('昨天'),
  });
  controller.restoreState({ source: 'ai', fallbackStep: 0,
    lastError: { code: 'AI_UNAVAILABLE', message: '旧的网络错误', retryable: true, requestId: 'old' } });
  const opened = await controller.open(restored.draft);
  const replied = await controller.respond(restored.draft, '测试中散步看见花开', 1);
  restored.draft.transcript = [{ role: 'user', text: '测试中散步看见花开', ts: 1 }];
  const diary = await controller.createDiary(restored.draft);
  expect(opened.usedAi).assertFalse();
  expect(replied.usedAi).assertFalse();
  expect(diary.usedAi).assertFalse();
  expect(diary.diary).assertEqual('测试中散步看见花开');
  expect(gateway.calls).assertEqual(0);
  expect(controller.getState().source).assertEqual('script');
  expect(controller.getState().lastError).assertEqual(undefined);
  expect(effectiveAiEnabled(settingsRepo.load().enabled)).assertFalse();
  expect(storage.read('milo.ai.settings.existing-user')).assertEqual(settingsBefore);
  expect(storage.read(DRAFT_STORAGE_KEY)).assertEqual(draftBefore);
  expect(restored.draft.aiEnabled).assertTrue();
  expect(restored.draft.inputText).assertEqual('未完成的输入');
}

export default function aiAvailabilityTest() {
  describe('aiAvailabilityTest', () => {
    it('temporarily disables AI regardless of the saved toggle', 0, () => {
      expect(AI_AVAILABLE).assertFalse();
      expect(effectiveAiEnabled(true)).assertFalse();
      expect(effectiveAiEnabled(false)).assertFalse();
    });
    it('restores an enabled hosted-model account without requests or settings loss', 0, async () => {
      await checkRestoredSettings('milo');
    });
    it('restores an enabled personal-model account without requests or settings loss', 0, async () => {
      await checkRestoredSettings('personal');
    });
    it('keeps a restored diary screen local even before a chat opening', 0, async () => {
      const gateway = new CountingGateway();
      const controller = new ConversationController({ gateway: gateway, newGuide: () => new FallbackGuide('昨天') });
      controller.restoreState({ source: 'ai', fallbackStep: 2, lastError: undefined });
      const state = initialRecallState();
      state.screen = Screen.diary();
      state.draft.aiEnabled = true;
      state.draft.transcript = [{ role: 'user', text: '第二段测试回忆', ts: 1 }];
      const diary = await controller.createDiary(state.draft);
      expect(diary.diary).assertEqual('第二段测试回忆');
      expect(diary.usedAi).assertFalse();
      expect(gateway.calls).assertEqual(0);
      expect(diary.state.lastError).assertEqual(undefined);
    });
  });
}
