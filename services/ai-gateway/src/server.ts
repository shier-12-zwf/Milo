/**
 * Public HTTP gateway for the recall flow. Validates inputs, calls MiniMax
 * through the injected transport, and emits a single error envelope shape
 * (`ErrorEnvelope`) on every failure path.
 */
import { randomUUID, timingSafeEqual } from 'node:crypto';
import express, { type Request, type Response, type NextFunction, type Express } from 'express';
import {
  buildDiaryPrompt,
  buildOpeningPrompt,
  buildRespondSystem,
  CONVERSATION_SYSTEM,
} from './prompts.js';
import { type MiniMaxTransport } from './minimax.js';
import {
  isValidMoodId,
  isValidRole,
  MAX_LABELS,
  MAX_LABEL_LENGTH,
  MAX_TEXT_LENGTH,
  MAX_TRANSCRIPT_LINES,
  type ChatMessage,
  type DraftSummary,
  type ErrorEnvelope,
} from './contracts.js';

export interface ServerDeps {
  aiEnabled?: boolean;
  transport?: MiniMaxTransport;
  rateLimitPerMinute: number;
  requestLog?: (entry: RequestLog) => void;
  bearerToken?: string;
  trustLoopbackProxy?: boolean;
}

export interface RequestLog {
  requestId: string;
  route: string;
  status: number;
  code?: string;
  durationMs: number;
  blocked: boolean;
}

const SYSTEM_DIARY = '你是「回响」。忠实整理用户自己的话为第一人称日记，不编造，只输出正文。';

interface RouteDeps extends ServerDeps {}

