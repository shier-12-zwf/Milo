/**
 * Validates environment configuration at startup. Exits with a non-zero code
 * when enabled AI is started without the required secret. AI is paused by default.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function readDotenv(): void {
  try {
    const raw = readFileSync(resolve(process.cwd(), '.env'), 'utf8');
    for (const line of raw.split('\n')) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq < 0) continue;
      const key = trimmed.slice(0, eq).trim();
      const value = trimmed.slice(eq + 1).trim();
      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  } catch {
    // .env is optional; fall back to process.env directly.
  }
}

export interface GatewayConfig {
  aiEnabled: boolean;
  apiKey: string;
  baseUrl: string;
  model: string;
  port: number;
  timeoutMs: number;
  host: string;
  rateLimitPerMinute: number;
  bearerToken: string;
  trustLoopbackProxy: boolean;
}

export function loadConfig(): GatewayConfig {
  readDotenv();
  return configFromEnv(process.env);
}

export function configFromEnv(env: NodeJS.ProcessEnv): GatewayConfig {
  const aiSetting = env.AI_ENABLED?.trim().toLowerCase() ?? 'false';
  if (aiSetting !== 'true' && aiSetting !== 'false') {
    throw new Error('Invalid AI_ENABLED; use true or false.');
  }
  const aiEnabled = aiSetting === 'true';
  const apiKey = env.MINIMAX_API_KEY ?? '';
  const baseUrl = env.MINIMAX_BASE_URL ?? 'https://api.minimax.chat/v1';
  const model = env.MINIMAX_MODEL ?? 'MiniMax-M3';
  const port = Number(env.PORT ?? 8787);
  const timeoutMs = Number(env.MINIMAX_TIMEOUT_MS ?? env.AI_TIMEOUT_MS ?? 20000);
  const host = env.HOST ?? '127.0.0.1';
  const rateLimitPerMinute = Number(env.RATE_LIMIT_PER_MINUTE ?? 60);
  const bearerToken = env.GATEWAY_BEARER_TOKEN?.trim() ?? '';
  const trustLoopbackProxy = env.TRUST_LOOPBACK_PROXY === 'true';
  if (aiEnabled && apiKey.trim().length === 0) {
    throw new Error('Missing MINIMAX_API_KEY. Set it in the environment or .env before starting the gateway.');
  }
  if (!Number.isInteger(port) || port <= 0 || port >= 65536) {
    throw new Error('Invalid PORT.');
  }
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1000) {
    throw new Error('Invalid MINIMAX_TIMEOUT_MS; must be ≥ 1000.');
  }
  if (baseUrl.length === 0 || !baseUrl.startsWith('http')) {
    throw new Error('Invalid MINIMAX_BASE_URL.');
  }
  if (!Number.isInteger(rateLimitPerMinute) || rateLimitPerMinute < 1) {
    throw new Error('Invalid RATE_LIMIT_PER_MINUTE.');
  }
  if (aiEnabled && env.NODE_ENV === 'production' && bearerToken.length < 32) {
    throw new Error('Production requires GATEWAY_BEARER_TOKEN with at least 32 characters.');
  }
  return { aiEnabled, apiKey, baseUrl, model, port, timeoutMs, host, rateLimitPerMinute, bearerToken, trustLoopbackProxy };
}

/** Replaces the key with a redacted marker suitable for logs and error responses. */
export function redactKey(key: string): string {
  if (key.length === 0) return '<missing>';
  if (key.length <= 6) return '***';
  return `${key.slice(0, 3)}***${key.slice(-3)}`;
}
