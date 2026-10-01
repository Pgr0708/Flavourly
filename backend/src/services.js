import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { LOCAL_GROUPS, imagePrompt, localTasks, tasks } from './ai/tasks.js';
import { readPage } from './parsers/jsonld.js';
import { canonicalize, captionFromMeta, findLinks, PLATFORM_NAMES, platformOf, youtubeId } from './parsers/social.js';
import { toDraft } from './recipe.js';
import { HttpError, dayStart, log, sha256, weekStart } from './util.js';
import { cleanText, countryName } from './validation.js';

const DAY = 86_400;
const short = (value, max) => {
  const text = cleanText(value == null ? '' : String(value)).slice(0, max).trim();
  return text || undefined;
};

// ─── Devices (anonymous, no login) ──────────────────────────────────────────────────────────

export function createDevices({ db, cache }) {
  return {
    /** Same install → same row (so free limits survive reinstalls); a new token every time. */
    async register({ installID, platform, appVersion }) {
      const token = crypto.randomBytes(32).toString('base64url');
      const hash = sha256(token);
      const [[existing]] = await db.query('SELECT id, token_hash FROM devices WHERE install_id = ?', [installID]);
      const update = () => db.query(
        'UPDATE devices SET token_hash = ?, platform = ?, app_version = ?, last_seen_at = CURRENT_TIMESTAMP(3) WHERE install_id = ?',
        [hash, platform, appVersion, installID],
      );
      if (existing) {
        await update();
        await cache.del(`dev:${existing.token_hash}`);
      } else {
        try {
          await db.query('INSERT INTO devices (install_id, token_hash, platform, app_version) VALUES (?, ?, ?, ?)', [installID, hash, platform, appVersion]);
        } catch (error) {
          if (error.code !== 'ER_DUP_ENTRY') throw error;
          await update(); // two first launches raced; the later token wins
        }
      }
      return token;
    },

    async authenticate(token) {
      if (!/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) return null;
      const hash = sha256(token);
      const cached = await cache.get(`dev:${hash}`);
      if (cached) return cached;
      const [[row]] = await db.query('SELECT id FROM devices WHERE token_hash = ?', [hash]);
      if (!row) return null;
      const device = { id: Number(row.id), hash };
      await cache.set(`dev:${hash}`, device, 600);
      return device;
    },

    /** last_seen_at at most once an hour per device, so busy devices don't hammer MySQL. */
    async touch(device) {
      if ((await cache.incr(`seen:${device.id}`, 3600)) === 1) {
        await db.query('UPDATE devices SET last_seen_at = CURRENT_TIMESTAMP(3) WHERE id = ?', [device.id]).catch(() => {});
      }
    },

    async erase(device) {
      await db.query('DELETE FROM devices WHERE id = ?', [device.id]);
      await cache.del(`dev:${device.hash}`);
    },
  };
}

// ─── Premium (RevenueCat) ───────────────────────────────────────────────────────────────────

export function createPremium({ config, cache }) {
  return async function isPremium(appUserId) {
    if (!config.REVENUECAT_SECRET_KEY || !appUserId || !/^[\w$:.@-]{1,128}$/.test(appUserId)) return false;
    const key = `rc:${sha256(appUserId)}`;
    const fresh = await cache.get(key);
    if (fresh) return fresh.premium;
    try {
      const response = await fetch(`${config.REVENUECAT_BASE_URL}/subscribers/${encodeURIComponent(appUserId)}`, {
        headers: { Authorization: `Bearer ${config.REVENUECAT_SECRET_KEY}` },
        signal: AbortSignal.timeout(5_000),
      });
      if (!response.ok) throw new Error(`RevenueCat answered ${response.status}`);
      const body = await response.json();
      const entitlement = body?.subscriber?.entitlements?.[config.REVENUECAT_ENTITLEMENT];
      const premium = Boolean(entitlement && (!entitlement.expires_date || Date.parse(entitlement.expires_date) > Date.now()));
      await cache.set(key, { premium }, 900);
      await cache.set(`${key}:stale`, { premium }, DAY);
      return premium;
    } catch (error) {
      log.warn('premium check failed, using last known state', { error: error.message });
      return (await cache.get(`${key}:stale`))?.premium ?? false;
    }
  };
}

