/**
 * Vercel Serverless adapter. Wraps the Express app so the same handler
 * works behind `vercel deploy`. Configured via the Vercel project's
 * Environment Variables page; no `.env` is read here.
 *
 * This file is plain ESM JavaScript so it does not fight the gateway's
 * strict TypeScript build (rootDir: "src"). Vercel handles the rest.
 */
import { createApp } from '../dist/server.js';
import { createMiniMaxTransport } from '../dist/minimax.js';
import { loadConfig } from '../dist/config.js';

const config = loadConfig();
const transport = config.aiEnabled ? createMiniMaxTransport({
  apiKey: config.apiKey,
  baseUrl: config.baseUrl,
  model: config.model,
  timeoutMs: config.timeoutMs,
}) : undefined;

const app = createApp({ aiEnabled: config.aiEnabled, transport, rateLimitPerMinute: config.rateLimitPerMinute, bearerToken: config.bearerToken });

export default function handler(req, res) {
  // Express handles the (req, res) objects Vercel passes directly.
  app(req, res);
}
