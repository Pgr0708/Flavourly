// Dish search for any dish in the world: autocomplete from each country's popular dish names, and recipes
// from a shared library — found once (TheMealDB, else AI) and then reused by every user, so the same dish is
// never paid for twice.
import { dishTasks, expandTask } from './ai/tasks.js';
import { parseLine } from './nutrition.js';
import { toDraft } from './recipe.js';
import { createSources, isThin } from './sources.js';
import { describesDish } from './services.js';
import { HttpError, log } from './util.js';
import { cleanText, countryName } from './validation.js';

const DAY = 86_400;

/**
 * Spelling-tolerant key: "Aloo Poori", "alu puri" and "ALOO PURI" all become "alu puri".
 * Folds accents and the usual transliteration variants (oo/u, ee/i, aa/a, w/v, ph/f, doubled consonants).
 */
export function soundKey(text) {
  return cleanText(String(text ?? '')).toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/\([^)]*\)/g, ' ').replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/oo/g, 'u').replace(/ee/g, 'i').replace(/aa/g, 'a').replace(/w/g, 'v').replace(/ph/g, 'f')
    .replace(/([b-df-hj-np-tv-z])\1/g, '$1')
    .replace(/\s+/g, ' ').trim();
}

export const dishSlug = (name) => soundKey(name).replace(/ /g, '-').slice(0, 120);

/** How well a dish name answers what was typed: 3 starts with it, 2 a word starts with it, 1 contains it. */
export function matchScore(query, name) {
  const q = soundKey(query);
  const n = soundKey(name);
  if (!q || !n) return 0;
  if (n.startsWith(q)) return 3;
  if (n.split(' ').some((word) => word.startsWith(q))) return 2;
  return q.length >= 3 && n.includes(q) ? 1 : 0;
}

/** TheMealDB meal → the app's recipe shape. */
function mealToRecipe(meal) {
  const ingredients = [];
  for (let i = 1; i <= 20; i += 1) {
    const name = cleanText(meal[`strIngredient${i}`] ?? '');
    if (!name) continue;
    const text = cleanText(`${meal[`strMeasure${i}`] ?? ''} ${name}`);
    const parsed = parseLine(text);
    ingredients.push({ text, quantity: parsed.quantity, unit: parsed.unit, name: parsed.name || name, confidence: parsed.quantity ? 0.9 : 0.6 });
  }
  const steps = String(meal.strInstructions ?? '').split(/\r?\n+|(?<=\.)\s+(?=step\s*\d+)/i)
    .map((line) => cleanText(line.replace(/^(step\s*)?\d+[.):]?\s*/i, ''))).filter((line) => line.length > 3)
    .map((text) => ({ text, timerSeconds: Number(/(\d+)\s*min/i.exec(text)?.[1] ?? 0) * 60 || null, confidence: 0.9 }));
  return {
    title: meal.strMeal, cuisine: meal.strArea && meal.strArea !== 'Unknown' ? meal.strArea : null, servings: 4,
    tags: String(meal.strTags ?? '').split(',').map((t) => t.trim()).filter(Boolean).slice(0, 5),
    imageURL: meal.strMealThumb, ingredients, steps,
  };
}

