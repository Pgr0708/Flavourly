import { fileURLToPath } from 'node:url';
import path from 'node:path';
import dotenv from 'dotenv';
import { z } from 'zod';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const flag = z.enum(['0', '1', 'true', 'false']).default('0').transform((v) => v === '1' || v === 'true');
const int = (fallback, min, max) => z.coerce.number().int().min(min).max(max).default(fallback);

const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  // Bind to localhost only: Nginx is the single public entry point.
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: int(8080, 1, 65535),
  PUBLIC_URL: z.string().url().default('http://localhost:8080'),
  TRUST_PROXY: z.string().default('loopback'),

  DB_HOST: z.string().min(1).default('127.0.0.1'),
  DB_PORT: int(3306, 1, 65535),
  DB_SOCKET: z.string().default(''),
  DB_USER: z.string().min(1).default('flavourly_app'),
  DB_PASSWORD: z.string().default(''),
  DB_NAME: z.string().regex(/^[A-Za-z0-9_]+$/, 'DB_NAME may only contain letters, digits and _').default('flavourly'),
  DB_POOL_SIZE: int(5, 1, 100),

  // Empty = in-process cache only (fine for one instance; use Redis for clusters / several servers).
  REDIS_URL: z.string().default(''),
  REDIS_PREFIX: z.string().min(1).default('flavourly:'),

  OPENAI_API_KEY: z.string().default(''),
  OPENAI_MODEL: z.string().min(1).default('gpt-4o-mini'),
  OPENAI_BASE_URL: z.string().url().default('https://api.openai.com/v1'),
  OPENAI_TIMEOUT_MS: int(45_000, 1_000, 180_000),

  YOUTUBE_API_KEY: z.string().default(''),
  FETCH_USER_AGENT: z.string().min(1).default('Mozilla/5.0 (compatible; FlavourlyBot/1.0; +https://flavourly.dakshyaminfotech.store)'),

  REVENUECAT_SECRET_KEY: z.string().default(''),
  REVENUECAT_ENTITLEMENT: z.string().min(1).default('premium'),
  REVENUECAT_BASE_URL: z.string().url().default('https://api.revenuecat.com/v1'),

  IMAGE_GENERATION: flag,
  IMAGE_MODEL: z.string().min(1).default('gpt-image-1'),
  // low ≈ $0.01, medium ≈ $0.04, high ≈ $0.17 per 1024×1024 photo (gpt-image-1).
  IMAGE_QUALITY: z.enum(['low', 'medium', 'high']).default('low'),
  IMAGE_DIR: z.string().default(path.join(ROOT, 'public', 'images')),

  FREE_IMPORTS_PER_WEEK: int(5, 0, 10_000),
  FREE_AI_PLANS_PER_WEEK: int(1, 0, 10_000),
  FREE_AI_IDEAS_PER_WEEK: int(5, 0, 10_000),
  FREE_AI_SWAPS_PER_WEEK: int(10, 0, 10_000),
  FREE_IMAGES_PER_WEEK: int(3, 0, 10_000),
  FREE_EXTRACTS_PER_DAY: int(20, 0, 10_000),
  RATE_LIMIT_PER_MINUTE: int(60, 1, 100_000),
  REGISTRATIONS_PER_HOUR: int(20, 1, 100_000),
});

/** Reads backend/.env (wherever PM2 starts us from), validates everything, fails fast with a readable list. */
export function loadConfig(env = undefined) {
  if (!env) {
    dotenv.config({ path: path.join(ROOT, '.env'), quiet: true });
    env = process.env;
  }
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((issue) => `  ${issue.path.join('.')}: ${issue.message}`).join('\n');
    throw new Error(`Invalid configuration in backend/.env:\n${problems}`);
  }
  const config = parsed.data;
  if (config.NODE_ENV === 'production' && !config.OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY is required in production (backend/.env).');
  }
  return Object.freeze(config);
}
