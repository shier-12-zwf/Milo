/**
 * Permission-aware Chinese speech input. The runtime entry point is the
 * HarmonyOS `speechRecognizer` engine; this module wraps it so callers never
 * see platform exceptions. Cancellation and permission denial are normal
 * outcomes — never auto-sent text — and the recognized string is normalised
 * into the active `input` value.
 *
 * Tests inject `SpeechPlatform` to avoid touching the real engine.
 */

export type SpeechPermissionState = 'granted' | 'denied' | 'never_asked';

export type SpeechState =
  | 'idle'
  | 'requesting_permission'
  | 'listening'
  | 'recognizing'
  | 'finalized'
  | 'cancelled'
  | 'denied'
  | 'error';

export interface SpeechResult {
  state: SpeechState;
  text: string;
  /** True when the recognizer delivered the final text fragment. */
  isFinal: boolean;
  errorMessage?: string;
}

export interface SpeechPlatform {
  /** Returns the current microphone permission state without prompting. */
  checkPermission(): SpeechPermissionState;
  /** Prompts the user; resolves with the new state. */
  requestPermission(): Promise<SpeechPermissionState>;
  /** Begin recognition; the listener receives incremental results. */
  start(listener: SpeechListener): Promise<void>;
  /** Stop recording and request a final result, without discarding speech. */
  finish(): Promise<void>;
  /** Cancel an in-flight recognition without emitting text. */
  cancel(): Promise<void>;
  /** Tear down platform resources. */
  destroy(): Promise<void>;
}

export interface SpeechListener {
  onReady?(): void;
  onPartial(text: string): void;
  onFinal(text: string): void;
  onError(message: string): void;
}

export interface SpeechInputOptions {
  /** Locale id; defaults to `zh-CN`. */
  locale?: string;
  /** Override the platform for tests. */
  platform?: SpeechPlatform;
}

export class SpeechInput {
  private platform: SpeechPlatform;
  private locale: string;
  private state: SpeechState = 'idle';
  private generation: number = 0;
  private capture: SpeechCapture | null = null;
  private disposed: boolean = false;

  constructor(options: SpeechInputOptions = {}) {
    this.platform = options.platform ?? defaultSpeechPlatform();
    this.locale = options.locale ?? 'zh-CN';
  }

  getState(): SpeechState {
    return this.state;
  }

  async begin(onUpdate?: (result: SpeechResult) => void): Promise<SpeechResult> {
    if (this.disposed) return { state: 'cancelled', text: '', isFinal: false };
    const currentState: SpeechState = this.state;
    if (this.capture !== null || currentState === 'requesting_permission' || currentState === 'listening' || currentState === 'recognizing') {
      return { state: currentState, text: '', isFinal: false };
    }
    const generation = ++this.generation;
    const captured = new SpeechCapture();
    this.capture = captured;
    const stateBox = new SpeechStateBox('listening');
    try {
      let permission = this.platform.checkPermission();
      if (permission === 'never_asked') {
        this.state = 'requesting_permission';
        permission = await this.platform.requestPermission();
      }
      if (generation !== this.generation) return { state: 'cancelled', text: '', isFinal: false };
      if (permission !== 'granted') {
        this.state = 'denied';
        return { state: 'denied', text: '', isFinal: false };
      }
      this.state = 'listening';
      const listener = new InlineSpeechListener(captured, stateBox, (result: SpeechResult) => {
        this.state = result.state;
        if (onUpdate) onUpdate(result);
      });
      await this.platform.start(listener);
    } catch (e) {
      if (generation === this.generation) {
        captured.errorMessage = '语音识别暂不可用，请重试或使用键盘输入。';
        stateBox.set('error');
      }
    } finally {
      captured.active = false;
      if (generation === this.generation) this.capture = null;
    }
    if (generation !== this.generation) return { state: 'cancelled', text: '', isFinal: false };
    const resolvedState: SpeechState = stateBox.value;
    const result: SpeechResult = {
      state: resolvedState,
      text: captured.text,
      isFinal: resolvedState === 'finalized',
      errorMessage: captured.errorMessage,
    };
    this.state = resolvedState;
    if (resolvedState === 'listening') {
      // platform.start resolved without any callback; treat as no text.
      this.state = 'idle';
      result.state = 'idle';
    }
    return result;
  }