export function createApp(deps: RouteDeps): Express {
  const aiEnabled = deps.aiEnabled === true;
  const transport = deps.transport;
  if (aiEnabled && transport === undefined) {
    throw new Error('Enabled AI requires a configured transport.');
  }
  const app = express();
  app.disable('x-powered-by');
  if (deps.trustLoopbackProxy) app.set('trust proxy', 'loopback');

  // Request id + basic access log; never logs the body.
  app.use((req, res, next) => {
    const id = req.header('x-request-id') ?? randomUUID();
    res.setHeader('x-request-id', id);
    const started = Date.now();
    res.on('finish', () => {
      deps.requestLog?.({
        requestId: id,
        route: req.path,
        status: res.statusCode,
        durationMs: Date.now() - started,
        blocked: res.getHeader('x-blocked') === 'true',
      });
    });
    next();
  });

  // Pause before parsing legacy/malformed payloads or consulting upstream credentials.
  // Existing clients get the same explicit response, even with an expired app token.
  app.use('/v1/recall', (_req, res, next) => {
    if (!aiEnabled) {
      respondError(res, 503, 'AI_DISABLED', 'AI 功能已暂时下架，仍可正常记录和保存日记。',
        res.getHeader('x-request-id') as string);
      return;
    }
    next();
  });
  app.use(express.json({ limit: '64kb' }));

  // The client token is separate from the upstream MiniMax secret.
  app.use('/v1', (req, res, next) => {
    if (deps.bearerToken) {
      const expected = Buffer.from(`Bearer ${deps.bearerToken}`);
      const supplied = Buffer.from(req.header('authorization') ?? '');
      if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) {
        respondError(res, 401, 'INVALID_REQUEST', '请更新应用后重试。', res.getHeader('x-request-id') as string);
        return;
      }
    }
    next();
  });

  // Per-IP token bucket; simple in-memory. One window per minute.
  const buckets = new Map<string, { count: number; resetAt: number }>();
  app.use((req, res, next) => {
    if (req.path === '/health') {
      next();
      return;
    }
    const key = req.ip ?? 'unknown';
    const now = Date.now();
    for (const [ip, entry] of buckets) {
      if (entry.resetAt <= now) buckets.delete(ip);
    }
    const bucket = buckets.get(key);
    if (!bucket || bucket.resetAt < now) {
      buckets.set(key, { count: 1, resetAt: now + 60_000 });
      next();
      return;
    }
    bucket.count += 1;
    if (bucket.count > deps.rateLimitPerMinute) {
      respondError(res, 429, 'RATE_LIMITED', '请求过于频繁，请稍后再试。', req.header('x-request-id') ?? randomUUID());
      return;
    }
    next();
  });

  app.get('/health', (req, res) => {
    const requestId = req.header('x-request-id') ?? randomUUID();
    res.json({
      ok: true,
      aiEnabled,
      aiStatus: aiEnabled ? 'enabled' : 'paused',
      model: 'gateway',
      baseUrl: 'gateway',
      requestId,
    });
  });

  app.post('/v1/recall/open', async (req, res) => {
    const requestId = res.getHeader('x-request-id') as string;
    const parsed = parseDraft(req.body);
    if (parsed.kind === 'invalid') {
      respondError(res, 400, 'INVALID_REQUEST', parsed.reason, requestId);
      return;
    }
    await runCompletion(transport, res, requestId, CONVERSATION_SYSTEM, [
      { role: 'user', text: buildOpeningPrompt(parsed.value), ts: Date.now() },
    ]);
  });

  app.post('/v1/recall/respond', async (req, res) => {
    const requestId = res.getHeader('x-request-id') as string;
    const parsed = parseDraft(req.body);
    if (parsed.kind === 'invalid') {
      respondError(res, 400, 'INVALID_REQUEST', parsed.reason, requestId);
      return;
    }
    const userText = readString(req.body?.userText);
    if (userText === undefined || userText.length === 0) {
      respondError(res, 400, 'INVALID_REQUEST', '缺少 userText。', requestId);
      return;
    }
    if (userText.length > MAX_TEXT_LENGTH) {
      respondError(res, 400, 'INVALID_REQUEST', 'userText 超过最大长度。', requestId);
      return;
    }
    const draft = parsed.value;
    // Current clients include the latest user line; older clients send it separately.
    const messages = draft.transcript.slice();
    const last = messages.at(-1);
    if (last?.role !== 'user' || last.text !== userText) {
      messages.push({ role: 'user', text: userText, ts: Date.now() });
    }
    await runCompletion(transport, res, requestId, buildRespondSystem(draft), messages);
  });

  app.post('/v1/recall/diary', async (req, res) => {
    const requestId = res.getHeader('x-request-id') as string;
    const parsed = parseDraft(req.body);
    if (parsed.kind === 'invalid') {
      respondError(res, 400, 'INVALID_REQUEST', parsed.reason, requestId);
      return;
    }
    await runCompletion(transport, res, requestId, SYSTEM_DIARY, [
      { role: 'user', text: buildDiaryPrompt(parsed.value), ts: Date.now() },
    ]);
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    const requestId = res.getHeader('x-request-id') as string ?? randomUUID();
    respondError(res, 500, 'AI_UNAVAILABLE', '网关内部错误。', requestId);
  });

  return app;
}

type ParseResult =
  | { kind: 'ok'; value: DraftSummary }
  | { kind: 'invalid'; reason: string };

