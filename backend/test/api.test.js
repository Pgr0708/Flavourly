import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { setup, stubFetcher, waitFor } from './helpers.js';

const RULES = { allergies: ['Peanuts'], diets: ['Vegetarian'], dislikes: ['mushrooms'], mildOnly: false };
const RECIPE_TEXT = 'Tomato soup\nIngredients\n- 4 tomatoes\n- 1 onion\n- 500 ml stock\nMethod\n1. Fry the onion for 5 min\n2. Simmer for 20 min';

let t;
let clock = new Date('2026-10-06T10:00:00Z'); // a Tuesday
before(async () => {
  t = await setup({
    now: () => clock,
    fetcher: stubFetcher({
      'https://www.tiktok.com/oembed': { json: { title: 'Garlic noodles 🍜\nIngredients\n200 g noodles\n4 cloves garlic\nMethod\n1. Boil the noodles for 5 min\n2. Toss with garlic', author_name: 'noodlequeen', thumbnail_url: 'https://p16.example/thumb.jpg' } },
    }),
    env: { FREE_IMPORTS_PER_WEEK: '3', FREE_AI_SWAPS_PER_WEEK: '2', FREE_EXTRACTS_PER_DAY: '50', RATE_LIMIT_PER_MINUTE: '1000' },
  });
});
after(() => t.teardown());

describe('health', () => {
  it('liveness and readiness report every dependency', async () => {
    assert.deepEqual((await t.api('/healthz', undefined, { method: 'GET' })).body, { ok: true });
    const ready = await t.api('/readyz', undefined, { method: 'GET' });
    assert.equal(ready.status, 200);
    assert.deepEqual(ready.body, { database: 'ok', redis: 'disabled', cache: 'memory', ai: 'configured' });
  });
  it('sends security headers, hides the framework and answers JSON 404s', async () => {
    const res = await t.api('/nope', undefined, { method: 'GET' });
    assert.equal(res.status, 404);
    assert.deepEqual(res.body, { error: 'Not found.' });
    assert.equal(res.headers.get('x-powered-by'), null);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(res.headers.get('x-request-id'));
  });
});

describe('devices (anonymous, no login)', () => {
  it('registers, authenticates and rotates the token for the same install', async () => {
    const id = 'AAAAAAAA-1111-2222-3333-444444444444';
    const first = await t.register(id);
    assert.match(first, /^[A-Za-z0-9_-]{43}$/);
    assert.equal((await t.api('/v1/ai/substitutes', { ingredient: '200 ml cream', recipeTitle: 'Pasta', rules: RULES }, { token: first })).status, 200);
    const second = await t.register(id);
    assert.notEqual(first, second);
    const stale = await t.api('/v1/ai/substitutes', { ingredient: '200 ml cream', recipeTitle: 'Pasta' }, { token: first });
    assert.equal(stale.status, 401, 'old token stops working');
    assert.match(stale.body.error, /session expired/);
    const [[{ count }]] = await t.deps.db.query('SELECT COUNT(*) AS count FROM devices WHERE install_id = ?', [id]);
    assert.equal(Number(count), 1, 'one row per install');
  });
  it('rejects missing, malformed and unknown tokens', async () => {
    for (const token of [undefined, 'abc', 'x'.repeat(43), '../etc/passwd']) {
      const res = await t.api('/v1/ai/plan', {}, { token });
      assert.equal(res.status, 401, String(token));
    }
  });
  it('validates registration input', async () => {
    const res = await t.api('/v1/devices', { installID: 'short', platform: 'android' });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'validation');
    assert.ok(res.body.fields.installID && res.body.fields.platform);
  });
  it('erase deletes the device and its usage; the app can register again', async () => {
    const token = await t.register();
    await t.api('/v1/ai/extract', { text: RECIPE_TEXT, kind: 'text' }, { token });
    const [[device]] = await t.deps.db.query('SELECT id FROM devices ORDER BY id DESC LIMIT 1');
    assert.equal((await t.api('/v1/devices/erase', {}, { token })).status, 200);
    const [[rows]] = await t.deps.db.query('SELECT COUNT(*) AS n FROM usage_counters WHERE device_id = ?', [device.id]);
    assert.equal(Number(rows.n), 0);
    assert.equal((await t.api('/v1/ai/extract', { text: RECIPE_TEXT }, { token })).status, 401);
    assert.match(await t.register(), /^[A-Za-z0-9_-]{43}$/);
  });
});