// ─── Free-plan limits ───────────────────────────────────────────────────────────────────────

export const FEATURES = {
  importRecipe: { period: 'week', limit: 'FREE_IMPORTS_PER_WEEK', label: 'link imports' },
  aiPlan: { period: 'week', limit: 'FREE_AI_PLANS_PER_WEEK', label: 'AI meal plans' },
  aiIdeas: { period: 'week', limit: 'FREE_AI_IDEAS_PER_WEEK', label: 'AI recipe ideas' },
  aiSwap: { period: 'week', limit: 'FREE_AI_SWAPS_PER_WEEK', label: 'AI swaps' },
  aiImage: { period: 'week', limit: 'FREE_IMAGES_PER_WEEK', label: 'AI photos' },
  extract: { period: 'day', limit: 'FREE_EXTRACTS_PER_DAY', label: 'AI recipe reads' },
};

export function createUsage({ db, config, now = () => new Date() }) {
  const period = (feature) => (FEATURES[feature].period === 'week' ? weekStart(now()) : dayStart(now()));
  const limitOf = (feature) => config[FEATURES[feature].limit];

  return {
    async used(deviceId, feature) {
      const [[row]] = await db.query('SELECT used FROM usage_counters WHERE device_id = ? AND feature = ? AND period_start = ?', [deviceId, feature, period(feature)]);
      return row ? Number(row.used) : 0;
    },

    /** Checked before the work; only successful work is counted (failures never cost a free use). */
    async assertAllowed(deviceId, feature, premium) {
      if (premium) return;
      const limit = limitOf(feature);
      if ((await this.used(deviceId, feature)) < limit) return;
      const { label, period: span } = FEATURES[feature];
      throw new HttpError(429, span === 'week'
        ? `You've used this week's ${limit} free ${label}. They reset on Monday — or go Premium for unlimited.`
        : `You've used today's ${limit} free ${label}. Try again tomorrow — or go Premium for unlimited.`, { code: 'limit' });
    },

    async consume(deviceId, feature, premium) {
      if (premium) return;
      try {
        await db.query(
          'INSERT INTO usage_counters (device_id, feature, period_start, used) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE used = used + 1',
          [deviceId, feature, period(feature)],
        );
      } catch (error) {
        if (String(error.code).startsWith('ER_NO_REFERENCED_ROW')) throw new HttpError(401, 'Your device session expired. Please try again.');
        throw error;
      }
    },
  };
}

// ─── Recipe import (links, pasted text, OCR, transcripts) ───────────────────────────────────

