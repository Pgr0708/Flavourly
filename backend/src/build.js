import { createOpenAI } from './ai/openai.js';
import { createApp } from './app.js';
import { createDishes } from './dishes.js';
import { createVariations } from './variations.js';
import { createCache } from './cache.js';
import { createPool } from './db.js';
import { createFetcher } from './fetcher.js';
import { createNutrition } from './nutrition.js';
import { createAssistant, createDevices, createDiscover, createImages, createImporter, createPremium, createUsage } from './services.js';

/** Builds every dependency from config. Tests pass their own config and may swap the fetcher or clock. */
export function build(config, { fetcher: customFetcher, now, http } = {}) {
  const db = createPool(config);
  const cache = createCache({ url: config.REDIS_URL, prefix: config.REDIS_PREFIX });
  const ai = createOpenAI({ apiKey: config.OPENAI_API_KEY, model: config.OPENAI_MODEL, baseUrl: config.OPENAI_BASE_URL, timeoutMs: config.OPENAI_TIMEOUT_MS });
  const fetcher = customFetcher ?? createFetcher({ userAgent: config.FETCH_USER_AGENT });
  const nutrition = createNutrition({ config, cache, ...(http ? { http } : {}) });
  const deps = {
    config, db, cache, ai, fetcher, nutrition,
    devices: createDevices({ db, cache }),
    premium: createPremium({ config, cache }),
    usage: createUsage({ db, config, ...(now ? { now } : {}) }),
    importer: createImporter({ config, fetcher, ai, cache, nutrition }),
    assistant: createAssistant({ ai, cache, nutrition }),
    images: createImages({ config, ai, cache, fetcher }),
  };
  deps.discover = createDiscover({ ai, cache, config, images: deps.images, fetcher, nutrition });
  deps.dishes = createDishes({ db, ai, cache, config, fetcher, nutrition, images: deps.images, usage: deps.usage });
  deps.variations = createVariations({ db, ai, nutrition, images: deps.images, usage: deps.usage });
  return { ...deps, app: createApp(deps) };
}
