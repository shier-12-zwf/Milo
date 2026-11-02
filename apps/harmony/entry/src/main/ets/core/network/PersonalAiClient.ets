import { AiGatewayClient, OpenRequestBody, RespondRequestBody, DiaryRequestBody, GatewayResult,
  DraftSummary, FetchLike, FetchInit, CancelSignalImpl, RequestOptions } from './AiGatewayClient';
import { UserAiSettings, completionUrl } from '../config/UserAiSettings';

interface ModelMessage { role: string; content: string; }
interface ThinkingOptions { type: string; }
interface CompletionBody { model: string; messages: ModelMessage[]; stream: boolean; thinking?: ThinkingOptions; }
interface CompletionMessage { content?: string; }
interface CompletionChoice { message?: CompletionMessage; }
interface CompletionResponse { choices?: CompletionChoice[]; }

export function aiFailure(message: string): GatewayResult {
  return { ok: false, error: { code: 'AI_UNAVAILABLE', retryable: true, requestId: '', message: message } };
}

export class UnavailableAiClient implements AiGatewayClient {
  private message: string;
  constructor(message: string) { this.message = message; }
  async open(_request: OpenRequestBody): Promise<GatewayResult> { return aiFailure(this.message); }
  async respond(_request: RespondRequestBody): Promise<GatewayResult> { return aiFailure(this.message); }
  async createDiary(_request: DiaryRequestBody): Promise<GatewayResult> { return aiFailure(this.message); }
}

/** Direct-to-provider adapter. Only current conversation context leaves the device. */
export class PersonalAiClient implements AiGatewayClient {
  private settings: UserAiSettings;
  private key: string;
  private fetcher: FetchLike;
  private timeoutMs: number;
  constructor(settings: UserAiSettings, key: string, fetcher: FetchLike, timeoutMs: number = 30000) {
    this.settings = settings;
    this.key = key;
    this.fetcher = fetcher;
    this.timeoutMs = timeoutMs;
  }

  async testConnection(): Promise<GatewayResult> {
    return this.complete([{ role: 'user', content: '这是连接测试，请只回复“连接成功”。' }]);
  }
  async open(request: OpenRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    return this.complete(this.messages(request.draft, '用一句温柔的中文问候开启回忆，问一个具体的小问题。'), options);
  }
  async respond(request: RespondRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    const messages = this.messages(request.draft, '简短回应用户刚才的话，再问一个具体的小问题。不要重复问题。');
    const last = request.draft.transcript[request.draft.transcript.length - 1];
    if (last === undefined || last.role !== 'user' || last.text !== request.userText) {
      messages.push({ role: 'user', content: request.userText });
    }
    return this.complete(messages, options);
  }
  async createDiary(request: DiaryRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    return this.complete(this.messages(request.draft,
      '将用户真实说过的内容整理成第一人称中文日记，200至500字。不虚构事实，不写标题，只输出正文。'), options);
  }
  private messages(draft: DraftSummary, instruction: string): ModelMessage[] {
    const out: ModelMessage[] = [{ role: 'system', content:
      `你是 MILO，温柔、简洁的回忆记录助手。尊重用户，不诊断，不说教。聊天回复最多120字。${instruction}\n用户情绪：${draft.mood.labels.join('、')}；回忆时间：${draft.timeMark ?? '此刻'}。` }];
    for (let i = Math.max(0, draft.transcript.length - 32); i < draft.transcript.length; i += 1) {
      out.push({ role: draft.transcript[i].role === 'user' ? 'user' : 'assistant', content: draft.transcript[i].text });
    }
    if (out.length === 1) out.push({ role: 'user', content: '我想记录这份感受。' });
    return out;
  }
  private async complete(messages: ModelMessage[], options?: RequestOptions): Promise<GatewayResult> {
    const endpoint = completionUrl(this.settings.baseUrl);
    if (!endpoint || !this.settings.model.trim() || !this.key.trim()) return aiFailure('请在 AI 设置中填写 HTTPS 地址、模型名称和 API Key。');
    const signal = new CancelSignalImpl();
    if (options?.signal?.cancelled) return aiFailure('请求已取消。');
    options?.signal?.onCancel(() => signal.fire());
    let timer: number = -1;
    const timeout = new Promise<GatewayResult>((resolve) => {
      timer = setTimeout(() => { signal.fire(); resolve(aiFailure('连接超时，请检查地址或稍后重试。')); }, this.timeoutMs);
    });
    try {
      return await Promise.race([this.request(endpoint, messages, signal), timeout]);
    } finally { if (timer >= 0) clearTimeout(timer); }
  }
  private async request(endpoint: string, messages: ModelMessage[], signal: CancelSignalImpl): Promise<GatewayResult> {
    try {
      const body: CompletionBody = { model: this.settings.model.trim(), messages: messages, stream: false };
      if (this.settings.provider === 'kimi' && body.model === 'kimi-k2.6') body.thinking = { type: 'disabled' };
      const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${this.key.trim()}` };
      const init: FetchInit = { method: 'POST', headers: headers,
        body: JSON.stringify(body), signal: signal };
      const response = await this.fetcher.fetch(endpoint, init);
      if (response.status === 401 || response.status === 403) return aiFailure('API Key 无效或没有模型权限，请检查 Key。');
      if (response.status === 429) return aiFailure('模型额度不足或请求频繁，请检查服务商余额后重试。');
      if (response.status === 404) return aiFailure('模型或接口地址不存在，请检查 URL 和模型名称。');
      if (response.status < 200 || response.status >= 300) return aiFailure(`模型服务返回 ${response.status}，请检查模型配置后重试。`);
      const parsed = JSON.parse(await response.text()) as CompletionResponse;
      const text = parsed.choices?.[0]?.message?.content;
      if (typeof text !== 'string' || !text.trim()) return aiFailure('模型没有返回正文，或此接口不兼容 Chat Completions。');
      return { ok: true, text: text.replace(/<think>[\s\S]*?<\/think>/g, '').trim(), requestId: '' };
    } catch { return aiFailure('连接失败，请检查网络、URL 和模型服务状态。'); }
  }
}