describe('request validation on every endpoint', () => {
  let token;
  before(async () => { token = await t.register(); });
  const cases = [
    ['/v1/imports', { url: 'ftp://example.com/x' }, 'url'],
    ['/v1/imports', { url: 'https://example.com/x', pageText: 'x'.repeat(20_001) }, 'pageText'],
    ['/v1/ai/extract', { text: 'short' }, 'text'],
    ['/v1/ai/extract', { text: RECIPE_TEXT, kind: 'video' }, 'kind'],
    ['/v1/ai/substitutes', { ingredient: '', recipeTitle: 'Pasta' }, 'ingredient'],
    ['/v1/ai/substitutes', { ingredient: '200 ml cream', recipeTitle: 'Pasta', otherIngredients: Array(101).fill('x') }, 'otherIngredients'],
    ['/v1/ai/cook-now', { minutes: 2 }, 'minutes'],
    ['/v1/ai/cook-now', { servings: 'two' }, 'servings'],
    ['/v1/ai/plan', { slots: [], candidates: [] }, 'slots'],
    ['/v1/ai/plan', { slots: [{ date: 'tomorrow', slot: 'dinner', candidates: [] }], candidates: [] }, 'slots.0.date'],
    ['/v1/images/recipe', { title: '1' }, 'title'],
    ['/v1/ai/substitutes', { ingredient: '200 ml cream', recipeTitle: 'Pasta', rules: { allergies: 'peanuts' } }, 'rules.allergies'],
  ];
  for (const [route, body, field] of cases) {
    it(`${route} rejects bad ${field}`, async () => {
      const res = await t.api(route, body, { token });
      assert.equal(res.status, 400, JSON.stringify(res.body));
      assert.equal(res.body.code, 'validation');
      assert.ok(res.body.fields[field], `expected a message for ${field}: ${JSON.stringify(res.body.fields)}`);
      assert.match(res.body.error, /^Please check /);
    });
  }
  it('rejects invalid JSON and oversized bodies', async () => {
    const bad = await t.api('/v1/ai/extract', undefined, { token, raw: '{"text": ' });
    assert.equal(bad.status, 400);
    assert.match(bad.body.error, /not valid JSON/);
    const big = await t.api('/v1/ai/extract', { text: 'a'.repeat(400_000) }, { token });
    assert.equal(big.status, 413);
  });
  it('cleans input before it reaches the AI (tags, invisible characters)', async () => {
    const res = await t.api('/v1/ai/substitutes', { ingredient: '<b>200 ml</b>​ cream', recipeTitle: 'Pasta <script>x</script>', rules: RULES }, { token });
    assert.equal(res.status, 200);
    const sent = JSON.parse(t.ai.calls.at(-1).body.messages[1].content);
    assert.equal(sent.replace, '200 ml cream');
    assert.equal(sent.recipe, 'Pasta x');
    assert.match(t.ai.calls.at(-1).body.messages[0].content, /Peanuts[\s\S]*Vegetarian[\s\S]*mushrooms/);
  });
});

