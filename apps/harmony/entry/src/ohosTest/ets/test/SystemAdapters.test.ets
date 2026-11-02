import { describe, expect, it } from '@ohos/hypium';
import {
  SpeechInput,
  mergeRecognizedText,
  type SpeechPlatform,
  type SpeechPermissionState,
  type SpeechListener,
  speechFeedback,
} from '../../../main/ets/core/system/SpeechInput';
import { Haptics, type HapticEvent, type HapticPlatform } from '../../../main/ets/core/system/Haptics';
import {
  ShareService,
  type SharePlatform,
  type ShareResultCode,
} from '../../../main/ets/core/system/ShareService';

class FakeSpeechPlatform implements SpeechPlatform {
  permission: SpeechPermissionState = 'never_asked';
  started: number = 0;
  cancelled: number = 0;
  destroyed: number = 0;
  startHandler: ((listener: SpeechListener) => Promise<void>) | null = null;
  cancelHandler: (() => Promise<void>) | null = null;
  permissionHandler: (() => Promise<SpeechPermissionState>) | null = null;

  checkPermission(): SpeechPermissionState {
    return this.permission;
  }

  async requestPermission(): Promise<SpeechPermissionState> {
    if (this.permissionHandler !== null) return await this.permissionHandler();
    return this.permission;
  }

  async start(listener: SpeechListener): Promise<void> {
    this.started += 1;
    if (this.startHandler !== null) {
      await this.startHandler(listener);
    }
  }

  async cancel(): Promise<void> {
    this.cancelled += 1;
    if (this.cancelHandler !== null) {
      await this.cancelHandler();
    }
  }

  async finish(): Promise<void> {}

  async destroy(): Promise<void> {
    this.destroyed += 1;
  }
}

class FakeHapticPlatform implements HapticPlatform {
  events: HapticEvent[] = [];
  vibrate(event: HapticEvent): void {
    this.events.push(event);
  }
}

class FakeSharePlatform implements SharePlatform {
  savedPaths: string[] = [];
  sharedPaths: string[] = [];
  cleanedPaths: string[] = [];
  shareResult: ShareResultCode = 'success';
  saveHandler: ((fileName: string, bytes: ArrayBuffer) => Promise<string>) | null = null;

  async saveTempFile(fileName: string, bytes: ArrayBuffer): Promise<string> {
    if (this.saveHandler !== null) {
      return await this.saveHandler(fileName, bytes);
    }
    const path = `/tmp/${fileName}`;
    this.savedPaths.push(path);
    return path;
  }

  async share(filePath: string): Promise<ShareResultCode> {
    this.sharedPaths.push(filePath);
    return this.shareResult;
  }

  async cleanup(filePath: string): Promise<void> {
    this.cleanedPaths.push(filePath);
  }
}

