import {
  type ChatMessage,
  type MoodState,
  type MoodId,
} from '../../core/model/Domain';

export interface MoodSummary {
  valence: number;
  labels: string[];
  emotionId?: MoodId;
}

export interface DraftSummary {
  mood: MoodSummary;
  timeMark?: string;
  transcript: ChatMessage[];
}

export type GatewayErrorCode =
  | 'AI_UNAVAILABLE'
  | 'RATE_LIMITED'
  | 'INVALID_REQUEST'
  | 'CONTENT_BLOCKED'
  | 'OFFLINE'
  | 'UNKNOWN';

export interface GatewayError {
  code: GatewayErrorCode;
  retryable: boolean;
  requestId: string;
  message: string;
}

export type GatewayResult = GatewaySuccess | GatewayFailure;

export interface GatewaySuccess {
  ok: true;
  text: string;
  requestId: string;
}

export interface GatewayFailure {
  ok: false;
  error: GatewayError;
}

export interface OpenRequestBody {
  draft: DraftSummary;
}

export interface RespondRequestBody {
  draft: DraftSummary;
  userText: string;
}

export interface DiaryRequestBody {
  draft: DraftSummary;
}

export interface AiGatewayClient {
  open(request: OpenRequestBody, options?: RequestOptions): Promise<GatewayResult>;
  respond(request: RespondRequestBody, options?: RequestOptions): Promise<GatewayResult>;
  createDiary(request: DiaryRequestBody, options?: RequestOptions): Promise<GatewayResult>;
}

export type OpenArg = OpenRequestBody;
export type RespondArg = RespondRequestBody;
export type DiaryArg = DiaryRequestBody;

export interface RequestOptions {
  requestId?: string;
  /** Cancel the in-flight call. The injected fetcher must observe this flag. */
  signal?: CancelSignal;
}

export interface CancelSignal {
  cancelled: boolean;
  onCancel(handler: () => void): void;
}

export class CancelSignalImpl implements CancelSignal {
  cancelled: boolean = false;
  private handlers: Array<() => void> = [];

  onCancel(handler: () => void): void {
    this.handlers.push(handler);
  }

  fire(): void {
    this.cancelled = true;
    for (let index = 0; index < this.handlers.length; index += 1) {
      this.handlers[index]();
    }
  }
}

export function createCancelSignal(): CancelSignal {
  return new CancelSignalImpl();
}

function fireCancel(signal: CancelSignal): void {
  if (signal instanceof CancelSignalImpl) {
    signal.fire();
  }
}

/** Minimal fetch shape so tests can inject a fake. */
export interface FetchInit {
  method: string;
  headers: Record<string, string>;
  body: string;
  signal?: CancelSignal;
}

export interface FetchLike {
  fetch(input: string, init: FetchInit): Promise<FetchResponse>;
}

export interface FetchResponse {
  status: number;
  text(): Promise<string>;
  json(): Promise<Record<string, Object>>;
}

export interface ClientConfig {
  baseUrl: string;
  bearerToken: string;
  timeoutMs: number;
  fetcher: FetchLike;
}

export interface RequestHeaders {
  contentType: string;
  authorization: string;
  requestId: string;
}

function toHeaders(h: RequestHeaders): Record<string, string> {
  return {
    'Content-Type': h.contentType,
    'Authorization': h.authorization,
    'x-request-id': h.requestId,
  };
}

/** Trim a ChatMessage down to the wire shape accepted by the gateway. */
function toSummaryMessage(message: ChatMessage): ChatMessage {
  return { role: message.role, text: message.text, ts: message.ts };
}

function cloneMood(mood: MoodSummary): MoodSummary {
  const out: MoodSummary = {
    valence: mood.valence,
    labels: mood.labels.slice(),
  };
  if (mood.emotionId !== undefined) {
    out.emotionId = mood.emotionId;
  }
  return out;
}

function toSummary(draft: DraftSummary): DraftSummary {
  const out: DraftSummary = {
    mood: cloneMood(draft.mood),
    transcript: draft.transcript.map(toSummaryMessage),
  };
  if (draft.timeMark !== undefined) {
    out.timeMark = draft.timeMark;
  }
  return out;
}

export class HttpAiGatewayClient implements AiGatewayClient {
  private config: ClientConfig;

  constructor(config: ClientConfig) {
    this.config = config;
  }

  async open(request: OpenRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    const body: OpenRequestBody = { draft: toSummary(request.draft) };
    return this.post('/v1/recall/open', body, options);
  }

  async respond(request: RespondRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    const body: RespondRequestBody = {
      draft: toSummary(request.draft),
      userText: request.userText,
    };
    return this.post('/v1/recall/respond', body, options);
  }

