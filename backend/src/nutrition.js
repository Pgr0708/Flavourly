// Verified nutrition: ingredient lines → grams → USDA FoodData Central (public domain, free key),
// with Spoonacular for lines USDA can't match (optional key). AI estimates are only a labelled fallback.
// Every lookup is cached in Redis for 30 days, so each food is fetched once for all users.
import { log, sha256 } from './util.js';

const DAY = 86_400;
const USDA = 'https://api.nal.usda.gov/fdc/v1';
const SPOONACULAR = 'https://api.spoonacular.com';
const NUTRIENTS = { calories: ['208', '957', '958'], protein: ['203'], carbs: ['205'], fat: ['204'], fiber: ['291'], sugar: ['269', '539'], sodium: ['307'] };
const EMPTY = { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0, sodium: 0 };

// ── Parsing "1 1/2 cups plain flour, sifted" ──────────────────────────────────────────────────
const FRACTIONS = { '¼': 0.25, '½': 0.5, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125 };
const UNITS = [
  ['kg', /^(kg|kgs|kilo|kilos|kilograms?)$/], ['g', /^(g|gm|gms|gr|grams?|grammes?)$/], ['mg', /^(mg|milligrams?)$/],
  ['lb', /^(lb|lbs|pounds?)$/], ['oz', /^(oz|ounces?)$/], ['l', /^(l|ltr|litres?|liters?)$/], ['ml', /^(ml|millilitres?|milliliters?)$/],
  ['tbsp', /^(tbsp|tbs|tablespoons?|T)$/], ['tsp', /^(tsp|teaspoons?|t)$/], ['cup', /^(cups?|c)$/],
  ['clove', /^cloves?$/], ['slice', /^slices?$/], ['can', /^(cans?|tins?)$/], ['pinch', /^pinch(es)?$/],
  ['bunch', /^bunch(es)?$/], ['piece', /^(pieces?|pcs?|nos?|whole)$/], ['stick', /^sticks?$/], ['handful', /^handfuls?$/],
];
const GRAMS = { kg: 1000, g: 1, mg: 0.001, lb: 453.6, oz: 28.35 };
const ML = { l: 1000, ml: 1, cup: 236.6, tbsp: 14.79, tsp: 4.93 };
// Not noise: cooked/raw change the food (200 g cooked rice ≈ 260 kcal, raw ≈ 730).
const NOISE = /\b(fresh(ly)?|finely|roughly|thinly|chopped|diced|sliced|minced|grated|crushed|ground|peeled|large|medium|small|ripe|boneless|skinless|optional|to taste|for garnish|divided|softened|melted|organic|about|approx\.?)\b/gi;

function number(token) {
  if (FRACTIONS[token] != null) return FRACTIONS[token];
  const mixed = /^(\d+)([¼½¾⅓⅔⅛])$/.exec(token);
  if (mixed) return Number(mixed[1]) + FRACTIONS[mixed[2]];
  const fraction = /^(\d+)\/(\d+)$/.exec(token);
  if (fraction) return Number(fraction[2]) ? Number(fraction[1]) / Number(fraction[2]) : null;
  const plain = /^\d+(?:[.,]\d+)?$/.exec(token);
  return plain ? Number(token.replace(',', '.')) : null;
}

/** "1 1/2 cups plain flour, sifted" → { quantity: 1.5, unit: 'cup', name: 'plain flour' } */
export function parseLine(text) {
  const tokens = String(text).replace(/(\d)([a-zA-Z])/g, '$1 $2').replace(/[()]/g, ' ').trim().split(/\s+/);
  let quantity = null;
  let i = 0;
  while (i < tokens.length) {
    const value = number(tokens[i]);
    if (value == null) {
      const range = /^(\d+(?:\.\d+)?)[-–](\d+(?:\.\d+)?)$/.exec(tokens[i]); // "2-3" → 2.5
      if (!range) break;
      quantity = (quantity ?? 0) + (Number(range[1]) + Number(range[2])) / 2;
    } else {
      quantity = (quantity ?? 0) + value;
    }
    i += 1;
  }
  let unit = null;
  if (quantity != null && tokens[i]) {
    const word = tokens[i].replace(/\.$/, '');
    const match = UNITS.find(([, pattern]) => pattern.test(word) || pattern.test(word.toLowerCase()));
    if (match) { unit = match[0]; i += 1; if (/^of$/i.test(tokens[i] ?? '')) i += 1; }
  }
  const [first, ...rest] = tokens.slice(i).join(' ').split(/,| - | – /);
  // "1 cup chickpeas, cooked": the state after the comma still decides which food it is.
  const state = /\b(cooked|boiled|raw|canned|frozen|dried)\b/i.exec(rest.join(' '))?.[1];
  const base = first.replace(NOISE, ' ').replace(/\s+/g, ' ').trim().toLowerCase();
  const name = state && !base.includes(state.toLowerCase()) ? `${state.toLowerCase()} ${base}` : base;
  return { quantity, unit, name };
}

