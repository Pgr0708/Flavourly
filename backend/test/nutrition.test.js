import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { createCache } from '../src/cache.js';
import { createNutrition, hasNutrients, parseLine, pickFood, singular } from '../src/nutrition.js';
import { fakeFoodApis } from './fake-openai.js';
import { setup, stubFetcher } from './helpers.js';

describe('ingredient line parser', () => {
  const cases = [
    ['3 eggs', 3, null, 'eggs'],
    ['1 1/2 cups plain flour, sifted', 1.5, 'cup', 'plain flour'],
    ['½ tsp salt', 0.5, 'tsp', 'salt'],
    ['1½ tbsp olive oil', 1.5, 'tbsp', 'olive oil'],
    ['200g paneer, cubed', 200, 'g', 'paneer'],
    ['2-3 cloves garlic, minced', 2.5, 'clove', 'garlic'],
    ['1 large onion, finely chopped', 1, null, 'onion'],
    ['1 Tbsp butter', 1, 'tbsp', 'butter'],
    ['1 can (400 g) chickpeas', 1, 'can', '400 g chickpeas'],
    ['Salt to taste', null, null, 'salt'],
    ['2 kg of potatoes', 2, 'kg', 'potatoes'],
    ['1,5 l milk', 1.5, 'l', 'milk'],
    ['200 g cooked white rice', 200, 'g', 'cooked white rice'], // cooking state changes calories ~3×
    ['250 g raw chicken breast, diced', 250, 'g', 'raw chicken breast'],
    ['1 cup chickpeas, cooked', 1, 'cup', 'cooked chickpeas'],
    ['1 can chickpeas, drained and rinsed', 1, 'can', 'chickpeas'],
  ];
  for (const [line, quantity, unit, name] of cases) {
    it(line, () => assert.deepEqual(parseLine(line), { quantity, unit, name }));
  }
});

describe('choosing the right USDA food (real search results)', () => {
  const pick = (query, descriptions) => pickFood(query, descriptions.map((description) => ({ description })))?.description;
  it('egg → the whole egg, not egg white, yolk or bagels', () => {
    assert.equal(pick('egg', ['Eggs, Grade A, Large, egg white', 'Eggs, Grade A, Large, egg whole', 'Eggs, Grade A, Large, egg yolk', 'Bagels, egg']),
      'Eggs, Grade A, Large, egg whole');
  });
  it('white rice → uncooked rice, not rice flour or cooked rice', () => {
    assert.equal(pick('white rice', ['Flour, rice, white, unenriched', 'Rice flour, white, unenriched', 'Rice, white, glutinous, unenriched, cooked', 'Rice, white, glutinous, unenriched, uncooked']),
      'Rice, white, glutinous, unenriched, uncooked');
  });
  it('olive oil → olive oil, not a corn/peanut blend', () => {
    assert.equal(pick('olive oil', ['Oil, corn, peanut, and olive', 'Oil, olive, salad or cooking']), 'Oil, olive, salad or cooking');
  });
  it('onion → raw onion, not restaurant onion rings or dried flakes', () => {
    assert.equal(pick('onion', ['DENNY\'S, onion rings', 'Onions, dehydrated flakes', 'Onions, raw']), 'Onions, raw');
  });
  it('cooked white rice → regular rice, not sticky (glutinous) rice listed first', () => {
    assert.equal(pick('cooked white rice', ['Rice, white, glutinous, unenriched, cooked', 'Rice, white, medium-grain, cooked, unenriched', 'Rice, white, long-grain, regular, enriched, cooked']),
      'Rice, white, medium-grain, cooked, unenriched');
    assert.equal(pick('glutinous rice', ['Rice, white, long-grain, regular, raw', 'Rice, white, glutinous, unenriched, uncooked']), 'Rice, white, glutinous, unenriched, uncooked');
  });
  it('the main food leads USDA names: milk is not "Crackers, milk", salt is not "Butter, salted"', () => {
    assert.equal(pick('milk', ['Crackers, milk', 'Candies, milk chocolate', 'Milk, sheep, fluid', 'Milk, whole, 3.25% milkfat, with added vitamin D']), 'Milk, whole, 3.25% milkfat, with added vitamin D');
    assert.equal(pick('salt', ['Butter, salted', 'Salt, table', 'Fish, mackerel, salted']), 'Salt, table');
    assert.equal(pick('butter', ['Butter, Clarified butter (ghee)', 'Butter, salted', 'Croissants, butter', 'Almond butter, creamy']), 'Butter, salted');
    assert.equal(pick('canned tomatoes', ['Tomato, puree, canned', 'Tomatoes, red, ripe, canned, packed in tomato juice']), 'Tomatoes, red, ripe, canned, packed in tomato juice');
    assert.equal(pick('ghee', ['Butter, salted', 'Butter, Clarified butter (ghee)']), 'Butter, Clarified butter (ghee)');
  });
  it('a dish built on the food is not the food (milk bar, potato pancakes, peas and carrots)', () => {
    assert.equal(pick('milk', ['Milk and cereal bar', 'Milk, whole, 3.25% milkfat, with added vitamin D']), 'Milk, whole, 3.25% milkfat, with added vitamin D');
    assert.equal(pick('potato', ['Potato pancakes', 'Potatoes, flesh and skin, raw']), 'Potatoes, flesh and skin, raw');
    assert.equal(pick('frozen pea', ['Peas and carrots, frozen, unprepared', 'Peas, green, frozen, unprepared']), 'Peas, green, frozen, unprepared');
  });
  it('parts and pod varieties only when asked (potato skin, snow peas)', () => {
    assert.equal(pick('potato', ['Potatoes, raw, skin', 'Potatoes, flesh and skin, raw']), 'Potatoes, flesh and skin, raw');
    assert.equal(pick('potato', ['Potatoes, hash brown, home-prepared', 'Potatoes, mashed, ready-to-eat', 'Potatoes, flesh and skin, raw']), 'Potatoes, flesh and skin, raw');
    assert.equal(pick('frozen pea', ['Peas, edible-podded, frozen, unprepared', 'Peas, green, frozen, unprepared']), 'Peas, green, frozen, unprepared');
    assert.equal(pick('cumin seed', ['Spices, cumin seed']), 'Spices, cumin seed');
    assert.equal(pick('cooked chickpea', ['Chickpeas (garbanzo beans, bengal gram), mature seeds, raw', 'Chickpeas (garbanzo beans, bengal gram), mature seeds, cooked, boiled, without salt']),
      'Chickpeas (garbanzo beans, bengal gram), mature seeds, cooked, boiled, without salt');
  });
  it('foods listed without nutrient values are skipped (USDA Foundation olive oil)', () => {
    const value = (nutrientNumber, v) => ({ nutrientNumber, value: v });
    assert.equal(hasNutrients({ foodNutrients: [] }), false);
    assert.equal(hasNutrients({ foodNutrients: [value('208', 884), value('204', 100)] }), true);
    assert.equal(hasNutrients({ foodNutrients: [value('204', 100)] }), true);
  });
  it('asking for a form keeps it (cooked rice, egg white)', () => {
    assert.equal(pick('cooked rice', ['Rice, white, long-grain, regular, raw', 'Rice, white, long-grain, regular, cooked']), 'Rice, white, long-grain, regular, cooked');
    assert.equal(pick('egg white', ['Egg, whole, raw, fresh', 'Egg, white, raw, fresh']), 'Egg, white, raw, fresh');
  });
  it('no plausible match → null (Spoonacular or the AI label takes over)', () => {
    assert.equal(pick('paneer', ['Cheese, cottage, creamed', 'Babyfood, dessert, custard']), undefined);
  });
});