describe('AI endpoints', () => {
  let token;
  before(async () => { token = await t.register(); });

  it('extract returns a draft the app can decode', async () => {
    const res = await t.api('/v1/ai/extract', { text: RECIPE_TEXT, kind: 'ocr' }, { token });
    assert.equal(res.status, 200);
    const { recipe } = res.body;
    assert.equal(recipe.title, 'Tomato soup');
    assert.equal(recipe.method, 'scan');
    assert.equal(recipe.ingredients.length, 3);
    assert.equal(recipe.steps.length, 2);
    assert.equal(recipe.steps[0].timerSeconds, 300);
    assert.deepEqual(Object.keys(recipe.nutrition).sort(), ['calories', 'carbs', 'fat', 'fiber', 'matched', 'protein', 'sodium', 'source', 'sugar', 'total']);
  });
  it('extract says clearly when there is no recipe', async () => {
    const res = await t.api('/v1/ai/extract', { text: 'NO_RECIPE just a nice day at the beach with friends' }, { token });
    assert.equal(res.status, 422);
    assert.match(res.body.error, /couldn't find a recipe/);
  });
  it('substitutes drop echoes and blanks, and are cached', async () => {
    const body = { ingredient: '1 cup heavy cream', recipeTitle: 'Alfredo', otherIngredients: ['pasta'], rules: RULES };
    const calls = t.ai.calls.length;
    const first = await t.api('/v1/ai/substitutes', body, { token });
    assert.deepEqual(first.body.options.map((o) => o.name), ['Greek yogurt', 'Oat cream']);
    assert.equal(first.body.options[1].flavour, undefined, 'nulls are omitted');
    const again = await t.api('/v1/ai/substitutes', body, { token });
    assert.deepEqual(again.body, first.body);
    assert.equal(t.ai.calls.length, calls + 1, 'second answer came from the cache');
  });
  it('cook-now keeps 3 safe ideas within the time limit and never repeats avoided titles', async () => {
    const res = await t.api('/v1/ai/cook-now', { minutes: 30, craving: 'rice', pantry: ['rice', 'eggs'], okToBuy: 2, servings: 3, rules: RULES, avoidTitles: ['Egg curry'] }, { token });
    assert.equal(res.status, 200);
    const titles = res.body.ideas.map((idea) => idea.recipe.title);
    assert.deepEqual(titles, ['Pantry fried rice', 'Quick dal']);
    assert.ok(res.body.ideas.every((idea) => idea.recipe.totalMinutes <= 35 && idea.recipe.method === 'ai' && idea.reason));
  });
  it('plan keeps only picks from each slot’s own shortlist', async () => {
    const res = await t.api('/v1/ai/plan', {
      slots: [{ date: '2026-10-06', slot: 'dinner', candidates: ['dal', 'pasta'] }, { date: '2026-10-07', slot: 'dinner', candidates: ['pasta'] }],
      candidates: [{ id: 'dal', title: 'Dal', minutes: 30, slots: ['dinner'], protein: 18 }, { id: 'pasta', title: 'Pasta', minutes: 20, slots: ['dinner'], protein: 12 }],
      preferences: ['High protein'], rules: RULES,
    }, { token });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.picks.map((p) => [p.date, p.recipeId]), [['2026-10-06', 'dal'], ['2026-10-07', 'pasta']]);
  });
  it('turns AI outages into friendly errors and does not charge a free use', async () => {
    const before = await t.deps.usage.used((await t.deps.devices.authenticate(token)).id, 'extract');
    const cases = [
      ['FAIL_500 soup recipe with tomatoes', 502, /busy/],
      ['BAD_JSON soup recipe with tomatoes', 502, /unreadable/],
      ['REFUSE soup recipe with tomatoes', 422, /couldn't help/],
      ['TRUNCATE soup recipe with tomatoes', 502, /too long/],
      ['SLOW_REPLY soup recipe with tomatoes', 504, /too long to answer/],
    ];
    for (const [text, status, message] of cases) {
      const res = await t.api('/v1/ai/extract', { text }, { token });
      assert.equal(res.status, status, text);
      assert.match(res.body.error, message, text);
    }
    const afterUse = await t.deps.usage.used((await t.deps.devices.authenticate(token)).id, 'extract');
    assert.equal(afterUse, before);
  });
  it('retries a rate-limited AI call and succeeds', async () => {
    const res = await t.api('/v1/ai/extract', { text: `FAIL_429_ONCE ${RECIPE_TEXT}` }, { token });
    assert.equal(res.status, 200);
  });
});

describe('free limits and Premium', () => {
  it('counts only successes, stops at the weekly limit and resets on Monday', async () => {
    const token = await t.register();
    const swap = (ingredient) => t.api('/v1/ai/substitutes', { ingredient, recipeTitle: 'Limit test', rules: {} }, { token });
    assert.equal((await swap('1 cup milk')).status, 200);
    assert.equal((await swap('2 eggs')).status, 200);
    const third = await swap('1 tbsp butter');
    assert.equal(third.status, 429);
    assert.equal(third.body.code, 'limit');
    assert.match(third.body.error, /this week's 2 free AI swaps.*Monday/);
    clock = new Date('2026-10-12T09:00:00Z'); // next Monday
    assert.equal((await swap('1 tbsp butter')).status, 200);
    clock = new Date('2026-10-06T10:00:00Z');
  });
  it('import limit applies to links, and failures are free', async () => {
    const token = await t.register();
    const tiktok = (n) => t.api('/v1/imports', { url: `https://www.tiktok.com/@noodlequeen/video/${n}?is_from_webapp=1` }, { token });
    const failed = await t.api('/v1/imports', { url: 'https://www.instagram.com/p/not-in-the-stub/' }, { token });
    assert.ok(failed.status >= 400, 'this import fails');
    for (let i = 0; i < 3; i += 1) assert.equal((await tiktok(100 + i)).status, 200, 'the failure did not use a free import');
    const blocked = await tiktok(200);
    assert.equal(blocked.status, 429);
    assert.match(blocked.body.error, /3 free link imports/);
  });
  it('Premium (verified with RevenueCat) is unlimited; lapsed or failing checks fall back to free', async () => {
    const token = await t.register();
    const swap = (user, ingredient) => t.api('/v1/ai/substitutes', { ingredient, recipeTitle: 'Premium test' }, { token, headers: { 'X-RC-App-User': user } });
    for (let i = 0; i < 4; i += 1) assert.equal((await swap('premium-user-1', `${i + 1} cups milk`)).status, 200);
    const lifetime = await t.register();
    for (let i = 0; i < 4; i += 1) {
      const res = await t.api('/v1/ai/substitutes', { ingredient: `${i + 1} tbsp butter`, recipeTitle: 'Lifetime' }, { token: lifetime, headers: { 'X-RC-App-User': 'lifetime-user' } });
      assert.equal(res.status, 200, 'the lifetime entitlement counts as Premium too');
    }
    const other = await t.register();
    const otherSwap = (n) => t.api('/v1/ai/substitutes', { ingredient: `${n} cups oat milk`, recipeTitle: 'Other' }, { token: other, headers: { 'X-RC-App-User': 'other-user' } });
    assert.equal((await otherSwap(1)).status, 200);
    assert.equal((await otherSwap(2)).status, 200);
    assert.equal((await otherSwap(3)).status, 429, 'an entitlement the app does not sell is not Premium');
    const lapsed = await t.register();
    const lapsedSwap = (ingredient) => t.api('/v1/ai/substitutes', { ingredient, recipeTitle: 'Lapsed' }, { token: lapsed, headers: { 'X-RC-App-User': 'expired-user' } });
    assert.equal((await lapsedSwap('1 cup milk')).status, 200);
    assert.equal((await lapsedSwap('2 cups milk')).status, 200);
    assert.equal((await lapsedSwap('3 cups milk')).status, 429);
    const weird = await t.api('/v1/ai/substitutes', { ingredient: '5 cups milk', recipeTitle: 'Bad header' }, { token: await t.register(), headers: { 'X-RC-App-User': 'bad user/../x' } });
    assert.equal(weird.status, 200, 'an invalid customer id is just treated as free');
  });
});

describe('images', () => {
  it('free-only lookups never use GPT and never use up the free plan', async () => {
    const token = await t.register();
    const gptCalls = t.ai.calls.filter((c) => c.path.includes('images')).length;
    for (let i = 0; i < 4; i += 1) {
      const res = await t.api('/v1/images/recipe', { title: 'Aunt Meera special stew', freeOnly: true }, { token });
      assert.equal(res.status, 404);
      assert.equal(res.body.code, 'no_photo');
    }
    assert.equal(t.ai.calls.filter((c) => c.path.includes('images')).length, gptCalls);
    const usage = await t.api('/v1/usage', {}, { token });
    assert.equal(usage.body.features.aiImage.used, 0);
  });
  it('creates a photo once and reuses the file', async () => {
    const token = await t.register();
    const first = await t.api('/v1/images/recipe', { title: 'Paneer tikka', description: 'smoky' }, { token });
    assert.equal(first.status, 200);
    assert.match(first.body.url, /^https:\/\/flavourly\.example\.com\/images\/[0-9a-f]{32}\.jpg#credit=AI-generated%20image$/);
    const file = path.join(t.config.IMAGE_DIR, path.basename(new URL(first.body.url).pathname));
    assert.ok((await fs.stat(file)).size > 0);
    const calls = t.ai.calls.filter((c) => c.path.includes('images')).length;
    const again = await t.api('/v1/images/recipe', { title: 'PANEER TIKKA' }, { token });
    assert.equal(again.body.url, first.body.url);
    assert.equal(t.ai.calls.filter((c) => c.path.includes('images')).length, calls);
    const served = await fetch(`${t.base}/images/${path.basename(new URL(first.body.url).pathname)}`);
    assert.equal(served.status, 200);
    assert.match(served.headers.get('cache-control'), /max-age=2592000/);
    assert.equal((await fetch(`${t.base}/images/..%2f..%2fpackage.json`)).status, 404, 'no path traversal');
  });
});

describe('local food (discover)', () => {
  let token;
  before(async () => { token = await t.register(); });
  const chats = () => t.ai.calls.filter((c) => c.path.includes('chat')).length;

  it('builds one catalogue per country: local dishes, staples and cravings', async () => {
    const res = await t.api('/v1/discover', { country: 'in' }, { token });
    assert.equal(res.status, 200);
    const { country, name, cuisine, staples, cravings, dishes } = res.body;
    assert.deepEqual([country, name, cuisine], ['IN', 'India', 'Indian']);
    assert.deepEqual(staples, ['Rice', 'Atta (wheat flour)', 'Toor dal'], 'trimmed and de-duplicated');
    assert.deepEqual(cravings, ['Biryani', 'Street food']);
    const titles = dishes.map((d) => d.title);
    assert.equal(titles.filter((title) => title === 'Shared dish').length, 1, 'duplicates across groups removed');
    assert.ok(!titles.includes('No steps'), 'incomplete dishes dropped');
    assert.ok(dishes.length >= 6);
    assert.ok(dishes.every((d) => d.remoteID.startsWith('local-in-') && d.cuisine === 'Indian' && d.method === 'local'));
    assert.ok(dishes.some((d) => d.tags.includes('Coastal')), 'region becomes a tag');
  });

  it('serves every later request from the shared cache and paints photos in the background', async () => {
    const calls = chats();
    await waitFor(async () => (await t.api('/v1/discover', { country: 'IN' }, { token })).body.dishes.every((d) => d.imageURL), 10_000);
    const res = await t.api('/v1/discover', { country: 'IN' }, { token });
    assert.ok(res.body.dishes.every((d) => /^https:\/\/flavourly\.example\.com\/images\/[0-9a-f]{32}\.jpg#credit=AI-generated%20image$/.test(d.imageURL)));
    assert.equal(chats(), calls, 'no new AI text calls');
    const other = await t.register();
    assert.equal((await t.api('/v1/discover', { country: 'IN' }, { token: other })).status, 200);
    assert.equal(chats(), calls, 'shared across devices');
  });

  it('builds the same country once even when many devices ask at the same time', async () => {
    const calls = chats();
    const results = await Promise.all([1, 2, 3, 4].map(() => t.api('/v1/discover', { country: 'MX' }, { token })));
    assert.ok(results.every((r) => r.status === 200));
    assert.equal(chats(), calls + 8, 'one build: 7 dish groups + 1 kitchen call');
  });

  it('rejects codes that are not countries, with a readable message', async () => {
    for (const country of ['XX', 'EU', 'india', '', 'I N', 42]) {
      const res = await t.api('/v1/discover', { country }, { token });
      assert.equal(res.status, 400, String(country));
      assert.ok(res.body.error && res.body.fields?.country, String(country));
    }
  });

  it('says so when no dishes came back, and does not cache the failure', async () => {
    const res = await t.api('/v1/discover', { country: 'NP' }, { token });
    assert.equal(res.status, 502);
    assert.match(res.body.error, /Nepal/);
    assert.equal(await t.deps.cache.get('discover:v2:NP'), null);
  });

  it('Cook Now asks for dishes from the cook\'s country', async () => {
    const res = await t.api('/v1/ai/cook-now', { minutes: 30, craving: '', pantry: ['rice'], okToBuy: 2, servings: 2, rules: RULES, country: 'jp' }, { token });
    assert.equal(res.status, 200);
    const system = t.ai.calls.filter((c) => c.path.includes('chat')).at(-1).body.messages[0].content;
    assert.match(system, /lives in Japan/);
    assert.equal((await t.api('/v1/ai/cook-now', { pantry: [], rules: RULES, country: 'ZZ' }, { token })).status, 400);
  });
});

describe('rate limiting', () => {
  it('limits requests per device per minute and new sessions per network', async () => {
    const strict = await setup({ env: { RATE_LIMIT_PER_MINUTE: '3', REGISTRATIONS_PER_HOUR: '4' } });
    try {
      const token = await strict.register();
      const statuses = [];
      for (let i = 0; i < 5; i += 1) statuses.push((await strict.api('/v1/ai/plan', {}, { token })).status);
      assert.deepEqual(statuses, [400, 400, 400, 429, 429]);
      const limited = await strict.api('/v1/ai/plan', {}, { token });
      assert.ok(Number(limited.headers.get('retry-after')) > 0);
      for (let i = 0; i < 3; i += 1) await strict.register();
      const tooMany = await strict.api('/v1/devices', { installID: 'BBBBBBBB-1111-2222-3333-444444444444' });
      assert.equal(tooMany.status, 429);
    } finally {
      await strict.teardown();
    }
  });
});