/** "onions" → "onion", "tomatoes" → "tomato", "berries" → "berry": one cache entry and USDA query per food. */
export function singular(name) {
  return name.replace(/(\w+)$/, (word) => {
    if (word.length <= 3 || /ss$/.test(word)) return word;
    if (/ies$/.test(word)) return `${word.slice(0, -3)}y`;
    if (/oes$/.test(word)) return word.slice(0, -2);
    return word.replace(/s$/, '');
  });
}

// ── Grams from a USDA food's portions ─────────────────────────────────────────────────────────
function grams({ quantity, unit }, food) {
  if (quantity == null || quantity <= 0) return null;
  if (GRAMS[unit]) return quantity * GRAMS[unit];
  const portion = (...words) => { // first word wins, in the order given
    for (const w of words) {
      const hit = food.portions.find((p) => p.label.startsWith(w));
      if (hit) return hit.grams;
    }
    return undefined;
  };
  if (ML[unit]) {
    const perCup = portion('cup');
    const perMl = perCup ? perCup / 236.6 : portion('tbsp') ? portion('tbsp') / 14.79 : 1; // water density as a last resort
    return quantity * ML[unit] * perMl;
  }
  if (unit === 'pinch') return quantity * 0.35;
  const fixed = { can: 400, stick: 113, bunch: 100 }; // typical sizes when USDA has no such portion
  if (fixed[unit]) return quantity * (portion(unit) ?? fixed[unit]);
  if (unit === 'handful') return quantity * 30;
  const each = portion(unit ?? 'medium', 'medium', 'large', 'small', 'whole', 'piece', 'item', 'slice', 'clove') ?? food.portions.find((p) => !/cup|tbsp|tsp|oz/.test(p.label))?.grams;
  return each ? quantity * each : null;
}

const per100 = (nutrients, gramsUsed) => Object.fromEntries(Object.entries(nutrients).map(([k, v]) => [k, (v * gramsUsed) / 100]));

/** All significant words of the query must appear in the food's description, or it's not the same food. */
function sameFood(query, description) {
  const words = description.toLowerCase().split(/[^a-z]+/).filter(Boolean);
  return query.toLowerCase().split(/[^a-z]+/).filter((w) => w.length >= 3)
    .every((w) => words.some((d) => d.startsWith(w.slice(0, Math.max(3, w.length - 2)))));
}

// Parts and processed forms of a food: never the default unless the line asks for them.
const PROCESSED = /\b(egg white|egg whites|yolk|yolks|flour|powder|powdered|dehydrated|dried|flakes|babyfood|rings|fried|cooked|canned|frozen|juice|sauce|soup|chips|bagels?|snacks?|mix|substitute|imitation|sweetened|candied|puree|paste|prepared|mashed|hash)\b/g;

// Niche varieties: fine when asked for, never the default ("white rice" is not sticky rice).
const VARIETY = /\b(glutinous|parboiled|instant|sprouted|low sodium|reduced fat|fat free|ghee|anhydrous|sheep|goat|buffalo|human|podded)\b/g;

/** USDA search sometimes lists foods without any nutrient values (some Foundation entries) — unusable. */
export const hasNutrients = (food) => (food.foodNutrients ?? []).some((n) => ['208', '957', '958', '203', '204', '205'].includes(String(n.nutrientNumber)) && Number.isFinite(n.value));

/**
 * Best USDA candidate for an ingredient, or null. USDA names put the food first ("Oil, olive, …"),
 * so query words there count most; parts/processed forms and restaurant brands are pushed down.
 */
