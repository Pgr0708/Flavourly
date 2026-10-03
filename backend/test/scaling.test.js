import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import Redis from 'ioredis';
import { createCache } from '../src/cache.js';
import { setup, startRedis, stopRedis, waitFor } from './helpers.js';

// Horizontal scaling: two API instances (as two PM2 workers or two servers would be) share one
// MySQL and one Redis, so tokens, caches, rate limits and free-plan limits hold across all of them.
let redisUrl;
before(async () => { redisUrl = await startRedis(); });
after(() => stopRedis());

describe('Redis cache', () => {
  it('stores JSON with expiry under this app’s prefix only', async () => {
    const cache = createCache({ url: redisUrl, prefix: 'flavourly-test:' });
    await waitFor(() => cache.backend === 'redis');
    await cache.set('greeting', { hello: 'world' }, 1);
    assert.deepEqual(await cache.get('greeting'), { hello: 'world' });
    const raw = new Redis(redisUrl);
    assert.equal(await raw.exists('flavourly-test:greeting'), 1, 'prefixed key');
    assert.equal(await raw.exists('greeting'), 0, 'nothing written outside the prefix');
    await raw.set('other-app:key', 'untouched');
    await new Promise((resolve) => setTimeout(resolve, 1_100));
    assert.equal(await cache.get('greeting'), null, 'expired');
    assert.equal(await raw.get('other-app:key'), 'untouched');
    await raw.quit();
    await cache.close();
  });
  it('counters are atomic and expire with their window', async () => {
    const cache = createCache({ url: redisUrl, prefix: 'flavourly-test:' });
    await waitFor(() => cache.backend === 'redis');
    const counts = await Promise.all(Array.from({ length: 20 }, () => cache.incr('counter', 1)));
    assert.deepEqual([...counts].sort((a, b) => a - b), Array.from({ length: 20 }, (_, i) => i + 1));
    await new Promise((resolve) => setTimeout(resolve, 1_100));
    assert.equal(await cache.incr('counter', 1), 1);
    await cache.close();
  });
  it('keeps working from memory when Redis is unreachable', async () => {
    const cache = createCache({ url: 'redis://127.0.0.1:1', prefix: 'x:' });
    await cache.set('k', [1, 2], 60);
    assert.deepEqual(await cache.get('k'), [1, 2]);
    assert.equal(await cache.incr('c', 60), 1);
    assert.equal(await cache.incr('c', 60), 2);
    assert.equal(await cache.ping(), 'down');
    assert.equal(cache.backend, 'memory');
    await cache.close();
  });
});

describe('two instances, one MySQL + one Redis', () => {
  let a;
  let b;
  before(async () => {
    a = await setup({ redisUrl, env: { FREE_AI_SWAPS_PER_WEEK: '3', RATE_LIMIT_PER_MINUTE: '1000', REDIS_PREFIX: 'shared:' } });
    b = await setup({ redisUrl, database: a.database, env: { FREE_AI_SWAPS_PER_WEEK: '3', RATE_LIMIT_PER_MINUTE: '1000', REDIS_PREFIX: 'shared:' } });
  });
  after(async () => {
    await b.teardown({ keepDatabase: true });
    await a.teardown();
  });

  it('a token issued by one instance works on the other; readiness shows Redis', async () => {
    const token = await a.register();
    const res = await b.api('/v1/ai/substitutes', { ingredient: '1 cup cream', recipeTitle: 'Shared' }, { token });
    assert.equal(res.status, 200);
    assert.equal((await b.api('/readyz', undefined, { method: 'GET' })).body.redis, 'ok');
  });
  it('free-plan limits add up across instances', async () => {
    const token = await a.register();
    const swap = (instance, n) => instance.api('/v1/ai/substitutes', { ingredient: `${n} cups milk`, recipeTitle: 'Limits' }, { token });
    assert.equal((await swap(a, 1)).status, 200);
    assert.equal((await swap(b, 2)).status, 200);
    assert.equal((await swap(a, 3)).status, 200);
    assert.equal((await swap(b, 4)).status, 429);
    assert.equal((await swap(a, 5)).status, 429);
  });
  it('AI answers cached by one instance are served by the other', async () => {
    const token = await a.register();
    const body = { ingredient: '2 tbsp butter', recipeTitle: 'Shared cache', rules: {} };
    await a.api('/v1/ai/substitutes', body, { token });
    const before = b.ai.calls.length;
    const res = await b.api('/v1/ai/substitutes', body, { token });
    assert.equal(res.status, 200);
    assert.equal(b.ai.calls.length, before, 'instance B never called the AI');
  });
  it('rate limits are shared across instances', async () => {
    const strictA = await setup({ redisUrl, env: { RATE_LIMIT_PER_MINUTE: '4', REDIS_PREFIX: 'rl:' } });
    const strictB = await setup({ redisUrl, database: strictA.database, env: { RATE_LIMIT_PER_MINUTE: '4', REDIS_PREFIX: 'rl:' } });
    try {
      const token = await strictA.register();
      const statuses = [];
      for (let i = 0; i < 6; i += 1) statuses.push((await (i % 2 ? strictB : strictA).api('/v1/ai/plan', {}, { token })).status);
      assert.deepEqual(statuses, [400, 400, 400, 400, 429, 429]);
    } finally {
      await strictB.teardown({ keepDatabase: true });
      await strictA.teardown();
    }
  });
  it('migrations are safe when instances start together', async () => {
    const { migrate } = await import('../src/db.js');
    await Promise.all([migrate(a.deps.db), migrate(b.deps.db), migrate(a.deps.db)]);
    const [rows] = await a.deps.db.query('SELECT version FROM schema_migrations');
    assert.deepEqual(rows.map((r) => r.version).sort(), ['001_init.sql', '002_dishes.sql', '003_variations.sql'], 'each migration applied exactly once');
  });
});