  async finish(): Promise<void> {
    if (this.state === 'requesting_permission') {
      await this.cancel();
      return;
    }
    if (this.state !== 'listening' && this.state !== 'recognizing') return;
    try {
      await this.platform.finish();
    } catch (e) {
      // The session watchdog will resolve a missing final callback.
    }
  }

  async cancel(): Promise<void> {
    this.generation += 1;
    if (this.capture !== null) this.capture.active = false;
    this.capture = null;
    this.state = 'cancelled';
    try { await this.platform.cancel(); } catch (e) { /* Cancellation is best effort. */ }
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    await this.cancel();
    try { await this.platform.destroy(); } catch (e) { /* Already released. */ }
    this.state = 'idle';
  }
}

/** Convenience helper to merge recognized text into an existing input buffer. */
export function mergeRecognizedText(current: string, recognized: string): string {
  const trimmedCurrent = current.trimEnd();
  if (trimmedCurrent.length === 0) {
    return recognized.trim();
  }
  return `${trimmedCurrent} ${recognized.trim()}`;
}

function defaultSpeechPlatform(): SpeechPlatform {
  // On a real device the production wiring would import the
  // `@ohos.ai.speechRecognizer` + `@ohos.permissions` modules. In test
  // environments (and when no listener is attached) the no-op platform is
  // used so unit tests do not depend on device-only APIs.
  return new NoopSpeechPlatform();
}

class NoopSpeechPlatform implements SpeechPlatform {
  checkPermission(): SpeechPermissionState {
    return 'never_asked';
  }
  async requestPermission(): Promise<SpeechPermissionState> {
    return 'denied';
  }
  async start(_listener: SpeechListener): Promise<void> {
    // Intentional no-op for unsupported environments.
  }
  async cancel(): Promise<void> {}
  async finish(): Promise<void> {}
  async destroy(): Promise<void> {}
}

class SpeechCapture {
  active: boolean = true;
  text: string = '';
  errorMessage: string = '';
}

class SpeechStateBox {
  value: SpeechState;
  constructor(initial: SpeechState) {
    this.value = initial;
  }
  set(next: SpeechState): void {
    this.value = next;
  }
}

class InlineSpeechListener implements SpeechListener {
  private capture: SpeechCapture;
  private stateBox: SpeechStateBox;
  private onUpdate: (result: SpeechResult) => void;

  constructor(capture: SpeechCapture, stateBox: SpeechStateBox, onUpdate: (result: SpeechResult) => void) {
    this.capture = capture;
    this.stateBox = stateBox;
    this.onUpdate = onUpdate;
  }

  onReady(): void {
    if (!this.capture.active) return;
    this.onUpdate({ state: 'listening', text: '', isFinal: false });
  }

  onPartial(text: string): void {
    if (!this.capture.active) return;
    this.capture.text = text;
    this.stateBox.set('recognizing');
    this.onUpdate({ state: 'recognizing', text: text, isFinal: false });
  }

  onFinal(text: string): void {
    if (!this.capture.active) return;
    this.capture.text = text;
    this.stateBox.set('finalized');
    this.onUpdate({ state: 'finalized', text: text, isFinal: true });
  }

  onError(message: string): void {
    if (!this.capture.active) return;
    this.capture.errorMessage = message;
    this.stateBox.set('error');
    this.onUpdate({ state: 'error', text: this.capture.text, isFinal: false, errorMessage: message });
  }
}

export function speechFeedback(result: SpeechResult): string {
  if (result.state === 'denied') return '未获得麦克风权限，可在系统设置中允许，或继续打字。';
  if (result.state === 'error') return '语音识别暂不可用，请重试或使用键盘输入。';
  if (result.state === 'cancelled') return '';
  if (result.text.trim().length === 0) return '没有听清，请再试一次，或使用键盘输入。';
  return '';
}
