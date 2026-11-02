import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { completionUrl } from '../config/UserAiSettings';

interface BoundApiKey { endpoint: string; apiKey: string; }

/** Keys are device-only system assets, never diary preferences or export data. */
export class ApiKeyStore {
  private alias: Uint8Array;
  constructor(uid: string) {
    this.alias = new util.TextEncoder().encodeInto(`milo.api-key.${uid}`);
  }
  read(baseUrl: string): string {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = asset.querySync(query);
      if (rows.length === 0) return '';
      const raw = util.TextDecoder.create('utf-8').decodeWithStream(rows[0].get(asset.Tag.SECRET) as Uint8Array);
      const saved = JSON.parse(raw) as BoundApiKey;
      return saved.endpoint === completionUrl(baseUrl) && typeof saved.apiKey === 'string' ? saved.apiKey : '';
    } catch (e) {
      if ((e as BusinessError).code === asset.ErrorCode.NOT_FOUND) return '';
      throw new Error('设备安全存储暂不可用，请解锁设备后重试。');
    }
  }
  save(key: string, baseUrl: string): void {
    if (key.length === 0) { this.clear(); return; }
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.alias);
    const payload: BoundApiKey = { endpoint: completionUrl(baseUrl), apiKey: key };
    if (!payload.endpoint) throw new Error('Key 必须绑定有效的 HTTPS 模型地址。');
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(JSON.stringify(payload)));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.addSync(attributes);
  }
  clear(): void {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias);
    try { asset.removeSync(query); } catch (e) {
      if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw new Error('无法删除安全存储中的 Key。');
    }
  }
}
