import Redis from 'ioredis';
import { log } from './util.js';

/** In-process LRU with expiry: the fallback when Redis is not configured or is down. */
class MemoryStore {
  constructor(maxEntries = 5_000) {
    this.max = maxEntries;
    this.map = new Map();
  }

  #live(key) {
    const entry = this.map.get(key);
    if (!entry) return undefined;
    if (entry.expires <= Date.now()) {
      this.map.delete(key);
      return undefined;
    }
    this.map.delete(key); // refresh LRU position
    this.map.set(key, entry);
    return entry;
  }

  get(key) {
    return this.#live(key)?.value ?? null;
  }

  set(key, value, ttlSeconds) {
    this.map.set(key, { value, expires: Date.now() + ttlSeconds * 1000 });
    while (this.map.size > this.max) this.map.delete(this.map.keys().next().value);
  }

  incr(key, ttlSeconds) {
    const entry = this.#live(key);
    const value = (entry ? Number(entry.value) : 0) + 1;
    this.map.set(key, { value: String(value), expires: entry?.expires ?? Date.now() + ttlSeconds * 1000 });
    return value;
  }

  del(key) {
    this.map.delete(key);
  }
}

/**
 * JSON cache + counters shared by every instance through Redis. Every key gets REDIS_PREFIX so this
 * app can share a Redis server with other projects without touching their keys. If Redis is
 * unreachable each call quietly falls back to memory, so the API keeps working (just less shared).
 */
export function createCache({ url = '', prefix = 'flavourly:' } = {}) {
  const memory = new MemoryStore();
  let redis = null;
  let healthy = false;

  if (url) {
    redis = new Redis(url, {
      keyPrefix: prefix,
      lazyConnect: false,
      enableOfflineQueue: false,
      maxRetriesPerRequest: 1,
      connectTimeout: 3_000,
      retryStrategy: (times) => Math.min(times * 500, 5_000),
    });
    redis.on('ready', () => {
      healthy = true;
      log.info('redis connected');
    });
    redis.on('error', (error) => {
      if (healthy) log.warn('redis error, using memory cache', { error: error.message });
      healthy = false;
    });
    redis.on('end', () => {
      healthy = false;
    });
  }

  const useRedis = () => redis && healthy;

  return {
    get backend() {
      return useRedis() ? 'redis' : 'memory';
    },

    async get(key) {
      try {
        const raw = useRedis() ? await redis.get(key) : memory.get(key);
        return raw == null ? null : JSON.parse(raw);
      } catch {
        const raw = memory.get(key);
        return raw == null ? null : JSON.parse(raw);
      }
    },

    async set(key, value, ttlSeconds) {
      const raw = JSON.stringify(value);
      try {
        if (useRedis()) await redis.set(key, raw, 'EX', Math.max(1, Math.round(ttlSeconds)));
        else memory.set(key, raw, ttlSeconds);
      } catch {
        memory.set(key, raw, ttlSeconds);
      }
    },

    /** Atomic counter that expires `ttlSeconds` after it was created (rate limits). */
    async incr(key, ttlSeconds) {
      try {
        if (useRedis()) {
          // SET NX + INCR works on Redis 2.6+ (Ubuntu's apt Redis 6 included); EXPIRE NX needs Redis 7.
          const [, [, count]] = await redis.multi().set(key, 0, 'EX', ttlSeconds, 'NX').incr(key).exec();
          return Number(count);
        }
      } catch {
        // fall through to memory
      }
      return memory.incr(key, ttlSeconds);
    },

    async del(key) {
      memory.del(key);
      try {
        if (useRedis()) await redis.del(key);
      } catch {
        // memory copy is gone; Redis entry expires on its own
      }
    },

    /** Takes a short lock shared by every instance; false when someone else holds it. */
    async lock(key, ttlSeconds) {
      try {
        if (useRedis()) return (await redis.set(key, '1', 'EX', ttlSeconds, 'NX')) === 'OK';
      } catch {
        // fall through to the local lock
      }
      if (memory.get(key) != null) return false;
      memory.set(key, '1', ttlSeconds);
      return true;
    },

    /** Cache-aside helper: returns the cached value or computes, stores and returns it. */
    async wrap(key, ttlSeconds, compute) {
      const hit = await this.get(key);
      if (hit != null) return { value: hit, cached: true };
      const value = await compute();
      if (value != null) await this.set(key, value, ttlSeconds);
      return { value, cached: false };
    },

    async ping() {
      if (!redis) return 'disabled';
      try {
        return (await redis.ping()) === 'PONG' ? 'ok' : 'down';
      } catch {
        return 'down';
      }
    },

    async close() {
      if (redis) await redis.quit().catch(() => redis.disconnect());
    },
  };
}
