import { createOpenAI } from './ai/openai.js';
import { createApp } from './app.js';
import { createCache } from './cache.js';
import { createPool } from './db.js';
import { createFetcher } from './fetcher.js';
import { createAssistant, createDevices, createDiscover, createImages, createImporter, createPremium, createUsage } from './services.js';

/** Builds every dependency from config. Tests pass their own config and may swap the fetcher or clock. */
export function build(config, { fetcher: customFetcher, now } = {}) {
  const db = createPool(config);
  const cache = createCache({ url: config.REDIS_URL, prefix: config.REDIS_PREFIX });
  const ai = createOpenAI({ apiKey: config.OPENAI_API_KEY, model: config.OPENAI_MODEL, baseUrl: config.OPENAI_BASE_URL, timeoutMs: config.OPENAI_TIMEOUT_MS });
  const fetcher = customFetcher ?? createFetcher({ userAgent: config.FETCH_USER_AGENT });
  const deps = {
    config, db, cache, ai, fetcher,
    devices: createDevices({ db, cache }),
    premium: createPremium({ config, cache }),
    usage: createUsage({ db, config, ...(now ? { now } : {}) }),
    importer: createImporter({ config, fetcher, ai, cache }),
    assistant: createAssistant({ ai, cache }),
    images: createImages({ config, ai }),
  };
  deps.discover = createDiscover({ ai, cache, config, images: deps.images });
  return { ...deps, app: createApp(deps) };
}