function systemSuite() {
  describe('systemAdaptersTest', () => {
    describe('SpeechInput', () => {
      it('requests permission only on first use and treats denial as normal outcome', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'never_asked';
        const speech = new SpeechInput({ platform });
        const result = await speech.begin();
        expect(result.state).assertEqual('denied');
        expect(speech.getState()).assertEqual('denied');
      });

      it('delivers partial and final text without auto-sending', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        platform.startHandler = async (listener) => {
          listener.onPartial('今天');
          listener.onPartial('今天下雨');
          listener.onFinal('今天下雨了');
        };
        const speech = new SpeechInput({ platform });
        const result = await speech.begin();
        expect(result.text).assertEqual('今天下雨了');
        expect(result.isFinal).assertEqual(true);
      });

      it('cancellation never emits a final result', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        platform.startHandler = async () => {
          // hold open
        };
        const speech = new SpeechInput({ platform });
        const beginPromise = speech.begin();
        // give microtasks a chance to start
        await Promise.resolve();
        await speech.cancel();
        const result = await beginPromise;
        expect(result.state === 'cancelled' || result.state === 'idle').assertTrue();
        expect(result.text).assertEqual('');
        expect(platform.cancelled >= 1).assertTrue();
      });

      it('granted permission skips the prompt', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        platform.startHandler = async () => {};
        const speech = new SpeechInput({ platform });
        await speech.begin();
        expect(speech.getState()).assertEqual('idle');
      });

      it('cancel during the permission prompt never starts recording afterward', 0, async () => {
        const platform = new FakeSpeechPlatform();
        let grant: ((state: SpeechPermissionState) => void) = () => {};
        platform.permissionHandler = () => new Promise<SpeechPermissionState>((resolve) => { grant = resolve; });
        const speech = new SpeechInput({ platform });
        const pending = speech.begin();
        await speech.cancel();
        grant('granted');
        const result = await pending;
        expect(platform.started).assertEqual(0);
        expect(result.state).assertEqual('cancelled');
      });

      it('engine exceptions become a visible retryable error and allow another attempt', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        platform.startHandler = async () => { throw new Error('synthetic engine failure'); };
        const speech = new SpeechInput({ platform });
        const failed = await speech.begin();
        expect(failed.state).assertEqual('error');
        expect(speechFeedback(failed).length > 0).assertTrue();
        platform.startHandler = async (listener) => { listener.onFinal('再次记录'); };
        const retried = await speech.begin();
        expect(retried.text).assertEqual('再次记录');
      });

      it('late callbacks after disposal cannot overwrite input or reopen recording', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        let callback: SpeechListener | null = null;
        let complete: (() => void) = () => {};
        platform.startHandler = (listener) => {
          callback = listener;
          return new Promise<void>((resolve) => { complete = resolve; });
        };
        const updates: string[] = [];
        const speech = new SpeechInput({ platform });
        const pending = speech.begin((result) => { updates.push(result.text); });
        await speech.dispose();
        if (callback !== null) (callback as SpeechListener).onFinal('过期识别');
        complete();
        expect((await pending).state).assertEqual('cancelled');
        expect(updates.length).assertEqual(0);
        expect((await speech.begin()).state).assertEqual('cancelled');
        expect(platform.started).assertEqual(1);
      });

      it('streams text to the input and explains denied permission and empty speech', 0, async () => {
        const platform = new FakeSpeechPlatform();
        platform.permission = 'granted';
        platform.startHandler = async (listener) => {
          listener.onPartial('今天');
          listener.onFinal('今天的回忆');
        };
        const updates: string[] = [];
        const speech = new SpeechInput({ platform });
        const result = await speech.begin((update) => { updates.push(update.text); });
        expect(updates.length).assertEqual(2);
        expect(result.isFinal).assertTrue();
        expect(speechFeedback({ state: 'denied', text: '', isFinal: false }).includes('麦克风权限')).assertTrue();
        expect(speechFeedback({ state: 'idle', text: '', isFinal: false }).includes('没有听清')).assertTrue();
      });

      it('mergeRecognizedText joins on a single space and trims edges', 0, () => {
        expect(mergeRecognizedText('', '你好')).assertEqual('你好');
        expect(mergeRecognizedText('今天', '下雨了')).assertEqual('今天 下雨了');
        expect(mergeRecognizedText('   ', '下雨')).assertEqual('下雨');
      });
    });

    describe('Haptics', () => {
      it('fires selection on selection()', 0, () => {
        const platform = new FakeHapticPlatform();
        const haptics = new Haptics(platform);
        haptics.selection();
        expect(platform.events.length).assertEqual(1);
        expect(platform.events[0]).assertEqual('selection');
      });

      it('fires confirmation and reminder for the matching calls', 0, () => {
        const platform = new FakeHapticPlatform();
        const haptics = new Haptics(platform);
        haptics.confirmation();
        haptics.reminder();
        haptics.error();
        expect(platform.events.length).assertEqual(3);
        expect(platform.events[0]).assertEqual('confirmation');
        expect(platform.events[1]).assertEqual('reminder');
        expect(platform.events[2]).assertEqual('error');
      });

      it('does not vibrate when disabled', 0, () => {
        const platform = new FakeHapticPlatform();
        const haptics = new Haptics(platform);
        haptics.setEnabled(false);
        haptics.selection();
        haptics.confirmation();
        expect(platform.events.length).assertEqual(0);
      });
    });

    describe('ShareService', () => {
      it('preview saves to a temp path without opening the share sheet', 0, async () => {
        const platform = new FakeSharePlatform();
        const service = new ShareService({ platform });
        const result = await service.preview('card.png', new ArrayBuffer(8));
        expect(result.code).assertEqual('success');
        expect(platform.sharedPaths.length).assertEqual(0);
        expect(platform.savedPaths.length).assertEqual(1);
      });

      it('shareLast opens the share sheet and cleans the temp file', 0, async () => {
        const platform = new FakeSharePlatform();
        const service = new ShareService({ platform });
        await service.preview('card.png', new ArrayBuffer(8));
        const result = await service.shareLast();
        expect(result.code).assertEqual('success');
        expect(platform.sharedPaths.length).assertEqual(1);
        expect(platform.cleanedPaths.length).assertEqual(1);
        expect(service.getLastSharedPath() === undefined).assertTrue();
      });

      it('a failed share reports failure and still cleans up', 0, async () => {
        const platform = new FakeSharePlatform();
        platform.shareResult = 'failed';
        const service = new ShareService({ platform });
        await service.preview('card.png', new ArrayBuffer(8));
        const result = await service.shareLast();
        expect(result.code).assertEqual('failed');
        expect(platform.cleanedPaths.length).assertEqual(1);
      });

      it('cancellation is reported without error', 0, async () => {
        const platform = new FakeSharePlatform();
        platform.shareResult = 'cancelled';
        const service = new ShareService({ platform });
        await service.preview('card.png', new ArrayBuffer(8));
        const result = await service.shareLast();
        expect(result.code).assertEqual('cancelled');
        expect(platform.cleanedPaths.length).assertEqual(1);
      });

      it('preview failure does not block later retry', 0, async () => {
        const platform = new FakeSharePlatform();
        platform.saveHandler = async () => {
          throw new Error('disk full');
        };
        const service = new ShareService({ platform });
        const first = await service.preview('card.png', new ArrayBuffer(8));
        expect(first.code).assertEqual('failed');
        expect(platform.savedPaths.length).assertEqual(0);

        platform.saveHandler = null;
        const second = await service.preview('card.png', new ArrayBuffer(8));
        expect(second.code).assertEqual('success');
      });

      it('emits a single onAfterShare callback per share', 0, async () => {
        const platform = new FakeSharePlatform();
        const calls: number[] = [];
        const service = new ShareService({
          platform,
          onAfterShare: (result) => calls.push(result.code === 'success' ? 1 : 0),
        });
        await service.preview('card.png', new ArrayBuffer(8));
        await service.shareLast();
        expect(calls.length).assertEqual(1);
        expect(calls[0]).assertEqual(1);
      });
    });
  });
}

export default function systemAdaptersTest() {
  systemSuite();
}
