// A stand-in for api.openai.com used by the tests and for local end-to-end runs without a real key:
//   node test/fake-openai.js            → http://127.0.0.1:9911/v1  (set OPENAI_BASE_URL to this)
// It speaks the same Chat Completions + Structured Outputs shape, so the real client code is exercised.
// Markers inside the request text trigger failures: FAIL_429_ONCE, FAIL_500, SLOW_REPLY, BAD_JSON, REFUSE, NO_RECIPE, TRUNCATE.
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TINY_JPEG = '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';

const fraction = { '½': 0.5, '¼': 0.25, '¾': 0.75 };

function recipeFromText(text) {
  const body = (/<<<TEXT\n([\s\S]*)\nTEXT>>>/.exec(text)?.[1] ?? text).trim();
  const lines = body.split('\n').map((line) => line.trim()).filter(Boolean);
  const ingredients = [];
  const steps = [];
  let section = '';
  for (const line of lines) {
    if (/^(ingredients?)\b/i.test(line)) { section = 'ingredients'; continue; }
    if (/^(method|steps|instructions|directions)\b/i.test(line)) { section = 'steps'; continue; }
    const bullet = line.replace(/^[-•*]\s*/, '');
    if (section === 'steps' || /^\d+[.)]\s/.test(line)) {
      steps.push({ text: bullet.replace(/^\d+[.)]\s*/, ''), timerSeconds: /(\d+)\s*min/.test(line) ? Number(/(\d+)\s*min/.exec(line)[1]) * 60 : null, confidence: 1 });
    } else if (section === 'ingredients' || /^([\d½¼¾]|-|•)/.test(line)) {
      const match = /^([\d.]+|[½¼¾])\s*(g|kg|ml|l|tsp|tbsp|cups?|cloves?)?\s+(.*)$/i.exec(bullet);
      ingredients.push({
        text: bullet,
        quantity: match ? (fraction[match[1]] ?? Number(match[1])) : null,
        quantityMax: null,
        unit: match?.[2]?.toLowerCase().replace(/s$/, '') ?? null,
        name: match ? match[3] : bullet,
        note: null,
        isOptional: /optional/i.test(bullet),
        confidence: match ? 1 : 0.5,
      });
    }
  }
  const title = lines.find((line) => !/^(kind|source):/i.test(line) && !/^\d/.test(line) && !/^[-•*]/.test(line)) ?? 'Shared recipe';
  return {
    title: title.replace(/[#!]+/g, '').slice(0, 80),
    summary: null, servings: 2, prepMinutes: 10, cookMinutes: 20, totalMinutes: 30, cuisine: null,
    mealTypes: ['dinner'], tags: ['quick'], ingredients, steps,
    nutrition: ingredients.length ? { calories: 520, protein: 24, carbs: 60, fat: 18, fiber: 6, sugar: 8, sodium: 700, matched: ingredients.length, total: ingredients.length } : null,
  };
}

function answer(name, request) {
  const user = request.messages?.find((m) => m.role === 'user')?.content ?? '';
  switch (name) {
    case 'recipe_extraction': {
      if (user.includes('NO_RECIPE')) return { found: false, recipe: { ...recipeFromText(''), title: '', ingredients: [], steps: [] }, notes: [] };
      const recipe = recipeFromText(user);
      return { found: recipe.ingredients.length > 0, recipe, notes: recipe.steps.length ? [] : ['Steps were not in the caption'] };
    }
    case 'ingredient_substitutes': {
      const { replace } = JSON.parse(user);
      return {
        options: [
          { name: 'Greek yogurt', amount: '150 ml', why: 'Tangy and creamy — stir in off the heat.', flavour: 'Tangy', texture: 'Creamy', nutrition: 'More protein', tag: 'healthier' },
          { name: 'Oat cream', amount: '150 ml', why: 'Dairy-free and simmers without splitting.', flavour: null, texture: 'Silky', nutrition: null, tag: 'dairy-free' },
          { name: replace, amount: 'same', why: 'Echoes the original (the server must drop this).', flavour: null, texture: null, nutrition: null, tag: null },
          { name: '  ', amount: '', why: '', flavour: null, texture: null, nutrition: null, tag: null },
        ],
      };
    }
    case 'cook_now_ideas': {
      const { pantry = [], avoidTitles = [] } = JSON.parse(user);
      const minutes = Number(/must be (\d+) minutes/.exec(request.messages[0].content)?.[1] ?? 30);
      const idea = (title, total) => ({
        recipe: {
          title, summary: 'Fast and fresh.', servings: 2, prepMinutes: 5, cookMinutes: total - 5, totalMinutes: total, cuisine: 'Indian',
          mealTypes: ['dinner'], tags: ['quick'],
          ingredients: [
            { text: `2 cups ${pantry[0] ?? 'rice'}`, quantity: 2, quantityMax: null, unit: 'cup', name: pantry[0] ?? 'rice', note: null, isOptional: false, confidence: 1 },
            { text: '1 tbsp oil', quantity: 1, quantityMax: null, unit: 'tbsp', name: 'oil', note: null, isOptional: false, confidence: 1 },
          ],
          steps: [{ text: 'Heat the oil.', timerSeconds: null, confidence: 1 }, { text: 'Cook for 10 minutes.', timerSeconds: 600, confidence: 1 }],
          nutrition: { calories: 450, protein: 18, carbs: 55, fat: 14, fiber: 4, sugar: 3, sodium: 400, matched: 2, total: 2 },
        },
        reason: `Uses your ${pantry[0] ?? 'rice'}`,
      });
      return { ideas: [idea('Pantry fried rice', Math.min(20, minutes)), idea(avoidTitles[0] ?? 'Repeat title', 15), idea('Slow braise', minutes + 60), idea('Quick dal', Math.min(25, minutes))] };
    }
    case 'local_dishes': {
      const { country, focus, count } = JSON.parse(user);
      if (country === 'Nepal') return { dishes: [] }; // "the AI found nothing" path
      const dish = (title, veg) => ({
        region: veg ? null : 'Coastal',
        recipe: {
          title, summary: `A ${country} favourite.`, servings: 4, prepMinutes: 10, cookMinutes: 20, totalMinutes: 30, cuisine: 'ignored',
          mealTypes: [focus.startsWith('breakfast') ? 'breakfast' : 'dinner'], tags: veg ? ['Vegetarian'] : [],
          ingredients: [
            { text: veg ? '200 g paneer' : '500 g chicken', quantity: veg ? 200 : 500, quantityMax: null, unit: 'g', name: veg ? 'paneer' : 'chicken', note: null, isOptional: false, confidence: 1 },
            { text: '1 onion', quantity: 1, quantityMax: null, unit: null, name: 'onion', note: null, isOptional: false, confidence: 1 },
          ],
          steps: [{ text: 'Cook everything for 20 minutes.', timerSeconds: 1200, confidence: 1 }],
          nutrition: { calories: 400, protein: 20, carbs: 30, fat: 15, fiber: 3, sugar: 4, sodium: 500, matched: 2, total: 2 },
        },
      });
      // Every group repeats "Shared dish" so the server has to de-duplicate; one broken dish must be dropped.
      const dishes = [dish('Shared dish', true), dish(`${focus.split(' ')[0]} special`, focus.includes('vegetarian')), { region: null, recipe: { ...dish('No steps', true).recipe, steps: [] } }];
      return { dishes: dishes.slice(0, count) };
    }
    case 'local_kitchen':
      return { cuisine: 'Indian', staples: ['Rice', 'Atta (wheat flour)', 'Toor dal', 'Rice', '  '], cravings: ['Biryani', 'Street food'] };
    case 'meal_plan': {
      const { slots } = JSON.parse(user);
      const picks = slots.map((slot) => ({ date: slot.date, slot: slot.slot, recipeId: slot.candidates[0] ?? 'none', reason: 'Fits a busy weeknight' }));
      if (slots[0]) picks.push({ ...picks[0], recipeId: 'invented-id' }, { date: '2099-01-01', slot: 'dinner', recipeId: slots[0].candidates[0] ?? 'x', reason: 'Wrong day' });
      return { picks };
    }
    default:
      return {};
  }
}

export function startFakeOpenAI({ port = 0, slowMs = 3_000 } = {}) {
  const calls = [];
  const failedOnce = new Set();
  const server = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (chunk) => { raw += chunk; });
    req.on('end', () => {
      const send = (status, body) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(typeof body === 'string' ? body : JSON.stringify(body));
      };
      if (req.headers.authorization !== 'Bearer test-key' && req.headers.authorization !== 'Bearer local-dev-key') {
        return send(401, { error: { message: 'bad key' } });
      }
      const request = JSON.parse(raw || '{}');
      calls.push({ path: req.url, body: request });
      if (req.url === '/v1/images/generations') return send(200, { data: [{ b64_json: TINY_JPEG }] });
      if (req.url !== '/v1/chat/completions') return send(404, { error: { message: 'not found' } });
      const text = JSON.stringify(request.messages);
      if (text.includes('FAIL_500')) return send(500, { error: { message: 'boom' } });
      if (text.includes('FAIL_429_ONCE') && !failedOnce.has(text)) {
        failedOnce.add(text);
        return send(429, { error: { message: 'rate limited' } });
      }
      const name = request.response_format?.json_schema?.name;
      const message = { role: 'assistant', content: JSON.stringify(answer(name, request)), refusal: null };
      if (text.includes('BAD_JSON')) message.content = '{not json';
      if (text.includes('REFUSE')) Object.assign(message, { content: null, refusal: 'I cannot help with that.' });
      const reply = { id: 'chatcmpl-fake', object: 'chat.completion', model: request.model, choices: [{ index: 0, message, finish_reason: text.includes('TRUNCATE') ? 'length' : 'stop' }], usage: { total_tokens: 123 } };
      if (text.includes('SLOW_REPLY')) return setTimeout(() => send(200, reply), slowMs);
      return send(200, reply);
    });
  });
  return new Promise((resolve) => {
    server.listen(port, '127.0.0.1', () => {
      const { port: actual } = server.address();
      resolve({ url: `http://127.0.0.1:${actual}/v1`, calls, close: () => new Promise((done) => { server.closeAllConnections?.(); server.close(done); }) });
    });
  });
}

/** RevenueCat stand-in: ids starting "premium" are subscribed, "expired" lapsed, "rcfail" errors. */
export function startFakeRevenueCat() {
  const server = http.createServer((req, res) => {
    const id = decodeURIComponent(req.url.split('/').pop() ?? '');
    const send = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.headers.authorization !== 'Bearer sk_test') return send(401, {});
    if (id.startsWith('rcfail')) return send(500, {});
    const entitlements = id.startsWith('premium') ? { premium: { expires_date: null } }
      : id.startsWith('expired') ? { premium: { expires_date: '2020-01-01T00:00:00Z' } } : {};
    return send(200, { subscriber: { entitlements } });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ url: `http://127.0.0.1:${server.address().port}/v1`, close: () => new Promise((done) => server.close(done)) }));
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const port = Number(process.env.PORT ?? 9911);
  startFakeOpenAI({ port }).then(({ url }) => console.log(`Fake OpenAI listening at ${url} (use OPENAI_API_KEY=local-dev-key)`));
}
