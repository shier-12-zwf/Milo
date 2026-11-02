/**
 * System share adapter. Saves a `PixelMap` (or raw bytes) to an app-owned
 * temporary file and invokes the system share sheet. The temp file is cleaned
 * up automatically after the share completes (success or failure), but never
 * rolled back if the diary itself was already saved.
 *
 * The production wiring uses `image.Packer` + `@ohos.app.ability.UIAbility`
 * context. Tests inject a `SharePlatform` fake.
 */

export type ShareResultCode =
  | 'success'
  | 'cancelled'
  | 'failed'
  | 'permission_denied';

export interface ShareResult {
  code: ShareResultCode;
  message: string;
  /** Path the platform wrote the file to, or undefined if no file was saved. */
  filePath?: string;
}

export interface SharePlatform {
  /** Save the rendered card to an app-owned temp file and return the path. */
  saveTempFile(fileName: string, bytes: ArrayBuffer): Promise<string>;
  /** Open the system share sheet pointed at the file. */
  share(filePath: string): Promise<ShareResultCode>;
  /** Remove the temp file; safe to call multiple times. */
  cleanup(filePath: string): Promise<void>;
}

export interface ShareServiceOptions {
  platform?: SharePlatform;
  /** Optional callback after every share (success, cancel, failure). */
  onAfterShare?: (result: ShareResult) => void;
}

export class ShareService {
  private platform: SharePlatform;
  private onAfterShare: ((result: ShareResult) => void) | undefined;
  private lastSharedPath: string | undefined;

  constructor(options: ShareServiceOptions = {}) {
    this.platform = options.platform ?? defaultSharePlatform();
    this.onAfterShare = options.onAfterShare;
  }

  getLastSharedPath(): string | undefined {
    return this.lastSharedPath;
  }

  /**
   * Preview-first flow: save the rendered card, return the local path so the
   * UI can render a preview. The actual share sheet only opens via
   * {@link shareLast} on explicit user tap.
   */
  async preview(fileName: string, bytes: ArrayBuffer): Promise<ShareResult> {
    try {
      const filePath = await this.platform.saveTempFile(fileName, bytes);
      this.lastSharedPath = filePath;
      return { code: 'success', message: 'preview ready', filePath: filePath };
    } catch (error) {
      return this.fail('failed', `preview failed: ${errorMessage(error)}`);
    }
  }

  /** Open the share sheet for the previously saved preview. */
  async shareLast(): Promise<ShareResult> {
    if (this.lastSharedPath === undefined) {
      return this.fail('failed', 'no preview available');
    }
    let result: ShareResult;
    try {
      const code = await this.platform.share(this.lastSharedPath);
      result = {
        code: code,
        message: codeMessage(code),
        filePath: this.lastSharedPath,
      };
    } catch (error) {
      result = this.fail('failed', `share failed: ${errorMessage(error)}`);
    }
    await this.cleanup();
    this.notify(result);
    return result;
  }

  /** Discard the preview file without sharing. */
  async discard(): Promise<void> {
    await this.cleanup();
  }

  private async cleanup(): Promise<void> {
    if (this.lastSharedPath !== undefined) {
      try {
        await this.platform.cleanup(this.lastSharedPath);
      } catch {
        // best-effort cleanup; share errors must not cascade
      }
      this.lastSharedPath = undefined;
    }
  }

  private fail(code: ShareResultCode, message: string): ShareResult {
    return { code: code, message: message };
  }

  private notify(result: ShareResult): void {
    if (this.onAfterShare !== undefined) {
      this.onAfterShare(result);
    }
  }
}

function codeMessage(code: ShareResultCode): string {
  switch (code) {
    case 'success': return '已分享。';
    case 'cancelled': return '已取消。';
    case 'failed': return '分享失败，请重试。';
    case 'permission_denied': return '系统拒绝了分享请求。';
    default: return '未知状态。';
  }
}

function errorMessage(error: Object | string | undefined): string {
  if (typeof error === 'string') return error;
  if (error === undefined) return 'unknown';
  return 'unknown';
}

function defaultSharePlatform(): SharePlatform {
  // Device-bound implementation lives outside the unit-test scope. The unit
  // suite injects an explicit fake so it can assert cleanup behaviour.
  return new NoopSharePlatform();
}

class NoopSharePlatform implements SharePlatform {
  async saveTempFile(_fileName: string, _bytes: ArrayBuffer): Promise<string> {
    throw new Error('no platform');
  }
  async share(_filePath: string): Promise<ShareResultCode> {
    return 'failed';
  }
  async cleanup(_filePath: string): Promise<void> {}
}