export function pickFood(query, foods) {
  const words = query.toLowerCase().split(/[^a-z]+/).filter((w) => w.length >= 3);
  const stem = (w) => w.slice(0, Math.max(3, w.length - 2));
  let best = null;
  foods.forEach((food, index) => {
    const description = food.description ?? '';
    if (!sameFood(query, description)) return;
    // "Chickpeas (garbanzo beans, bengal gram), mature seeds": brackets are aliases, not name segments.
    const full = description.toLowerCase();
    const lower = full.replace(/\([^)]*\)/g, '');
    const head = full.split(',').slice(0, 2).join(' ');
    let score = words.filter((w) => head.includes(stem(w))).length * 2 - index * 0.15;
    // USDA names lead with the food itself ("Milk, whole", "Salt, table"): the main noun there is the real match,
    // not "Crackers, milk" or "Butter, salted".
    const noun = words.at(-1);
    const first = lower.split(',')[0].split(/[^a-z]+/).filter((w) => w.length >= 3);
    const isNoun = (w) => Boolean(noun) && (w.startsWith(stem(noun)) || noun.startsWith(stem(w)));
    if (first.length && isNoun(first.at(-1))) score += 3; // "Wheat flour" for flour, "Oil, olive" for olive oil
    // "Milk and cereal bar", "Potato pancakes", "Peas and carrots": the food is only part of another dish.
    else if (first.some(isNoun)) score -= 2;
    // A part on its own ("Potatoes, raw, skin") — not "flesh and skin" or legumes' "mature seeds".
    if (lower.split(',').some((segment) => /^\s*(skin|peel|leaves|stems?|seeds?)\s*$/.test(segment) && !query.toLowerCase().includes(segment.trim()))) score -= 4;
    if (food.dataType === 'SR Legacy') score += 1; // full household portions (clove, cup, medium); Foundation often has none
    // "packed in tomato juice" describes the can, not the food.
    for (const part of full.replace(/packed in [^,]*/g, '').match(PROCESSED) ?? []) if (!query.toLowerCase().includes(part)) score -= 3;
    for (const kind of full.match(VARIETY) ?? []) if (!query.toLowerCase().includes(kind)) score -= 2;
    if (/\b(raw|whole|uncooked)\b/.test(lower)) score += 1;
    if (/[A-Z]{3,}/.test(description.replace(/\b(USDA|NFS|UPC)\b/g, ''))) score -= 4; // "DENNY'S, onion rings"
    score -= Math.max(0, lower.split(',').length - 3) * 0.3;
    if (score > 0 && (!best || score > best.score)) best = { food, score };
  });
  return best?.food ?? null;
}