describe('verified nutrition', () => {
  const make = (env = {}) => {
    const food = fakeFoodApis();
    const config = { USDA_API_KEY: 'test', SPOONACULAR_API_KEY: '', ...env };
    return { food, nutrition: createNutrition({ config, cache: createCache(), http: food.http }) };
  };

  it('uses USDA values and household portions (3 eggs = 3 × 44 g medium, 1 cup rice = 185 g)', async () => {
    const { nutrition } = make();
    const result = await nutrition.forLines(['3 eggs', '1 cup rice', '1 tbsp olive oil', 'salt to taste'], 1);
    // eggs 3×44 g (medium is the default) + rice 185 g + oil 13.5 g
    const kcal = 1.43 * 132 + 3.65 * 185 + 8.84 * 13.5;
    assert.equal(result.calories, Math.round(kcal));
    assert.equal(result.source, 'USDA FoodData Central');
    assert.deepEqual([result.matched, result.total], [3, 3], '"to taste" lines are not counted');
  });

  it('divides by servings', async () => {
    const { nutrition } = make();
    const one = await nutrition.forLines(['1 onion', '2 eggs'], 1);
    const four = await nutrition.forLines(['1 onion', '2 eggs'], 4);
    assert.ok(Math.abs(one.calories / 4 - four.calories) <= 1);
  });

  it('never matches a different food (decoy search result is ignored)', async () => {
    const { nutrition } = make();
    assert.equal(await nutrition.forLines(['200 g eggplant', '1 tbsp dragonfruit jam'], 2), null, 'nothing verified → null');
  });

  it('fills unmatched lines from Spoonacular when a key is set', async () => {
    const { nutrition, food } = make({ SPOONACULAR_API_KEY: 'sk' });
    const result = await nutrition.forLines(['200 g paneer', '1 onion'], 1);
    assert.equal(result.source, 'USDA + Spoonacular');
    assert.deepEqual([result.matched, result.total], [2, 2]);
    assert.equal(result.calories, 265 + Math.round(0.4 * 110));
    assert.ok(food.calls.some((c) => c.host === 'api.spoonacular.com' && c.body.includes('paneer')));
  });

  it('returns null below the coverage bar instead of guessing', async () => {
    const { nutrition } = make();
    assert.equal(await nutrition.forLines(['1 onion', '100 g paneer', '50 g ghee', '2 tbsp kasuri methi'], 2), null);
  });

  it('caches every food: a second recipe makes no new USDA calls', async () => {
    const { nutrition, food } = make();
    await nutrition.forLines(['2 eggs', '1 onion'], 2);
    const before = food.calls.length;
    await nutrition.forLines(['4 eggs', '2 onions'], 2);
    assert.equal(food.calls.length, before);
  });

  it('survives USDA outages: enrich keeps the AI numbers, labelled', async () => {
    const { nutrition } = make({ USDA_API_KEY: 'RATE_LIMITED' });
    const draft = { servings: 2, ingredients: [{ text: '2 eggs' }], nutrition: { calories: 300, matched: 1, total: 1 } };
    const out = await nutrition.enrich(draft);
    assert.equal(out.nutrition.calories, 300);
    assert.equal(out.nutrition.source, 'AI estimate');
  });
});

