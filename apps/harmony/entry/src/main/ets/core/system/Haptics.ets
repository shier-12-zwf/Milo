import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Haptic feedback adapter. Mirrors the trigger points used by the web build's
 * `apps/web/src/lib/haptics.ts`: selection changes, important confirmations,
 * and gentle reminders.
 *
 * The production wiring delegates to `@ohos.vibrator`. Tests inject a
 * `HapticPlatform` fake to assert timing without needing device APIs.
 */

export type HapticEvent =
  | 'selection'
  | 'confirmation'
  | 'reminder'
  | 'error';

export interface HapticPlatform {
  vibrate(event: HapticEvent): void;
}

export class Haptics {
  private platform: HapticPlatform;
  private enabled: boolean = true;

  constructor(platform?: HapticPlatform) {
    this.platform = platform ?? defaultHapticPlatform();
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  selection(): void {
    if (!this.enabled) return;
    this.platform.vibrate('selection');
  }

  confirmation(): void {
    if (!this.enabled) return;
    this.platform.vibrate('confirmation');
  }

  reminder(): void {
    if (!this.enabled) return;
    this.platform.vibrate('reminder');
  }

  error(): void {
    if (!this.enabled) return;
    this.platform.vibrate('error');
  }
}

function defaultHapticPlatform(): HapticPlatform {
  return new VibratorHapticPlatform();
}

function durationForEvent(event: HapticEvent): number {
  switch (event) {
    case 'confirmation':
      return 10;
    case 'reminder':
      return 24;
    case 'error':
      return 32;
    default:
      return 8;
  }
}

/**
 * Real device platform. Durations mirror the web build's `navigator.vibrate`
 * patterns (8ms selection ticks, 10ms confirm taps). Devices without a motor
 * (e.g. emulators) reject the call; that failure is expected and ignored.
 */
class VibratorHapticPlatform implements HapticPlatform {
  vibrate(event: HapticEvent): void {
    const effect: vibrator.VibrateTime = {
      type: 'time',
      duration: durationForEvent(event),
    };
    const attribute: vibrator.VibrateAttribute = {
      id: 0,
      usage: 'touch',
    };
    vibrator.startVibration(effect, attribute).catch((_error: BusinessError) => {
      // No vibrator hardware on this device; haptics degrade silently.
    });
  }
}