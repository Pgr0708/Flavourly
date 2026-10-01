// Entry point for `npm start`, `npm run dev` and PM2 (cluster mode imports this file directly).
import { build } from './build.js';
import { loadConfig } from './config.js';
import { migrate } from './db.js';
import { log } from './util.js';

async function main() {
  const config = loadConfig();
  const deps = build(config);
  await migrate(deps.db);

  const server = deps.app.listen(config.PORT, config.HOST, () => {
    log.info('flavourly api listening', { host: config.HOST, port: config.PORT, pid: process.pid, env: config.NODE_ENV });
    process.send?.('ready'); // PM2 wait_ready: reloads switch traffic only once this instance is up
  });
  // Longer than Nginx's upstream keepalive so idle connections are never cut mid-request.
  server.keepAliveTimeout = 65_000;
  server.headersTimeout = 66_000;
  server.requestTimeout = 120_000;

  let closing = false;
  const shutdown = async (signal) => {
    if (closing) return;
    closing = true;
    log.info('shutting down', { signal });
    setTimeout(() => process.exit(1), 15_000).unref();
    server.close(async () => {
      await deps.db.end().catch(() => {});
      await deps.cache.close().catch(() => {});
      process.exit(0);
    });
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('message', (message) => message === 'shutdown' && shutdown('message'));
  process.on('unhandledRejection', (error) => log.error('unhandled rejection', { error: String(error?.stack ?? error) }));
}

main().catch((error) => {
  log.error('failed to start', { error: error.message });
  process.exit(1);
});