describe('/v1/nutrition and /v1/usage', () => {
  let t;
  let token;
  before(async () => { t = await setup(); token = await t.register(); });
  after(() => t.teardown());

  it('recalculates nutrition for edited ingredient lines', async () => {
    const res = await t.api('/v1/nutrition', { lines: ['3 eggs', '1 onion'], servings: 1 }, { token });
    assert.equal(res.status, 200);
    assert.equal(res.body.nutrition.source, 'USDA FoodData Central');
    assert.equal(res.body.nutrition.calories, Math.round(1.43 * 132 + 0.4 * 110));
  });
  it('answers null (not a guess) when nothing can be verified', async () => {
    const res = await t.api('/v1/nutrition', { lines: ['1 tbsp mystery sauce'] }, { token });
    assert.equal(res.status, 200);
    assert.equal(res.body.nutrition, null);
  });
  it('validates the lines', async () => {
    for (const body of [{ lines: [] }, { lines: Array(101).fill('1 egg') }, { lines: ['x'.repeat(201)] }, { lines: ['1 egg'], servings: 0 }]) {
      assert.equal((await t.api('/v1/nutrition', body, { token })).status, 400, JSON.stringify(body).slice(0, 60));
    }
  });
  it('scanned recipes carry verified nutrition', async () => {
    const res = await t.api('/v1/ai/extract', { text: 'Egg fried rice\nIngredients\n- 1 cup rice\n- 2 eggs\n- 1 onion\nMethod\n1. Fry for 5 min', kind: 'ocr' }, { token });
    assert.equal(res.status, 200);
    assert.equal(res.body.recipe.nutrition.source, 'USDA FoodData Central');
  });
  it('reports the server-side free counters', async () => {
    const res = await t.api('/v1/usage', {}, { token });
    assert.equal(res.status, 200);
    assert.equal(res.body.premium, false);
    assert.equal(res.body.features.extract.used, 1, 'the scan above was counted');
    assert.deepEqual(Object.keys(res.body.features).sort(), ['aiIdeas', 'aiImage', 'aiPlan', 'aiSwap', 'extract', 'importRecipe']);
  });
});

describe('local dishes are checked against Wikipedia', () => {
  let t;
  let token;
  const wiki = (url) => {
    const query = new URL(url).searchParams.get('srsearch');
    // Wikipedia knows everything except the invented "regional special"; Peru's coverage is "thin".
    if (/regional special/.test(query)) return { query: { search: [{ title: 'Regional variation' }] } };
    if (/Peru/.test(query)) return { query: { search: [] } };
    return { query: { search: [{ title: query.replace(/ India food$/, '') }] } };
  };
  before(async () => {
    t = await setup({ fetcher: stubFetcher({ 'https://en.wikipedia.org/w/api.php': wiki }), env: { RATE_LIMIT_PER_MINUTE: '1000' } });
    token = await t.register();
  });
  after(() => t.teardown());

  it('drops dishes no encyclopedia has heard of', async () => {
    const res = await t.api('/v1/discover', { country: 'IN' }, { token });
    assert.equal(res.status, 200);
    const titles = res.body.dishes.map((d) => d.title);
    assert.ok(!titles.includes('regional special'), 'invented dish removed');
    assert.ok(titles.includes('breakfast special') && titles.includes('Shared dish'));
  });
  it('keeps everything when Wikipedia would drop more than half (thin coverage)', async () => {
    const res = await t.api('/v1/discover', { country: 'PE' }, { token });
    assert.equal(res.status, 200);
    assert.ok(res.body.dishes.some((d) => d.title === 'regional special'));
  });
});
