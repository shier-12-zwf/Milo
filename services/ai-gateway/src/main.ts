import { loadConfig } from './config.js';
import { createMiniMaxTransport } from './minimax.js';
import { startServer } from './server.js';

try {
  const config = loadConfig();
  const server = startServer({
    ...config,
    transport: config.aiEnabled ? createMiniMaxTransport(config) : undefined,
    requestLog: (entry) => process.stdout.write(`${JSON.stringify(entry)}\n`),
  });
  const shutdown = () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 25_000).unref();
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : 'Gateway startup failed.'}\n`);
  process.exitCode = 1;
}