export function createImporter({ config, fetcher, ai, cache }) {
  const complete = (recipe) => Boolean(recipe?.ingredients?.length && recipe?.steps?.length);

  async function extract({ text, kind, sourceURL }) {
    const key = `extract:v2:${sha256(`${kind}|${sourceURL ?? ''}|${text}`)}`;
    const { value } = await cache.wrap(key, 7 * DAY, () => ai.json(tasks.extract({ text, kind, sourceURL })));
    if (!value?.found || !value.recipe?.ingredients?.length) {
      throw new HttpError(422, "We couldn't find a recipe in that. Try pasting the recipe text, or a screenshot of it.");
    }
    return { recipe: value.recipe, notes: value.notes ?? [] };
  }

  async function website(url) {
    const page = await fetcher.fetchPage(url);
    if (page.status >= 400) throw new HttpError(422, page.status === 404 ? 'That page no longer exists.' : "That site didn't let us read the page.");
    return { finalUrl: page.url, ...readPage(page.body) };
  }

  /** Public caption / description only — never the video file, never comments. */
  async function post(url, platform) {
    if (platform === 'tiktok') {
      const embed = await fetcher.fetchJson(`https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`);
      return { caption: embed.title ?? '', title: '', author: embed.author_name, image: embed.thumbnail_url };
    }
    if (platform === 'youtube') {
      const id = youtubeId(url);
      if (config.YOUTUBE_API_KEY && id) {
        const data = await fetcher.fetchJson(`https://www.googleapis.com/youtube/v3/videos?part=snippet&id=${encodeURIComponent(id)}&key=${config.YOUTUBE_API_KEY}`);
        const snippet = data.items?.[0]?.snippet;
        if (!snippet) throw new HttpError(404, 'That video is private, deleted or unavailable.');
        return { caption: snippet.description ?? '', title: snippet.title, author: snippet.channelTitle, image: snippet.thumbnails?.high?.url };
      }
      const embed = await fetcher.fetchJson(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}`);
      const page = await fetcher.fetchPage(url).then((p) => readPage(p.body).page).catch(() => null);
      return { caption: page?.description ?? '', title: embed.title, author: embed.author_name, image: embed.thumbnail_url };
    }
    const page = await website(url);
    return { caption: captionFromMeta(page.page.description), title: page.page.title, author: null, image: page.page.image, recipe: page.recipe };
  }

  function reply(recipe, { via, notes = [], ...extras }) {
    const draft = toDraft(recipe, { ...extras, method: 'link' });
    if (!draft.title) draft.title = extras.sourceName ? `Recipe from ${extras.sourceName}` : 'Imported recipe';
    const allNotes = [...notes];
    if (!draft.steps.length) allNotes.push('The steps weren’t in the post — add them from a screenshot or by pasting them.');
    return { recipe: draft, via, notes: allNotes.map((note) => short(note, 200)).filter(Boolean).slice(0, 5) };
  }

  async function fresh(url, platform, pageText) {
    const name = PLATFORM_NAMES[platform] ?? new URL(url).hostname.replace(/^www\./, '');
    if (platform === 'web') {
      let page = null;
      if (!pageText) {
        page = await website(url);
        if (complete(page.recipe)) {
          return reply(page.recipe, { via: 'recipe card', sourceURL: page.finalUrl, sourceName: page.page.siteName ?? name, imageURL: page.recipe.imageURL ?? page.page.image });
        }
      }
      const text = (pageText ?? page.text ?? '').slice(0, 15_000);
      if (text.length < 40) throw new HttpError(422, "That page didn't include a recipe we could read. Try pasting the recipe text.");
      const found = await extract({ text, kind: 'text', sourceURL: url });
      const base = page?.recipe ?? {};
      return reply({ ...base, ...found.recipe, title: found.recipe.title || base.title, imageURL: base.imageURL },
        { via: 'page', notes: found.notes, sourceURL: url, sourceName: page?.page.siteName ?? name, imageURL: page?.page.image });
    }

    const shared = await post(url, platform);
    if (complete(shared.recipe)) return reply(shared.recipe, { via: 'recipe card', sourceURL: url, sourceName: name, imageURL: shared.image });

    // A recipe website linked from the caption beats reading the caption itself.
    for (const link of findLinks(shared.caption)) {
      try {
        const site = await website(link);
        if (complete(site.recipe)) {
          const host = new URL(link).hostname.replace(/^www\./, '');
          return reply(site.recipe, {
            via: "creator's website", sourceURL: site.finalUrl, sourceName: site.page.siteName ?? host,
            creator: shared.author, imageURL: site.recipe.imageURL ?? shared.image, notes: [`Found on ${host}, linked from the ${name} post`],
          });
        }
      } catch {
        // try the next link, then the caption
      }
    }

    const caption = [shared.title, shared.caption].filter(Boolean).join('\n').trim();
    if (caption.length < 20) {
      throw new HttpError(422, `${name} didn't share a caption for this post. If it's public, copy the caption and paste it in the Text tab.`);
    }
    const found = await extract({ text: caption.slice(0, 12_000), kind: 'caption', sourceURL: url });
    return reply(found.recipe, {
      via: platform === 'youtube' ? 'description' : 'caption', notes: found.notes,
      sourceURL: url, sourceName: name, creator: shared.author, imageURL: shared.image,
    });
  }

  return {
    async importLink({ url, pageText }) {
      const canonical = canonicalize(url);
      const platform = platformOf(canonical);
      const key = `import:v1:${sha256(`${canonical}|${pageText ? sha256(pageText) : ''}`)}`;
      const { value } = await cache.wrap(key, 7 * DAY, () => fresh(canonical, platform, pageText));
      return value;
    },

    async extractText({ text, kind, sourceURL }) {
      const found = await extract({ text, kind, sourceURL });
      return { recipe: toDraft(found.recipe, { sourceURL, method: kind === 'ocr' ? 'scan' : kind }), notes: found.notes.slice(0, 5) };
    },
  };
}

// ─── AI helpers: swaps, Cook Now, planner ───────────────────────────────────────────────────

export function createAssistant({ ai, cache }) {
  const lower = (value) => String(value).toLowerCase();
  return {
    async substitutes(request) {
      const key = `swap:v1:${sha256(JSON.stringify([lower(request.ingredient), lower(request.recipeTitle), request.otherIngredients, request.rules]))}`;
      const { value } = await cache.wrap(key, 30 * DAY, async () => {
        const result = await ai.json(tasks.substitutes(request));
        const options = (result.options ?? []).map((option) => JSON.parse(JSON.stringify({
          name: short(option.name, 60),
          amount: short(option.amount, 40) ?? '',
          why: short(option.why, 200) ?? '',
          flavour: short(option.flavour, 80),
          texture: short(option.texture, 80),
          nutrition: short(option.nutrition, 80),
          tag: short(option.tag, 30),
        }))).filter((option) => option.name && lower(option.name) !== lower(request.ingredient));
        return { options: options.slice(0, 6) };
      });
      return value;
    },

    async cookNow(request) {
      const key = `cooknow:v1:${sha256(JSON.stringify(request))}`;
      const { value } = await cache.wrap(key, 6 * 3600, async () => {
        const result = await ai.json(tasks.cookNow({ ...request, country: request.country ? countryName(request.country) : null }));
        const avoid = new Set(request.avoidTitles.map(lower));
        const ideas = (result.ideas ?? []).map((idea) => ({
          recipe: toDraft(idea.recipe, { method: 'ai', servings: idea.recipe?.servings ?? request.servings }),
          reason: short(idea.reason, 160),
        })).filter(({ recipe }) => recipe.title && recipe.ingredients.length >= 2 && recipe.steps.length >= 1
          && !avoid.has(lower(recipe.title))
          && (!request.minutes || !recipe.totalMinutes || recipe.totalMinutes <= request.minutes + 5));
        return { ideas: ideas.slice(0, 3).map((idea) => JSON.parse(JSON.stringify(idea))) };
      });
      return value;
    },

    /** Not cached: asking again should give a fresh week. Picks outside each slot's shortlist are dropped. */
    async plan(request) {
      const result = await ai.json(tasks.plan(request));
      const allowed = new Map(request.slots.map((slot) => [`${slot.date}|${slot.slot}`, new Set(slot.candidates)]));
      const seen = new Set();
      const picks = [];
      for (const pick of result.picks ?? []) {
        const slotKey = `${pick.date}|${pick.slot}`;
        if (seen.has(slotKey) || !allowed.get(slotKey)?.has(pick.recipeId)) continue;
        seen.add(slotKey);
        picks.push(JSON.parse(JSON.stringify({ date: pick.date, slot: pick.slot, recipeId: pick.recipeId, reason: short(pick.reason, 100) })));
      }
      return { picks };
    },
  };
}

// ─── AI recipe photos (optional) ────────────────────────────────────────────────────────────

export function createImages({ config, ai }) {
  const locate = (title) => {
    const name = `${sha256(title.toLowerCase()).slice(0, 32)}.jpg`;
    return { file: path.join(config.IMAGE_DIR, name), url: `${config.PUBLIC_URL.replace(/\/$/, '')}/images/${name}` };
  };
  const exists = (file) => fs.access(file).then(() => true, () => false);

  return {
    /** URL of an already generated photo for this title, or null. Free: no AI call. */
    async existing(title) {
      const { file, url } = locate(title);
      return (await exists(file)) ? url : null;
    },

    async recipePhoto({ title, description }) {
      if (!config.IMAGE_GENERATION) throw new HttpError(501, "Photo creation isn't turned on for this server.");
      const { file, url } = locate(title);
      if (await exists(file)) return { url };
      const bytes = await ai.image({ prompt: imagePrompt({ title, description }), model: config.IMAGE_MODEL, quality: config.IMAGE_QUALITY });
      await fs.mkdir(config.IMAGE_DIR, { recursive: true });
      const temp = `${file}.${process.pid}.tmp`;
      await fs.writeFile(temp, bytes);
      await fs.rename(temp, file);
      return { url };
    },
  };
}

// ─── Local food: popular home dishes per country ───────────────────────────────────────────

/**
 * One catalogue per country, built by AI once and shared by every user through Redis (30 days),
 * so cost does not grow with users. Photos are painted in the background, one at a time, by
 * whichever instance holds the lock; each request reports the photos that exist so far.
 * Diets and allergies are applied in the app with FoodRules, because the catalogue is shared.
 */
export function createDiscover({ ai, cache, config, images }) {
  const building = new Map(); // country → in-flight build in this process (avoids duplicate AI calls)
  const slug = (title) => title.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);
  const words = (list, max, length) => [...new Set((list ?? []).map((item) => short(item, length)).filter(Boolean))].slice(0, max);

  async function build(code, country) {
    const [kitchen, ...groups] = await Promise.allSettled([
      ai.json(localTasks.kitchen({ country })),
      ...LOCAL_GROUPS.map((group) => ai.json(localTasks.dishes({ country, ...group }))),
    ]);
    const cuisine = (kitchen.status === 'fulfilled' && short(kitchen.value.cuisine, 40)) || country;
    const seen = new Set();
    const dishes = [];
    for (const group of groups) {
      if (group.status !== 'fulfilled') continue;
      for (const { recipe, region } of group.value.dishes ?? []) {
        const draft = toDraft(recipe, { method: 'local', cuisine });
        const key = slug(draft.title ?? '');
        if (!key || seen.has(key) || draft.ingredients.length < 2 || draft.steps.length < 1) continue;
        seen.add(key);
        const where = short(region, 30);
        if (where && !draft.tags.includes(where)) draft.tags = [where, ...draft.tags].slice(0, 20);
        dishes.push({ ...draft, remoteID: `local-${code.toLowerCase()}-${key}` });
      }
    }
    if (dishes.length < 6) {
      const failed = groups.find((group) => group.status === 'rejected');
      throw failed?.reason instanceof HttpError ? failed.reason : new HttpError(502, `We couldn't load dishes from ${country} right now. Please try again.`);
    }
    return {
      country: code,
      name: country,
      cuisine,
      staples: kitchen.status === 'fulfilled' ? words(kitchen.value.staples, 30, 40) : [],
      cravings: kitchen.status === 'fulfilled' ? words(kitchen.value.cravings, 12, 30) : [],
      dishes,
    };
  }

  async function paint(catalog) {
    if (!(await cache.lock(`discover:paint:${catalog.country}`, 20 * 60))) return; // another worker is on it
    for (const dish of catalog.dishes) {
      if (await images.existing(dish.title)) continue;
      try {
        await images.recipePhoto({ title: dish.title, description: [dish.summary, `${catalog.cuisine} home cooking`].filter(Boolean).join(' — ') });
      } catch (error) {
        log.warn('local photo failed', { country: catalog.country, title: dish.title, error: error.message });
        if (error.status === 503 || error.status === 501) break; // AI down or photos off: stop, retry on a later request
      }
    }
    await cache.del(`discover:paint:${catalog.country}`);
  }

  return {
    async local({ country: code }) {
      const country = countryName(code);
      const key = `discover:v1:${code}`;
      let value = await cache.get(key);
      if (!value) {
        if (!building.has(code)) {
          building.set(code, cache.wrap(key, 30 * DAY, () => build(code, country)).finally(() => building.delete(code)));
        }
        value = (await building.get(code)).value;
      }
      const dishes = await Promise.all(value.dishes.map(async (dish) => ({ ...dish, imageURL: (await images.existing(dish.title)) ?? dish.imageURL })));
      if (config.IMAGE_GENERATION && dishes.some((dish) => !dish.imageURL)) {
        paint(value).catch((error) => log.warn('local photos stopped', { country: code, error: error.message }));
      }
      return { ...value, dishes };
    },
  };
}
