import test from 'node:test';
import assert from 'node:assert/strict';
import { createMiniMaxTransport } from '../src/minimax.js';

test('MiniMax receives assistant roles and the complete conversation in order', async () => {
  let body: { messages: Array<{ role: string; content: string }> } | undefined;
  const transport = createMiniMaxTransport({
    apiKey: 'test-key', baseUrl: 'https://example.test', model: 'test-model', timeoutMs: 1000,
    fetchImpl: async (_input, init) => {
      body = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ choices: [{ message: { content: '那一刻是什么感受？' } }] }));
    },
  });
  const result = await transport.chat({
    system: '安静地听', temperature: 0.6,
    messages: [
      { role: 'ai', text: '你最先想起什么？', ts: 1 },
      { role: 'user', text: '和朋友去河边', ts: 2 },
    ],
  });
  assert.deepEqual(body?.messages.map((m) => m.role), ['system', 'assistant', 'user']);
  assert.equal(body?.messages[2]?.content, '和朋友去河边');
  assert.equal(result.text, '那一刻是什么感受？');
});
