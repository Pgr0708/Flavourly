import crypto from 'node:crypto';
import compression from 'compression';
import express from 'express';
import helmet from 'helmet';
import { HttpError, log } from './util.js';
import { schemas, validate } from './validation.js';

/** Fixed-window counter in the shared cache, so limits hold across every instance and server. */
function rateLimit({ cache, name, limit, windowSeconds, key, message }) {
  return async (req, res, next) => {
    const bucket = Math.floor(Date.now() / 1000 / windowSeconds);
    const count = await cache.incr(`rl:${name}:${key(req)}:${bucket}`, windowSeconds + 5);
    res.setHeader('RateLimit-Limit', String(limit));
    res.setHeader('RateLimit-Remaining', String(Math.max(0, limit - count)));
    if (count > limit) {
      res.setHeader('Retry-After', String(windowSeconds - (Math.floor(Date.now() / 1000) % windowSeconds)));
      return next(new HttpError(429, message, { code: 'rate_limit' }));
    }
    next();
  };
}

export function createApp({ config, db, cache, devices, premium, usage, importer, assistant, images, discover, nutrition }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.TRUST_PROXY === 'false' ? false : config.TRUST_PROXY);
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(compression());

  app.use((req, res, next) => {
    const started = process.hrtime.bigint();
    const id = req.get('X-Request-Id')?.slice(0, 64) || crypto.randomUUID();
    res.setHeader('X-Request-Id', id);
    res.on('finish', () => {
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      if (req.path !== '/healthz') log.info('request', { id, method: req.method, path: req.path, status: res.statusCode, ms: Math.round(ms) });
    });
    next();
  });

  app.use(express.json({ limit: '300kb', strict: true }));

  app.get('/healthz', (_req, res) => res.json({ ok: true }));
  app.get('/readyz', async (_req, res) => {
    const database = await db.query('SELECT 1').then(() => 'ok', () => 'down');
    const redis = await cache.ping();
    res.status(database === 'ok' ? 200 : 503).json({ database, redis, cache: cache.backend, ai: config.OPENAI_API_KEY ? 'configured' : 'missing' });
  });
  app.use('/images', express.static(config.IMAGE_DIR, { maxAge: '30d', immutable: true, index: false, dotfiles: 'deny' }));

  const v1 = express.Router();
  const json = (handler) => async (req, res) => res.json(await handler(req));
  const metered = (feature, handler) => async (req, res) => {
    await usage.assertAllowed(req.device.id, feature, req.premium);
    const result = await handler(req);
    await usage.consume(req.device.id, feature, req.premium);
    res.json(result);
  };

  v1.post('/devices',
    rateLimit({ cache, name: 'register', limit: config.REGISTRATIONS_PER_HOUR, windowSeconds: 3600, key: (req) => req.ip, message: 'Too many new sessions from this network. Please try again later.' }),
    validate(schemas.device),
    json(async (req) => ({ token: await devices.register(req.body) })));

  // Everything below needs the anonymous device token.
  v1.use(async (req, _res, next) => {
    const token = /^Bearer (.+)$/.exec(req.get('Authorization') ?? '')?.[1];
    const device = await devices.authenticate(token);
    if (!device) return next(new HttpError(401, 'Your device session expired. Please try again.'));
    req.device = device;
    devices.touch(device).catch(() => {});
    next();
  });
  v1.use(rateLimit({ cache, name: 'device', limit: config.RATE_LIMIT_PER_MINUTE, windowSeconds: 60, key: (req) => req.device.id, message: 'Slow down a little — too many requests. Try again in a minute.' }));
  v1.use(async (req, _res, next) => {
    req.premium = await premium(req.get('X-RC-App-User'));
    next();
  });

  v1.post('/devices/erase', json(async (req) => {
    await devices.erase(req.device);
    return {};
  }));
  v1.post('/imports', validate(schemas.importLink), metered('importRecipe', (req) => importer.importLink(req.body)));
  v1.post('/ai/extract', validate(schemas.extract), metered('extract', (req) => importer.extractText(req.body)));
  v1.post('/ai/substitutes', validate(schemas.substitutes), metered('aiSwap', (req) => assistant.substitutes(req.body)));
  v1.post('/ai/cook-now', validate(schemas.cookNow), metered('aiIdeas', (req) => assistant.cookNow(req.body)));
  v1.post('/ai/plan', validate(schemas.plan), metered('aiPlan', (req) => assistant.plan(req.body)));
  v1.post('/usage', json((req) => usage.summary(req.device.id, req.premium)));
  // Verified nutrition (USDA, then Spoonacular). Cached per food, so it's free to call after edits.
  v1.post('/nutrition', validate(schemas.nutrition), json(async (req) => ({
    nutrition: await nutrition.forLines(req.body.lines, req.body.servings, { minCoverage: 0.5 }),
  })));
  // Shared, cached catalogue: free for everyone, no credit used.
  v1.post('/discover', validate(schemas.discover), json((req) => discover.local(req.body)));
  // Premium: full-length listening for a video the user picked (audio only, max TRANSCRIBE_MAX_MB).
  // Not metered per use; a per-device daily cap keeps the OpenAI bill bounded.
  v1.post('/ai/transcribe',
    (req, _res, next) => next(req.premium ? undefined : new HttpError(403, 'Listening to full videos is part of Premium.', { code: 'premium' })),
    rateLimit({ cache, name: 'transcribe', limit: config.TRANSCRIBE_PER_DAY, windowSeconds: 86_400, key: (req) => req.device.id, message: "You've listened to a lot of videos today. Try again tomorrow." }),
    express.raw({ type: ['audio/*', 'video/mp4'], limit: `${config.TRANSCRIBE_MAX_MB}mb` }),
    json((req) => importer.transcribe({ audio: req.body, mimeType: req.get('Content-Type') ?? '' })));
  v1.post('/images/recipe', validate(schemas.image), metered('aiImage', (req) => images.recipePhoto(req.body)));

  app.use('/v1', v1);
  app.use((_req, _res, next) => next(new HttpError(404, 'Not found.')));

  // eslint-disable-next-line no-unused-vars
  app.use((error, req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'That request is too large.' });
    if (error.type === 'entity.parse.failed') return res.status(400).json({ error: 'That request was not valid JSON.' });
    const known = error instanceof HttpError;
    const status = known ? error.status : 500;
    if (!known) log.error('unhandled error', { path: req.path, error: error.message, stack: error.stack?.split('\n').slice(0, 4).join(' | ') });
    res.status(status).json({ error: known ? error.message : 'Something went wrong on our side. Please try again.', ...(known ? error.extra : {}) });
  });

  return app;
}
