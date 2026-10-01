import { cleanText } from './validation.js';

const SLOTS = new Set(['breakfast', 'lunch', 'dinner', 'snack']);
const clamp = (value, min, max) => {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(Math.max(n, min), max) : min;
};
const str = (value, max, multiline = false) => {
  const text = cleanText(value == null ? '' : String(value), { multiline }).slice(0, max).trim();
  return text || undefined;
};
const link = (value) => {
  const text = str(value, 2048);
  if (!text) return undefined;
  try {
    const url = new URL(text);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : undefined;
  } catch {
    return undefined;
  }
};
const positive = (value, max) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.min(n, max) : undefined;
};

/**
 * Shapes any recipe (JSON-LD, AI) exactly like the app's RecipeDraft decoder expects: cleaned text,
 * clamped numbers, no empty lines, and — when present — a complete nutrition object.
 */
export function toDraft(input = {}, extras = {}) {
  const source = { ...input, ...Object.fromEntries(Object.entries(extras).filter(([, v]) => v != null && v !== '')) };
  const ingredients = (Array.isArray(source.ingredients) ? source.ingredients : []).slice(0, 100).map((item) => {
    const line = typeof item === 'string' ? { text: item } : item ?? {};
    const quantity = positive(line.quantity, 100_000);
    const quantityMax = positive(line.quantityMax, 100_000);
    return {
      text: str(line.text ?? [line.quantity, line.unit, line.name].filter(Boolean).join(' '), 200),
      quantity,
      quantityMax: quantityMax && quantity && quantityMax > quantity ? quantityMax : undefined,
      unit: str(line.unit, 20),
      name: str(line.name, 120),
      note: str(line.note, 120),
      confidence: line.confidence == null ? undefined : clamp(line.confidence, 0, 1),
      isOptional: line.isOptional === true ? true : undefined,
    };
  }).filter((item) => item.text || item.name);

  const steps = (Array.isArray(source.steps) ? source.steps : []).slice(0, 60).map((step) => {
    const value = typeof step === 'string' ? { text: step } : step ?? {};
    return {
      text: str(value.text, 2000, true),
      timerSeconds: value.timerSeconds == null ? undefined : Math.round(clamp(value.timerSeconds, 0, 86_400)),
      confidence: value.confidence == null ? undefined : clamp(value.confidence, 0, 1),
    };
  }).filter((step) => step.text);

  let nutrition;
  const n = source.nutrition;
  if (n && Number(n.calories) > 0) {
    const matched = Math.round(clamp(n.matched, 0, 100));
    nutrition = {
      calories: clamp(n.calories, 0, 20_000),
      protein: clamp(n.protein, 0, 2_000),
      carbs: clamp(n.carbs, 0, 2_000),
      fat: clamp(n.fat, 0, 2_000),
      fiber: clamp(n.fiber, 0, 500),
      sugar: clamp(n.sugar, 0, 2_000),
      sodium: clamp(n.sodium, 0, 50_000),
      matched,
      total: Math.max(matched, Math.round(clamp(n.total, 0, 100))),
      source: str(n.source, 40),
    };
  }

  const prep = Math.round(clamp(source.prepMinutes, 0, 2880));
  const cook = Math.round(clamp(source.cookMinutes, 0, 2880));
  const draft = {
    title: str(source.title, 120) ?? '',
    summary: str(source.summary, 300),
    sourceURL: link(source.sourceURL),
    sourceName: str(source.sourceName, 100),
    creator: str(source.creator, 100),
    imageURL: link(source.imageURL),
    servings: source.servings == null ? undefined : Math.round(clamp(source.servings, 1, 100)),
    prepMinutes: prep,
    cookMinutes: cook,
    totalMinutes: Math.round(clamp(source.totalMinutes, 0, 2880)) || prep + cook,
    cuisine: str(source.cuisine, 40),
    mealTypes: [...new Set((source.mealTypes ?? []).map((slot) => String(slot).toLowerCase()).filter((slot) => SLOTS.has(slot)))],
    tags: [...new Set((source.tags ?? []).map((tag) => str(tag, 30)).filter(Boolean))].slice(0, 20),
    ingredients,
    steps,
    nutrition,
    method: str(source.method, 20),
  };
  return JSON.parse(JSON.stringify(draft)); // drops undefined keys; the app treats missing as "unknown"
}
