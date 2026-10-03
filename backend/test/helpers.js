// Shared test setup: a fresh MySQL database per suite (TEST_DB_* env, default root@127.0.0.1:3307),
// fake OpenAI + RevenueCat servers, optional real Redis (redis-memory-server), and a tiny API client.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import mysql from 'mysql2/promise';
import { build } from '../src/build.js';
import { loadConfig } from '../src/config.js';
import { migrate } from '../src/db.js';
import { fakeFoodApis, startFakeOpenAI, startFakeRevenueCat } from './fake-openai.js';

export const DB = {
  host: process.env.TEST_DB_HOST ?? '127.0.0.1',
  port: Number(process.env.TEST_DB_PORT ?? 3307),
  user: process.env.TEST_DB_USER ?? 'root',
  password: process.env.TEST_DB_PASSWORD ?? '',
};

let redisServer = null;
/** One real Redis for the whole run (built inside node_modules, nothing installed system-wide). */
export async function startRedis() {
  if (!redisServer) {
    const { RedisMemoryServer } = await import('redis-memory-server');
    redisServer = await RedisMemoryServer.create();
  }
  return `redis://${await redisServer.getHost()}:${await redisServer.getPort()}`;
}
export async function stopRedis() {
  await redisServer?.stop();
  redisServer = null;
}

/** `user`: a RevenueCat id sent with every call that doesn't name one ("premium-…" = subscribed). */
export async function setup({ env = {}, fetcher, now, redisUrl = '', database, user } = {}) {
  const name = database ?? `flavourly_test_${crypto.randomBytes(4).toString('hex')}`;
  const admin = await mysql.createConnection(DB);
  await admin.query(`CREATE DATABASE IF NOT EXISTS \`${name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
  const ai = await startFakeOpenAI({ slowMs: 2_500 });
  const revenueCat = await startFakeRevenueCat();
  const imageDir = await fs.mkdtemp(path.join(os.tmpdir(), 'flavourly-images-'));
  const config = loadConfig({
    NODE_ENV: 'test',
    DB_HOST: DB.host, DB_PORT: String(DB.port), DB_USER: DB.user, DB_PASSWORD: DB.password, DB_NAME: name, DB_POOL_SIZE: '4',
    OPENAI_API_KEY: 'test-key', OPENAI_BASE_URL: ai.url, OPENAI_TIMEOUT_MS: '1500',
    REVENUECAT_SECRET_KEY: 'sk_test', REVENUECAT_BASE_URL: revenueCat.url,
    REDIS_URL: redisUrl, REDIS_PREFIX: `t${crypto.randomBytes(3).toString('hex')}:`,
    IMAGE_GENERATION: '1', IMAGE_DIR: imageDir, PUBLIC_URL: 'https://flavourly.example.com',
    TRUST_PROXY: 'false',
    ...env,
  });
  const food = fakeFoodApis();
  const deps = build(config, { fetcher, now, http: food.http });
  await migrate(deps.db);
  if (redisUrl) await waitFor(() => deps.cache.backend === 'redis');
  const server = await new Promise((resolve) => {
    const s = deps.app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;

  async function api(route, body, { token, headers = {}, method = 'POST', raw } = {}) {
    const response = await fetch(`${base}${route}`, {
      method,
      headers: {
        ...(body !== undefined || raw !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(user ? { 'X-RC-App-User': user } : {}),
        ...headers,
      },
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {
      json = null;
    }
    return { status: response.status, body: json, text, headers: response.headers };
  }

  async function register(installID = crypto.randomUUID().toUpperCase()) {
    const { status, body } = await api('/v1/devices', { installID, platform: 'ios', appVersion: '1.0' });
    if (status !== 200) throw new Error(`register failed: ${status} ${JSON.stringify(body)}`);
    return body.token;
  }

  async function teardown({ keepDatabase = false } = {}) {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    await deps.db.end();
    await deps.cache.close();
    await ai.close();
    await revenueCat.close();
    if (!keepDatabase) await admin.query(`DROP DATABASE IF EXISTS \`${name}\``);
    await admin.end();
    await fs.rm(imageDir, { recursive: true, force: true });
  }

  return { config, deps, ai, food, base, api, register, teardown, database: name, admin };
}

export async function waitFor(check, timeoutMs = 5_000) {
  const started = Date.now();
  while (!(await check())) {
    if (Date.now() - started > timeoutMs) throw new Error('timed out waiting');
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

/** A fetcher stand-in that serves fixtures by URL and records every request. */
export function stubFetcher(routes) {
  const requests = [];
  const respond = (url) => {
    requests.push(url);
    const match = Object.entries(routes).find(([key]) => url.startsWith(key));
    if (!match) {
      const error = new Error(`unexpected fetch ${url}`);
      error.status = 502;
      throw error;
    }
    return match[1];
  };
  return {
    requests,
    async fetchPage(url) {
      const route = respond(url);
      return { url, status: route.status ?? 200, contentType: 'text/html', body: route.body ?? route };
    },
    async fetchJson(url) {
      const route = respond(url);
      if (typeof route === 'function') return route(url);
      return typeof route === 'string' ? JSON.parse(route) : route.json ?? route;
    },
  };
}

export const fixture = (file) => fs.readFile(new URL(`./fixtures/${file}`, import.meta.url), 'utf8');