function parseDraft(body: unknown): ParseResult {
  if (typeof body !== 'object' || body === null) {
    return { kind: 'invalid', reason: '请求体必须是对象。' };
  }
  const root = body as Record<string, unknown>;
  const draftRaw = root['draft'];
  if (typeof draftRaw !== 'object' || draftRaw === null) {
    return { kind: 'invalid', reason: '缺少 draft 字段。' };
  }
  const draft = draftRaw as Record<string, unknown>;
  const moodRaw = draft['mood'];
  if (typeof moodRaw !== 'object' || moodRaw === null) {
    return { kind: 'invalid', reason: '缺少 draft.mood 字段。' };
  }
  const mood = moodRaw as Record<string, unknown>;
  const valence = mood['valence'];
  if (typeof valence !== 'number' || !Number.isFinite(valence)) {
    return { kind: 'invalid', reason: 'draft.mood.valence 必须是有限数字。' };
  }
  const labels = mood['labels'];
  if (!Array.isArray(labels) || labels.length > MAX_LABELS) {
    return { kind: 'invalid', reason: 'draft.mood.labels 必须是数组且不超过 6 个。' };
  }
  for (let index = 0; index < labels.length; index += 1) {
    const label = labels[index];
    if (typeof label !== 'string' || label.length === 0 || label.length > MAX_LABEL_LENGTH) {
      return { kind: 'invalid', reason: 'draft.mood.labels 中的元素必须是 1~32 字符的字符串。' };
    }
  }
  const emotionId = mood['emotionId'];
  if (emotionId !== undefined && !isValidMoodId(emotionId)) {
    return { kind: 'invalid', reason: 'draft.mood.emotionId 必须是已知的 MoodId。' };
  }
  const timeMark = draft['timeMark'];
  if (timeMark !== undefined && (typeof timeMark !== 'string' || timeMark.length === 0 || timeMark.length > 64)) {
    return { kind: 'invalid', reason: 'draft.timeMark 必须是 1~64 字符的字符串。' };
  }
  const transcriptRaw = draft['transcript'];
  if (!Array.isArray(transcriptRaw) || transcriptRaw.length > MAX_TRANSCRIPT_LINES) {
    return { kind: 'invalid', reason: 'draft.transcript 必须是数组且不超过 32 条。' };
  }
  const transcript: ChatMessage[] = [];
  for (let index = 0; index < transcriptRaw.length; index += 1) {
    const item = transcriptRaw[index];
    if (typeof item !== 'object' || item === null) {
      return { kind: 'invalid', reason: 'transcript 元素必须是对象。' };
    }
    const record = item as Record<string, unknown>;
    if (!isValidRole(record['role'])) {
      return { kind: 'invalid', reason: 'transcript.role 必须是 user 或 ai。' };
    }
    if (typeof record['text'] !== 'string' || record['text'].length === 0 || record['text'].length > MAX_TEXT_LENGTH) {
      return { kind: 'invalid', reason: 'transcript.text 必须是 1~2000 字符的字符串。' };
    }
    if (typeof record['ts'] !== 'number') {
      return { kind: 'invalid', reason: 'transcript.ts 必须是数字。' };
    }
    transcript.push({ role: record['role'], text: record['text'], ts: record['ts'] });
  }
  const summary: DraftSummary = {
    mood: { valence, labels: labels as string[] },
    transcript,
  };
  if (emotionId !== undefined) summary.mood.emotionId = emotionId;
  if (typeof timeMark === 'string') summary.timeMark = timeMark;
  return { kind: 'ok', value: summary };
}

function readString(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  return value;
}

async function runCompletion(
  transport: MiniMaxTransport | undefined,
  res: Response,
  requestId: string,
  system: string,
  messages: ChatMessage[],
): Promise<void> {
  try {
    if (transport === undefined) throw new Error('AI transport is not configured.');
    const result = await transport.chat({
      system,
      messages,
      temperature: 0.6,
    });
    if (result.blocked) {
      res.setHeader('x-blocked', 'true');
      respondError(res, 451, 'CONTENT_BLOCKED', '对话内容触发了内容策略，请换个方向。', requestId);
      return;
    }
    if (result.text.length === 0) {
      respondError(res, 502, 'AI_UNAVAILABLE', 'AI 没有返回内容。', requestId);
      return;
    }
    res.json({ text: result.text, requestId });
  } catch {
    respondError(res, 502, 'AI_UNAVAILABLE', 'AI 服务暂时不可用。', requestId);
  }
}

export function startServer(deps: ServerDeps & { port: number; host?: string }) {
  const app = createApp(deps);
  return app.listen(deps.port, deps.host ?? '127.0.0.1', () => {
    process.stdout.write(`AI gateway listening on ${deps.host ?? '127.0.0.1'}:${deps.port}\n`);
  });
}

export function respondError(
  res: Response,
  status: number,
  code: ErrorEnvelope['code'],
  message: string,
  requestId: string,
): void {
  const body: ErrorEnvelope = {
    code,
    message,
    retryable: code === 'AI_UNAVAILABLE' || code === 'RATE_LIMITED',
    requestId,
  };
  res.status(status).json(body);
}
