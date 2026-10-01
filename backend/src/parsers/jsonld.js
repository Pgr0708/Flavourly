import * as cheerio from 'cheerio';

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', frac12: '½', frac14: '¼', frac34: '¾', deg: '°', ndash: '–', mdash: '—', hellip: '…', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”' };

/** Decodes HTML entities and drops tags from strings that sites put inside JSON-LD. */
export function plain(value) {
  if (value == null) return '';
  return String(value)
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/?[A-Za-z][^<>]*>/g, ' ')
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)))
    .replace(/&([a-z]+\d*);/gi, (match, name) => ENTITIES[name.toLowerCase()] ?? match)
    .replace(/[ \t]+/g, ' ')
    .trim();
}

/** "PT1H30M" → 90, "P0DT45M" → 45, "1 hour 15 mins" → 75, 20 → 20. */
export function parseDuration(value) {
  if (value == null || value === '') return 0;
  if (typeof value === 'number') return Math.max(0, Math.round(value));
  const text = String(value).trim();
  const iso = /^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i.exec(text);
  if (iso) {
    const [, d = 0, h = 0, m = 0, s = 0] = iso;
    return Math.round(Number(d) * 1440 + Number(h) * 60 + Number(m) + Number(s) / 60);
  }
  const hours = /(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b/i.exec(text);
  const minutes = /(\d+)\s*(?:m|min|mins|minute|minutes)\b/i.exec(text);
  if (hours || minutes) return Math.round(Number(hours?.[1] ?? 0) * 60 + Number(minutes?.[1] ?? 0));
  return /^\d+$/.test(text) ? Number(text) : 0;
}

/** recipeYield can be 4, "4", "Serves 4-6", ["4", "4 servings"]. */
export function parseYield(value) {
  if (Array.isArray(value)) {
    for (const item of value) {
      const parsed = parseYield(item);
      if (parsed) return parsed;
    }
    return null;
  }
  if (typeof value === 'number') return value > 0 ? Math.round(value) : null;
  const match = /(\d+)/.exec(String(value ?? ''));
  return match ? Number(match[1]) : null;
}

const first = (value) => (Array.isArray(value) ? value[0] : value);

function imageOf(value) {
  const image = first(value);
  if (!image) return null;
  if (typeof image === 'string') return image;
  return image.url || image.contentUrl || first(image['@id']) || null;
}

function authorOf(value) {
  const author = first(value);
  if (!author) return null;
  return typeof author === 'string' ? plain(author) : plain(author.name || '') || null;
}

function listOf(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value.flatMap(listOf);
  return String(value).split(',').map((item) => plain(item)).filter(Boolean);
}

/** recipeInstructions: string | [string] | [HowToStep] | [HowToSection{itemListElement}] → step texts. */
export function instructionsOf(value) {
  if (!value) return [];
  if (typeof value === 'string') {
    return plain(value).split(/\n+|(?<=[.!?])\s+(?=\d+[.)]\s)/).map((step) => step.replace(/^\d+[.)]\s*/, '').trim()).filter(Boolean);
  }
  if (Array.isArray(value)) return value.flatMap(instructionsOf);
  if (typeof value === 'object') {
    if (value.itemListElement) return instructionsOf(value.itemListElement);
    const text = plain(value.text || value.name || '');
    return text ? [text] : [];
  }
  return [];
}

const number = (value) => {
  const match = /(\d+(?:[.,]\d+)?)/.exec(String(value ?? ''));
  return match ? Number(match[1].replace(',', '.')) : 0;
};

function nutritionOf(value) {
  if (!value || typeof value !== 'object') return null;
  const nutrition = {
    calories: number(value.calories),
    protein: number(value.proteinContent),
    carbs: number(value.carbohydrateContent),
    fat: number(value.fatContent),
    fiber: number(value.fiberContent),
    sugar: number(value.sugarContent),
    sodium: number(value.sodiumContent) * (/\bg\b/i.test(String(value.sodiumContent ?? '')) && !/mg/i.test(String(value.sodiumContent)) ? 1000 : 1),
  };
  return nutrition.calories > 0 ? { ...nutrition, matched: 0, total: 0, source: 'publisher' } : null;
}

const isRecipe = (node) => node && typeof node === 'object' && [].concat(node['@type'] ?? []).some((type) => String(type).toLowerCase() === 'recipe');

/** Finds a schema.org Recipe anywhere inside a JSON-LD document (@graph, arrays, mainEntity…). */
export function findRecipe(node, depth = 0) {
  if (!node || depth > 6) return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const found = findRecipe(item, depth + 1);
      if (found) return found;
    }
    return null;
  }
  if (typeof node !== 'object') return null;
  if (isRecipe(node)) return node;
  for (const key of ['@graph', 'mainEntity', 'mainEntityOfPage', 'itemListElement', 'item']) {
    const found = findRecipe(node[key], depth + 1);
    if (found) return found;
  }
  return null;
}

/** Turns a schema.org Recipe into the app's draft shape (before normalisation). */
export function recipeFromJsonLd(node) {
  const prep = parseDuration(node.prepTime);
  const cook = parseDuration(node.cookTime);
  const total = parseDuration(node.totalTime) || prep + cook;
  return {
    title: plain(node.name || node.headline),
    summary: plain(node.description),
    creator: authorOf(node.author),
    imageURL: imageOf(node.image),
    servings: parseYield(node.recipeYield),
    prepMinutes: prep,
    cookMinutes: cook,
    totalMinutes: total,
    cuisine: listOf(node.recipeCuisine)[0] ?? null,
    tags: [...listOf(node.recipeCategory), ...listOf(node.keywords)].slice(0, 12),
    ingredients: [].concat(node.recipeIngredient ?? node.ingredients ?? []).map((line) => ({ text: plain(line) })).filter((item) => item.text),
    steps: instructionsOf(node.recipeInstructions).map((text) => ({ text })),
    nutrition: nutritionOf(node.nutrition),
  };
}

/** Reads a page: the JSON-LD recipe if there is one, Open Graph details and the visible text. */
export function readPage(html) {
  const $ = cheerio.load(html);
  let recipe = null;
  $('script[type="application/ld+json"]').each((_, element) => {
    if (recipe) return;
    const raw = $(element).contents().text().trim();
    try {
      const found = findRecipe(JSON.parse(raw));
      if (found) recipe = recipeFromJsonLd(found);
    } catch {
      // Sites often ship one broken block among good ones; skip it.
    }
  });
  const meta = (name) => $(`meta[property="${name}"]`).attr('content') || $(`meta[name="${name}"]`).attr('content') || '';
  const page = {
    title: plain(meta('og:title') || $('title').first().text()),
    description: plain(meta('og:description') || meta('description')),
    image: meta('og:image') || null,
    siteName: plain(meta('og:site_name')) || null,
  };
  $('script, style, noscript, svg, iframe, nav, footer, form').remove();
  const root = $('article').first().length ? $('article').first() : $('main').first().length ? $('main').first() : $('body');
  root.find('br, p, li, h1, h2, h3, h4, div, tr').each((_, element) => {
    $(element).append('\n');
  });
  const text = root.text().replace(/[ \t ]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
  return { recipe, page, text };
}