export function createNutrition({ config, cache, http = fetch }) {
  const get = async (url, init) => {
    const response = await http(url, { ...init, signal: AbortSignal.timeout(8_000) });
    if (!response.ok) throw new Error(`${new URL(url).hostname} answered ${response.status}`);
    return response.json();
  };

  /** One USDA food per ingredient name: nutrients per 100 g + household portions in grams. */
  async function usdaFood(name) {
    const { value } = await cache.wrap(`usda:v10:${sha256(name)}`, 30 * DAY, async () => {
      const key = encodeURIComponent(config.USDA_API_KEY);
      const found = await get(`${USDA}/foods/search?api_key=${key}&pageSize=25&dataType=Foundation,SR%20Legacy&query=${encodeURIComponent(name)}`);
      const food = pickFood(name, (found.foods ?? []).filter(hasNutrients));
      if (!food) return { none: true };
      const pick = (numbers) => {
        for (const n of numbers) {
          const hit = food.foodNutrients?.find((x) => String(x.nutrientNumber) === n && Number.isFinite(x.value));
          if (hit) return hit.value;
        }
        return 0;
      };
      const nutrients = Object.fromEntries(Object.entries(NUTRIENTS).map(([k, numbers]) => [k, pick(numbers)]));
      if (!nutrients.calories) nutrients.calories = 4 * nutrients.protein + 4 * nutrients.carbs + 9 * nutrients.fat;
      const detail = await get(`${USDA}/food/${food.fdcId}?api_key=${key}`).catch(() => ({}));
      // RACC is a label serving size, not a unit — "1 clove" must never mean 85 g.
      const portions = (detail.foodPortions ?? []).filter((p) => p.gramWeight > 0 && p.measureUnit?.name !== 'RACC').map((p) => ({
        label: [p.measureUnit?.name !== 'undetermined' ? p.measureUnit?.name : null, p.modifier, p.portionDescription]
          .filter(Boolean).join(' ').toLowerCase().replace(/^tablespoon/, 'tbsp').replace(/^teaspoon/, 'tsp'),
        grams: p.gramWeight / (p.amount || 1),
      }));
      return { fdcId: food.fdcId, description: food.description, nutrients, portions };
    });
    return value?.none ? null : value;
  }

  /** Spoonacular parses and prices whole lines itself; used only for lines USDA couldn't match. */
  async function spoonacular(lines) {
    if (!config.SPOONACULAR_API_KEY || !lines.length) return [];
    const { value } = await cache.wrap(`spoon:v1:${sha256(lines.join('\n'))}`, 30 * DAY, async () => {
      const body = new URLSearchParams({ ingredientList: lines.join('\n'), servings: '1', includeNutrition: 'true' });
      const items = await get(`${SPOONACULAR}/recipes/parseIngredients?apiKey=${encodeURIComponent(config.SPOONACULAR_API_KEY)}`, {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
      });
      const names = { calories: 'Calories', protein: 'Protein', carbs: 'Carbohydrates', fat: 'Fat', fiber: 'Fiber', sugar: 'Sugar', sodium: 'Sodium' };
      return (Array.isArray(items) ? items : []).map((item) => {
        const list = item?.nutrition?.nutrients ?? [];
        if (!list.length) return null;
        return Object.fromEntries(Object.entries(names).map(([k, n]) => [k, list.find((x) => x.name === n)?.amount ?? 0]));
      });
    });
    return value ?? [];
  }

  /**
   * Nutrition per serving for ingredient lines, or null when too few lines could be verified.
   * Lines without an amount ("salt to taste") don't count either way.
   */
  async function forLines(lines, servings = 2, { minCoverage = 0.6 } = {}) {
    const parsed = lines.map((text) => ({ text, ...parseLine(text) })).filter((line) => line.quantity != null && line.name);
    if (!parsed.length) return null;
    const total = { ...EMPTY };
    const missing = [];
    let matched = 0;
    let usedSpoonacular = false;
    const add = (part) => { for (const k of Object.keys(total)) total[k] += part[k] ?? 0; };

    const foods = await mapLimited(parsed, 4, (line) => usdaFood(singular(line.name)).catch((error) => {
      log.warn('usda lookup failed', { name: line.name, error: error.message });
      return null;
    }));
    parsed.forEach((line, index) => {
      const food = foods[index];
      const used = food && grams(line, food);
      if (used) { add(per100(food.nutrients, used)); matched += 1; } else missing.push(line.text);
    });
    if (missing.length) {
      const extra = await spoonacular(missing).catch((error) => { log.warn('spoonacular failed', { error: error.message }); return []; });
      for (const part of extra) if (part) { add(part); matched += 1; usedSpoonacular = true; }
    }
    if (matched / parsed.length < minCoverage) return null;
    const portions = Math.max(1, Number(servings) || 1);
    const round = (v, d = 0) => Math.round((v / portions) * 10 ** d) / 10 ** d;
    return {
      calories: round(total.calories), protein: round(total.protein, 1), carbs: round(total.carbs, 1), fat: round(total.fat, 1),
      fiber: round(total.fiber, 1), sugar: round(total.sugar, 1), sodium: round(total.sodium),
      matched, total: parsed.length,
      source: usedSpoonacular ? 'USDA + Spoonacular' : 'USDA FoodData Central',
    };
  }

  return {
    forLines,
    /** Replaces an AI estimate with verified numbers when enough ingredients match; otherwise labels it. */
    async enrich(draft) {
      if (!draft?.ingredients?.length) return draft;
      const verified = await withTimeout(forLines(draft.ingredients.map((i) => i.text || [i.quantity, i.unit, i.name].filter(Boolean).join(' ')), draft.servings ?? 2), 12_000).catch(() => null);
      if (verified) return { ...draft, nutrition: verified };
      return draft.nutrition ? { ...draft, nutrition: { ...draft.nutrition, source: 'AI estimate' } } : draft;
    },
  };
}

async function mapLimited(items, limit, task) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await task(items[index], index);
    }
  }));
  return results;
}

const withTimeout = (promise, ms) => Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms).unref?.())]);