  async createDiary(request: DiaryRequestBody, options?: RequestOptions): Promise<GatewayResult> {
    const body: DiaryRequestBody = { draft: toSummary(request.draft) };
    return this.post('/v1/recall/diary', body, options);
  }

  private async post(path: string, body: Object, options?: RequestOptions): Promise<GatewayResult> {
    const requestId = options?.requestId ?? randomId();
    const headers: RequestHeaders = {
      contentType: 'application/json',
      authorization: `Bearer ${this.config.bearerToken}`,
      requestId: requestId,
    };
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      if (options?.signal !== undefined) {
        fireCancel(options.signal);
      }
    }, this.config.timeoutMs);
    try {
      const init: FetchInit = {
        method: 'POST',
        headers: toHeaders(headers),
        body: JSON.stringify(body),
      };
      if (options?.signal !== undefined) {
        init.signal = options.signal;
      }
      const response = await this.config.fetcher.fetch(`${this.config.baseUrl}${path}`, init);
      return await this.parse(response, requestId);
    } catch (error) {
      void error;
      if (timedOut || (options?.signal !== undefined && options.signal.cancelled)) {
        return this.failure('AI_UNAVAILABLE', 'AI 服务暂未响应。', requestId);
      }
      return this.failure('OFFLINE', '网络连接不可用。', requestId);
    } finally {
      clearTimeout(timer);
    }
  }

  private async parse(response: FetchResponse, requestId: string): Promise<GatewayResult> {
    const text = await response.text();
    let parsed: Record<string, Object> | undefined;
    if (text.length > 0) {
      try {
        parsed = JSON.parse(text) as Record<string, Object>;
      } catch {
        // fall through to error
      }
    }
    if (response.status >= 200 && response.status < 300) {
      if (parsed === undefined) {
        return this.failure('AI_UNAVAILABLE', 'AI 没有返回内容。', requestId);
      }
      const reply = parsed['text'];
      if (typeof reply !== 'string' || reply.trim().length === 0) {
        return this.failure('AI_UNAVAILABLE', 'AI 没有返回内容。', requestId);
      }
      const responseId = parsed['requestId'];
      return {
        ok: true,
        text: reply,
        requestId: typeof responseId === 'string' ? responseId : requestId,
      };
    }
    const code = this.errorCodeFromStatus(response.status);
    const responseId = parsed && typeof parsed['requestId'] === 'string' ? parsed['requestId'] : requestId;
    return this.failure(code, this.errorMessage(code, response.status), responseId);
  }

  private errorCodeFromStatus(status: number): GatewayErrorCode {
    if (status === 429) return 'RATE_LIMITED';
    if (status === 451) return 'CONTENT_BLOCKED';
    if (status >= 500) return 'AI_UNAVAILABLE';
    if (status >= 400) return 'INVALID_REQUEST';
    return 'UNKNOWN';
  }

  private errorMessage(code: GatewayErrorCode, status: number): string {
    switch (code) {
      case 'RATE_LIMITED': return '请求过于频繁，请稍后再试。';
      case 'CONTENT_BLOCKED': return '对话内容触发了内容策略，请换个方向。';
      case 'INVALID_REQUEST': return `请求参数无效 (HTTP ${status})。`;
      case 'AI_UNAVAILABLE': return 'AI 服务暂时不可用。';
      case 'OFFLINE': return '网络连接不可用。';
      default: return '网关返回未知错误。';
    }
  }

  private failure(code: GatewayErrorCode, message: string, requestId: string): GatewayResult {
    const retryable = code === 'AI_UNAVAILABLE' || code === 'RATE_LIMITED' || code === 'OFFLINE';
    return {
      ok: false,
      error: { code: code, retryable: retryable, requestId: requestId, message: message },
    };
  }
}

const RANDOM_CHARS: string = '0123456789abcdef';

function randomCharAt(index: number): string {
  // Force a switch instead of indexed access; this still returns a single hex char.
  switch (index) {
    case 0: return '0';
    case 1: return '1';
    case 2: return '2';
    case 3: return '3';
    case 4: return '4';
    case 5: return '5';
    case 6: return '6';
    case 7: return '7';
    case 8: return '8';
    case 9: return '9';
    case 10: return 'a';
    case 11: return 'b';
    case 12: return 'c';
    case 13: return 'd';
    case 14: return 'e';
    default: return 'f';
  }
}

function randomId(): string {
  // 8 hex chars are enough for client-side correlation. Not used for security.
  let out = '';
  for (let index = 0; index < 8; index += 1) {
    const rand = Math.floor(Math.random() * 16);
    out += randomCharAt(rand);
  }
  return `req-${out}`;
}

/** Convenience helpers. */
export function isSuccess(result: GatewayResult): boolean {
  return result.ok === true;
}

export function isFailure(result: GatewayResult): boolean {
  return result.ok === false;
}