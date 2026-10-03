// Free recipe sources tried before AI writes a dish: the Wikibooks Cookbook (CC BY-SA, may be saved with
// credit) and Spoonacular (live only — its terms forbid storing recipes, so callers never save these).
import { parseLine } from './nutrition.js';
import { toDraft } from './recipe.js';
import { describesDish } from './services.js';
import { dayStart, log } from './util.js';
import { cleanText } from './validation.js';

const DAY = 86_400;

/** Too short to cook from: a second AI pass writes it out in full. */
export const isThin = (draft) => (draft?.ingredients?.length ?? 0) < 10 || (draft?.steps?.length ?? 0) < 8;

/** Wikitext → plain text: links keep their label, templates, refs, files and bold/italics go. */
export function plainWiki(text) {
  let out = String(text ?? '').replace(/<ref[^>]*\/>|<ref[\s\S]*?<\/ref>|<!--[\s\S]*?-->/g, '');
  for (let i = 0; i < 5 && /\{\{[^{}]*\}\}/.test(out); i += 1) out = out.replace(/\{\{[^{}]*\}\}/g, '');
  return out
    .replace(/\[\[(?:File|Image|Category):[^\]]*\]\]/gi, '')
    .replace(/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/g, '$1')
    .replace(/\[https?:\/\/\S+\s+([^\]]+)\]/g, '$1')
    .replace(/'{2,}/g, '')
    .replace(/<[^>]+>/g, ' ');
}

/** A Wikibooks Cookbook page's wikitext → recipe (or null when it has too little to cook from). */
export function wikibooksRecipe(title, wikitext) {
  const servings = Number(/\|\s*servings\s*=\s*(\d+)/i.exec(wikitext)?.[1]) || null;
  const minutes = /\|\s*time\s*=\s*([^|}\n]+)/i.exec(wikitext)?.[1] ?? '';
  const hours = Number(/(\d+)\s*h/i.exec(minutes)?.[1] ?? 0);
  const totalMinutes = hours * 60 + Number(/(\d+)\s*min/i.exec(minutes)?.[1] ?? 0) || null;
  const sections = String(wikitext).split(/^==+\s*(.+?)\s*==+\s*$/m);
  const ingredients = [];
  const steps = [];
  for (let i = 1; i < sections.length; i += 2) {
    const heading = sections[i].toLowerCase();
    const lines = sections[i + 1].split('\n');
    if (/ingredient/.test(heading)) {
      for (const line of lines) {
        if (!/^\*/.test(line)) continue;
        const text = cleanText(plainWiki(line.replace(/^\*+\s*/, '')));
        if (text.length < 2) continue;
        const parsed = parseLine(text);
        ingredients.push({ text, quantity: parsed.quantity, unit: parsed.unit, name: parsed.name || text, confidence: parsed.quantity ? 0.85 : 0.6 });
      }
    } else if (/procedure|method|instruction|direction|preparation|steps/.test(heading)) {
      for (const line of lines) {
        if (!/^#/.test(line)) continue;
        const text = cleanText(plainWiki(line.replace(/^#+[:*]?\s*/, '')));
        if (text.length > 3) steps.push({ text, timerSeconds: Number(/(\d+)\s*min/i.exec(text)?.[1] ?? 0) * 60 || null, confidence: 0.85 });
      }
    }
  }
  if (ingredients.length < 5 || steps.length < 3) return null;
  const name = title.replace(/^Cookbook:/, '');
  return toDraft({ title: name, servings, totalMinutes, ingredients, steps }, {
    method: 'search', sourceName: 'Wikibooks Cookbook (CC BY-SA)',
    sourceURL: `https://en.wikibooks.org/wiki/${encodeURIComponent(title.replace(/ /g, '_'))}`,
  });
}

export function createSources({ config, cache, fetcher }) {
  const wiki = 'https://en.wikibooks.org/w/api.php?format=json&formatversion=2';

  /** Spoonacular recipe information → recipe draft, credited to the original site. */
  function spoonDraft(r) {
    const ingredients = (r.extendedIngredients ?? []).map((i) => ({
      text: cleanText(i.original ?? `${i.amount ?? ''} ${i.unit ?? ''} ${i.name ?? ''}`),
      quantity: Number.isFinite(i.amount) && i.amount > 0 ? i.amount : null,
      unit: i.unit || null, name: i.name ?? '', confidence: 0.9,
    })).filter((i) => i.text);
    const steps = (r.analyzedInstructions ?? []).flatMap((part) => part.steps ?? []).map((s) => ({
      text: cleanText(s.step ?? ''),
      timerSeconds: s.length?.unit === 'minutes' ? s.length.number * 60 : null,
      confidence: 0.9,
    })).filter((s) => s.text.length > 3);
    return toDraft({
      title: r.title, servings: r.servings ?? null, totalMinutes: r.readyInMinutes ?? null,
      cuisine: r.cuisines?.[0] ?? null, imageURL: r.image ?? null, ingredients, steps,
    }, { method: 'search', sourceName: r.sourceName || r.creditsText || 'spoonacular', sourceURL: r.sourceUrl || `https://spoonacular.com/recipes/-${r.id}` });
  }

  return {
    async wikibooks(name) {
      try {
        const found = await fetcher.fetchJson(`${wiki}&action=query&list=search&srnamespace=102&srlimit=5&srsearch=${encodeURIComponent(name)}`);
        const page = (found?.query?.search ?? []).map((r) => r.title)
          .find((title) => describesDish(name, title.replace(/^Cookbook:/, '')));
        if (!page) return null;
        const parsed = await fetcher.fetchJson(`${wiki}&action=parse&prop=wikitext&page=${encodeURIComponent(page)}`);
        return wikibooksRecipe(page, parsed?.parse?.wikitext ?? '');
      } catch (error) {
        log.warn('wikibooks lookup failed', { name, error: error.message });
        return null;
      }
    },

    /** Live only. The id/title may be kept (allowed by their terms) so the next lookup is one call. */
    async spoonacular(name, slug) {
      if (!config.SPOONACULAR_API_KEY) return null;
      try {
        const known = await cache.get(`spoonid:${slug}`);
        if ((await cache.incr(`spoon:recipes:${dayStart(new Date())}`, DAY)) > config.SPOONACULAR_RECIPES_PER_DAY) return null;
        const key = `apiKey=${config.SPOONACULAR_API_KEY}`;
        let recipe;
        if (known) {
          recipe = await fetcher.fetchJson(`https://api.spoonacular.com/recipes/${known}/information?${key}`);
        } else {
          const data = await fetcher.fetchJson(`https://api.spoonacular.com/recipes/complexSearch?query=${encodeURIComponent(name.slice(0, 80))}&number=3&addRecipeInformation=true&fillIngredients=true&instructionsRequired=true&${key}`);
          recipe = (data?.results ?? []).find((r) => describesDish(name, r.title));
          if (recipe) await cache.set(`spoonid:${slug}`, recipe.id, 30 * DAY);
        }
        const draft = recipe ? spoonDraft(recipe) : null;
        return draft && draft.ingredients.length >= 3 && draft.steps.length >= 2 ? draft : null;
      } catch (error) {
        log.warn('spoonacular recipe lookup failed', { name, error: error.message });
        return null;
      }
    },
  };
}
