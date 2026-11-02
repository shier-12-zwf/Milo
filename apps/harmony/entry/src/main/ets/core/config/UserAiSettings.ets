import { KVStorage } from '../data/KVStorage';

export interface ModelPreset {
  id: string;
  label: string;
  baseUrl: string;
  model: string;
}

export const MODEL_PRESETS: ModelPreset[] = [
  { id: 'deepseek', label: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  { id: 'qwen', label: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus' },
  { id: 'kimi', label: 'Kimi', baseUrl: 'https://api.moonshot.cn/v1', model: 'kimi-k2.6' },
  { id: 'minimax', label: 'MiniMax', baseUrl: 'https://api.minimaxi.com/v1', model: 'MiniMax-M2.5' },
  { id: 'custom', label: '自定义（OpenAI 兼容）', baseUrl: '', model: '' },
];

export interface UserAiSettings {
  enabled: boolean;
  source: string;
  provider: string;
  baseUrl: string;
  model: string;
  consent: boolean;
}

export function defaultAiSettings(): UserAiSettings {
  return { enabled: true, source: 'milo', provider: 'deepseek', baseUrl: MODEL_PRESETS[0].baseUrl,
    model: MODEL_PRESETS[0].model, consent: false };
}

/** Accept a base URL or a complete chat-completions URL, without secret URL parameters. */
export function completionUrl(value: string): string {
  const base = value.trim().replace(/\/+$/, '');
  if (!/^https:\/\/[a-zA-Z0-9.-]+(?::\d+)?(?:\/[a-zA-Z0-9._~%/-]*)?$/.test(base)) return '';
  return base.endsWith('/chat/completions') ? base : `${base}/chat/completions`;
}

export class UserAiSettingsRepository {
  private key: string;
  private storage: KVStorage;
  constructor(storage: KVStorage, uid: string) { this.storage = storage; this.key = `milo.ai.settings.${uid}`; }
  load(): UserAiSettings {
    try {
      const value = JSON.parse(this.storage.read(this.key) ?? '{}') as UserAiSettings;
      if (typeof value.enabled !== 'boolean' || typeof value.baseUrl !== 'string'
        || typeof value.model !== 'string' || typeof value.provider !== 'string'
        || (value.source !== 'personal' && value.source !== 'milo')) return defaultAiSettings();
      return { enabled: value.enabled, source: value.source, provider: value.provider,
        baseUrl: value.baseUrl, model: value.model, consent: value.consent === true };
    } catch { return defaultAiSettings(); }
  }
  save(value: UserAiSettings): void { this.storage.write(this.key, JSON.stringify(value)); }
  clear(): void { this.storage.remove(this.key); }
}
