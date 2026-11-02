import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import {
  type SpeechListener,
  type SpeechPermissionState,
  type SpeechPlatform,
} from './SpeechInput';

/**
 * Production `SpeechPlatform` backed by the HarmonyOS Core Speech Kit
 * (`speechRecognizer`, short offline mode, zh-CN). Microphone access is
 * requested on demand; denial and engine errors surface as normal outcomes
 * so callers can degrade gracefully.
 */
export class HarmonySpeechPlatform implements SpeechPlatform {
  private context: common.UIAbilityContext;
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private finishSession: (() => void) | null = null;
  private timer: number = -1;
  private finishRequested: boolean = false;
  private sequence: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  checkPermission(): SpeechPermissionState {
    // Always go through the request flow: it resolves instantly when the
    // permission was already granted, and shows the dialog otherwise.
    return 'never_asked';
  }

  async requestPermission(): Promise<SpeechPermissionState> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(
        this.context,
        ['ohos.permission.MICROPHONE'],
      );
      if (result.authResults.length > 0 && result.authResults[0] === 0) {
        return 'granted';
      }
      return 'denied';
    } catch (e) {
      return 'denied';
    }
  }

  async start(listener: SpeechListener): Promise<void> {
    if (this.finishSession !== null) {
      listener.onError('语音识别正在进行中。');
      return;
    }
    const sessionId = `milo-${Date.now()}-${++this.sequence}`;
    this.sessionId = sessionId;
    this.finishRequested = false;
    const session: Promise<void> = new Promise<void>((resolve: () => void) => {
      this.finishSession = resolve;
    });
    this.timer = setTimeout(() => {
      if (this.sessionId !== sessionId) return;
      listener.onError('语音识别超时，请重试或使用键盘输入。');
      this.endSession(sessionId);
    }, 35000);
    // Starting can outlive permission/page cancellation. A late engine is
    // discarded by prepareEngine rather than being attached to the next turn.
    void this.prepareEngine(sessionId, listener).catch(() => {
      if (this.sessionId !== sessionId) return;
      listener.onError('语音识别暂不可用，请重试或使用键盘输入。');
      this.endSession(sessionId);
    });
    await session;
  }

  private async prepareEngine(sessionId: string, listener: SpeechListener): Promise<void> {
    const extraParams: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
    const engineParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams: extraParams,
    };
    const engine: speechRecognizer.SpeechRecognitionEngine =
      await speechRecognizer.createEngine(engineParams);
    if (this.sessionId !== sessionId) {
      engine.shutdown();
      return;
    }
    this.engine = engine;

    let latestText: string = '';
    const recognitionListener: speechRecognizer.RecognitionListener = {
      onStart: (_sessionId: string, _eventMessage: string) => {
        if (this.sessionId === sessionId && _sessionId === sessionId) listener.onReady?.();
      },
      onEvent: (_sessionId: string, _eventCode: number, _eventMessage: string) => {},
      onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (this.sessionId !== sessionId || _sessionId !== sessionId) return;
        latestText = result.result;
        // isFinal ends a clause; only isLast (or onComplete) ends the session.
        if (result.isFinal && result.isLast) {
          listener.onFinal(result.result);
          this.endSession(sessionId);
        } else {
          listener.onPartial(result.result);
        }
      },
      onComplete: (_sessionId: string, _eventMessage: string) => {
        if (this.sessionId !== sessionId || _sessionId !== sessionId) return;
        if (latestText.trim().length > 0) listener.onFinal(latestText);
        this.endSession(sessionId);
      },
      onError: (_sessionId: string, _errorCode: number, errorMessage: string) => {
        if (this.sessionId !== sessionId || _sessionId !== sessionId) return;
        // Diagnostic code only: never log recognized speech or account data.
        console.warn(`MILO speech recognition failed: ${_errorCode}`);
        listener.onError(errorMessage);
        this.endSession(sessionId);
      },
    };
    engine.setListener(recognitionListener);

    const audioInfo: speechRecognizer.AudioInfo = {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16,
    };
    const startParams: speechRecognizer.StartParams = {
      sessionId: sessionId,
      audioInfo: audioInfo,
      // Default is 1 (caller-supplied PCM), which never opens the microphone.
      extraParams: { 'recognitionMode': 0, 'vadBegin': 10000, 'vadEnd': 1500, 'maxAudioDuration': 20000 },
    };
    engine.startListening(startParams);
    if (this.sessionId === sessionId && this.finishRequested) engine.finish(sessionId);
  }

  async finish(): Promise<void> {
    this.finishRequested = true;
    if (this.engine !== null && this.sessionId.length > 0) this.engine.finish(this.sessionId);
  }

  async cancel(): Promise<void> {
    this.endSession(this.sessionId);
  }

  async destroy(): Promise<void> {
    await this.cancel();
  }

  private endSession(sessionId: string): void {
    if (this.sessionId !== sessionId || sessionId.length === 0) return;
    this.sessionId = '';
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    const engine = this.engine;
    this.engine = null;
    const finish = this.finishSession;
    this.finishSession = null;
    if (engine !== null) {
      try { engine.cancel(sessionId); } catch (e) { /* Session may already be over. */ }
      try { engine.shutdown(); } catch (e) { /* Best-effort resource release. */ }
    }
    if (finish !== null) finish();
  }
}