export function createDishes({ db, ai, cache, config, fetcher, nutrition = { enrich: async (draft) => draft }, images, usage }) {
  const building = new Map();
  const sources = createSources({ config, cache, fetcher });

  /** ~200 popular dish names for a country, built once by AI and shared for 90 days. */
  async function countryNames(code, premium) {
    const key = `dishnames:v1:${code}`;
    const cached = await cache.get(key);
    if (cached) return cached;
    if (!premium) return []; // a new country's list is built by AI: a Premium cook unlocks it for everyone
    if (!building.has(key)) {
      building.set(key, cache.wrap(key, 90 * DAY, async () => {
        const result = await ai.json(dishTasks.names({ country: countryName(code) }));
        const seen = new Set();
        return (result.dishes ?? []).map((d) => ({ name: cleanText(d.name ?? '').slice(0, 80), region: cleanText(d.region ?? '').slice(0, 40) || null }))
          .filter((d) => d.name && !/^(null|none)$/i.test(d.name) && !seen.has(soundKey(d.name)) && seen.add(soundKey(d.name)))
          .map((d) => ({ ...d, region: /^(null|none|n\/?a)$/i.test(d.region ?? '') ? null : d.region }));
      }).finally(() => building.delete(key)));
    }
    return (await building.get(key)).value;
  }

  /**
   * Where a new dish comes from, cheapest and most trusted first: TheMealDB → Wikibooks Cookbook (both saved
   * and shared) → Spoonacular (live only, never saved — their terms) → AI with the stronger dish model, plus a
   * second "write it out in full" pass when the first answer is too short.
   */
  async function build(slug, name, code, region, { deviceId, premium }) {
    let draft = null;
    let source = 'themealdb';
    try {
      const data = await fetcher.fetchJson(`https://www.themealdb.com/api/json/v1/${encodeURIComponent(config.THEMEALDB_API_KEY)}/search.php?s=${encodeURIComponent(name)}`);
      const meal = (data?.meals ?? []).find((m) => soundKey(m.strMeal) === soundKey(name) || describesDish(name, m.strMeal));
      if (meal) draft = toDraft(mealToRecipe(meal), { method: 'search', sourceName: 'TheMealDB' });
    } catch (error) {
      log.warn('themealdb search failed', { name, error: error.message });
    }
    if (!draft || draft.ingredients.length < 2) {
      draft = await sources.wikibooks(name);
      source = 'wikibooks';
    }
    if (!draft) {
      const live = await sources.spoonacular(name, slug);
      if (live) return { ...(await nutrition.enrich(live)), remoteID: `dish-${slug}`, live: true };
    }
    if (!draft) {
      if (await cache.get(`dishmiss:${slug}`)) throw new HttpError(404, `We couldn't find a recipe called "${name}".`, { code: 'unknown_dish' });
      // A new AI recipe is Premium (weekly cap); once written it's shared with everyone for free.
      if (deviceId != null) await usage.assertAllowed(deviceId, 'dishAI', premium);
      const result = await ai.json({ ...dishTasks.recipe({ name, country: code ? countryName(code) : null, region }), model: config.DISH_MODEL });
      if (!result.found || !(result.recipe?.ingredients?.length >= 2)) {
        await cache.set(`dishmiss:${slug}`, 1, 7 * DAY);
        throw new HttpError(404, `We couldn't find a recipe called "${name}". Check the spelling or try another name.`, { code: 'unknown_dish' });
      }
      draft = toDraft(result.recipe, { method: 'search' });
      if (isThin(draft)) {
        const fuller = await ai.json({ ...expandTask({ name, recipe: result.recipe }), model: config.DISH_MODEL })
          .then((r) => toDraft(r.recipe, { method: 'search' }), (error) => { log.warn('recipe expand failed', { name, error: error.message }); return null; });
        if (fuller && fuller.ingredients.length >= draft.ingredients.length && fuller.steps.length >= draft.steps.length) draft = fuller;
      }
      source = 'ai';
      if (deviceId != null) await usage.consume(deviceId, 'dishAI', premium);
    }
    draft = await nutrition.enrich(draft);
    draft.remoteID = `dish-${slug}`;
    await db.query('INSERT IGNORE INTO dishes (slug, name, country, source, recipe) VALUES (?, ?, ?, ?, ?)',
      [slug, draft.title || name, code ?? null, source, JSON.stringify(draft)]);
    log.info('dish added to the shared library', { name, source });
    return draft;
  }

  async function withPhoto(draft) {
    if (draft.imageURL || !images) return draft;
    const found = await images.existing(draft.title);
    if (found) return { ...draft, imageURL: found };
    // Look for a free photo in the background; it shows on the next visit.
    images.recipePhoto({ title: draft.title, freeOnly: true }).catch(() => {});
    return draft;
  }

  const entities = { '&amp;': '&', '&#39;': "'", '&quot;': '"', '&lt;': '<', '&gt;': '>' };
  const unescape = (text) => String(text ?? '').replace(/&(amp|#39|quot|lt|gt);/g, (m) => entities[m]);

  return {
    /**
     * Recipe videos: YouTube's top matches when the server has a YouTube key (cached 30 days, shared),
     * and always a YouTube search link. Only links — videos play on YouTube, nothing is downloaded.
     */
    async videos({ title }) {
      const name = cleanText(title).replace(/\([^)]*\)/g, ' ').replace(/\s+/g, ' ').trim() || cleanText(title);
      const searchURL = `https://www.youtube.com/results?search_query=${encodeURIComponent(`${name} recipe`)}`;
      if (!config.YOUTUBE_API_KEY) return { videos: [], searchURL };
      try {
        const { value } = await cache.wrap(`videos:v1:${soundKey(name)}`, 30 * DAY, async () => {
          const data = await fetcher.fetchJson(`https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults=8&safeSearch=strict&videoEmbeddable=true&q=${encodeURIComponent(`${name} recipe`)}&key=${encodeURIComponent(config.YOUTUBE_API_KEY)}`);
          return (data?.items ?? []).filter((item) => item.id?.videoId && describesDish(name, unescape(item.snippet?.title)))
            .slice(0, 5).map((item) => ({
              id: item.id.videoId,
              title: unescape(item.snippet.title).slice(0, 120),
              channel: unescape(item.snippet.channelTitle).slice(0, 60),
              thumbnail: item.snippet.thumbnails?.high?.url ?? item.snippet.thumbnails?.medium?.url ?? null,
              url: `https://www.youtube.com/watch?v=${item.id.videoId}`,
            }));
        });
        return { videos: value, searchURL };
      } catch (error) {
        log.warn('video search failed', { title: name, error: error.message });
        return { videos: [], searchURL };
      }
    },

    /** Up to 8 dish names for what's being typed: local dishes first, then the shared library. */
    async suggest({ q, country: code, region, premium = false }) {
      const query = cleanText(q);
      if (soundKey(query).length < 2) return { suggestions: [] };
      const [local, saved] = await Promise.all([
        code ? countryNames(code, premium).catch((error) => { log.warn('dish names failed', { country: code, error: error.message }); return []; }) : [],
        db.query('SELECT name FROM dishes WHERE slug LIKE ? OR slug LIKE ? ORDER BY hits DESC LIMIT 20',
          [`${dishSlug(query)}%`, `%-${dishSlug(query)}%`]).then(([rows]) => rows, () => []),
      ]);
      const wanted = soundKey(region ?? '');
      const seen = new Set();
      const candidates = [...local.map((d) => ({ ...d, saved: false })), ...saved.map((r) => ({ name: r.name, region: null, saved: true }))];
      // The cook's own region only reorders real matches; it never adds dishes that don't match.
      const ranked = candidates.map((d) => ({ ...d, score: matchScore(query, d.name) }))
        .filter((d) => d.score > 0)
        .map((d) => ({ ...d, score: d.score + (wanted && soundKey(d.region ?? '') === wanted ? 0.5 : 0) }))
        .sort((a, b) => b.score - a.score || a.name.length - b.name.length)
        .filter((d) => !seen.has(soundKey(d.name)) && seen.add(soundKey(d.name)));
      return { suggestions: ranked.slice(0, 8).map(({ name, region: where }) => ({ name, region: where })) };
    },

    /** The recipe for a dish by name: from the shared library, else found once and added to it. */
    async find({ name, country: code, region, deviceId, premium }) {
      const clean = cleanText(name).slice(0, 80);
      const slug = dishSlug(clean);
      if (slug.length < 2) throw new HttpError(400, 'Please type a dish name.', { code: 'validation' });
      const [[row]] = await db.query('SELECT recipe FROM dishes WHERE slug = ?', [slug]);
      if (row) {
        db.query('UPDATE dishes SET hits = hits + 1 WHERE slug = ?', [slug]).catch(() => {});
        const recipe = typeof row.recipe === 'string' ? JSON.parse(row.recipe) : row.recipe;
        return { recipe: await withPhoto(recipe), cached: true };
      }
      if (!building.has(slug)) {
        building.set(slug, build(slug, clean, code, region, { deviceId, premium }).finally(() => building.delete(slug)));
      }
      const { live, ...recipe } = await building.get(slug);
      // live: from Spoonacular, not saved here (their terms) — the app should not keep it long either.
      return { recipe: await withPhoto(recipe), cached: false, ...(live ? { live: true } : {}) };
    },
  };
}
