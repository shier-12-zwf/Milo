/**
 * Transport to the MiniMax Chat Completions endpoint. Pure HTTP — no SDK.
 * Caller supplies a `fetchImpl` so tests can substitute a deterministic
 * response without touching the network.
 */
import type { ChatMessage } from './contracts.js';

export interface ChatRequest {
  system: string;
  messages: ChatMessage[];
  temperature: number;
}

export interface ChatResult {
  text: string;
  blocked: boolean;
}

export interface MiniMaxTransport {
  chat(request: ChatRequest): Promise<ChatResult>;
}

export interface TransportDeps {
  apiKey: string;
  baseUrl: string;
  model: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}

export function createMiniMaxTransport(deps: TransportDeps): MiniMaxTransport {
  const fetchImpl = deps.fetchImpl ?? globalThis.fetch;
  if (typeof fetchImpl !== 'function') {
    throw new Error('No fetch implementation available.');
  }
  return {
    async chat(request: ChatRequest): Promise<ChatResult> {
      const url = `${deps.baseUrl.replace(/\/$/, '')}/text/chatcompletion_v2`;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), deps.timeoutMs);
      try {
        const response = await fetchImpl(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${deps.apiKey}`,
          },
          body: JSON.stringify({
            model: deps.model,
            temperature: request.temperature,
            thinking: { type: 'disabled' },
            messages: [
              { role: 'system', content: request.system, name: 'Milo' },
              ...request.messages.map((m) => ({ role: m.role === 'ai' ? 'assistant' : 'user', content: m.text, name: m.role === 'user' ? 'user' : 'assistant' })),
            ],
          }),
          signal: controller.signal,
        });
        if (!response.ok) {
          const body = await safeText(response);
          if (looksLikeContentBlock(response.status, body)) {
            return { text: '', blocked: true };
          }
          throw new Error(`MiniMax HTTP ${response.status}`);
        }
        const json = await response.json() as Record<string, unknown>;
        return { text: extractText(json), blocked: false };
      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          throw new Error('MiniMax request timed out');
        }
        throw error;
      } finally {
        clearTimeout(timer);
      }
    },
  };
}

async function safeText(response: Response): Promise<string> {
  try { return await response.text(); } catch { return ''; }
}

function looksLikeContentBlock(status: number, body: string): boolean {
  if (status === 400 && /sensitivity|content/i.test(body)) return true;
  if (status === 451) return true;
  return false;
}

function extractText(payload: Record<string, unknown>): string {
  const choices = payload['choices'];
  if (!Array.isArray(choices) || choices.length === 0) return '';
  const first = choices[0] as Record<string, unknown>;
  const message = first['message'] as Record<string, unknown> | undefined;
  if (message && typeof message['content'] === 'string') {
    return message['content'].trim();
  }
  if (typeof first['text'] === 'string') {
    return first['text'].trim();
  }
  return '';
}
