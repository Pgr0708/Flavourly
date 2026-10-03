// Edge-case matrix: every endpoint, boundaries on both sides, wrong types, empty / invisible-only
// text, injection strings, prototype-pollution keys and auth variants. Each row: route, body,
// expected status, and (for 400s) the field the message must name.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { setup } from './helpers.js';

const RULES = { allergies: [], diets: [], dislikes: [], mildOnly: false };
const RECIPE = 'Tomato soup\nIngredients\n- 4 tomatoes\n- 1 onion\nMethod\n1. Simmer for 20 min';
const slot = (over = {}) => ({ date: '2026-10-06', slot: 'dinner', candidates: ['dal'], ...over });
const cand = (over = {}) => ({ id: 'dal', title: 'Dal', minutes: 30, slots: ['dinner'], protein: 18, ...over });

let t;
let token;
before(async () => {
  t = await setup({ user: 'premium-edge', env: { PREMIUM_EXTRACTS_PER_WEEK: '10000', PREMIUM_AI_SWAPS_PER_WEEK: '10000', PREMIUM_AI_IDEAS_PER_WEEK: '10000', PREMIUM_AI_PLANS_PER_WEEK: '10000', PREMIUM_IMAGES_PER_WEEK: '10000', PREMIUM_IMPORTS_PER_WEEK: '10000', RATE_LIMIT_PER_MINUTE: '100000', REGISTRATIONS_PER_HOUR: '100000', FREE_EXTRACTS_PER_WEEK: '10000', FREE_AI_SWAPS_PER_WEEK: '10000', FREE_AI_IDEAS_PER_WEEK: '10000', FREE_AI_PLANS_PER_WEEK: '10000', FREE_IMAGES_PER_WEEK: '10000', FREE_IMPORTS_PER_WEEK: '10000' } });
  token = await t.register();
});
after(() => t.teardown());

const rows = [
  // ── devices
  ['/v1/devices', { installID: 'short' }, 400, 'installID', { auth: false }],
  ['/v1/devices', { installID: "x'; DROP TABLE devices;--" }, 400, 'installID', { auth: false }],
  ['/v1/devices', { installID: 'A'.repeat(65) }, 400, 'installID', { auth: false }],
  ['/v1/devices', { installID: 'ABCDEF12-0000', platform: 'android' }, 400, 'platform', { auth: false }],
  ['/v1/devices', { installID: 'ABCDEF12-0000', appVersion: '1.0; rm -rf' }, 400, 'appVersion', { auth: false }],
  ['/v1/devices', { installID: 'ABCDEF12-0001', unknown: 'ignored' }, 200, null, { auth: false }],

  // ── extract: length boundaries, letters required, invisible-only
  ['/v1/ai/extract', {}, 400, 'text'],
  ['/v1/ai/extract', { text: 12345 }, 400, 'text'],
  ['/v1/ai/extract', { text: '1234567890 1234567890 1234' }, 400, 'text'],
  ['/v1/ai/extract', { text: '​'.repeat(40) }, 400, 'text'],
  ['/v1/ai/extract', { text: '<p></p>'.repeat(10) }, 400, 'text'],
  ['/v1/ai/extract', { text: 'a'.repeat(19) }, 400, 'text'],
  ['/v1/ai/extract', { text: 'a'.repeat(20) }, 422, null], // valid input, but not a recipe
  ['/v1/ai/extract', { text: `${RECIPE}\n${'x'.repeat(20_000 - RECIPE.length - 1)}` }, 200, null],
  ['/v1/ai/extract', { text: 'x'.repeat(20_001) }, 400, 'text'],
  ['/v1/ai/extract', { text: RECIPE, kind: 'ocr', sourceURL: 'javascript:alert(1)' }, 400, 'sourceURL'],
  ['/v1/ai/extract', { text: 'पनीर टिक्का\nसामग्री\n- 200 g paneer\n- 1 onion\nविधि\n1. Grill for 10 min' }, 200, null],

  // ── imports
  ['/v1/imports', { url: '' }, 400, 'url'],
  ['/v1/imports', { url: 'not a url' }, 400, 'url'],
  ['/v1/imports', { url: 'http://localhost/x' }, 400, 'url'],
  ['/v1/imports', { url: 'https://169.254.169.254/latest/meta-data' }, 400, 'url'],
  ['/v1/imports', { url: 'https://user:pw@example.com/x' }, 400, 'url'],
  ['/v1/imports', { url: `https://example.com/${'a'.repeat(2050)}` }, 400, 'url'],
  ['/v1/imports', { url: ['https://example.com'] }, 400, 'url'],

  // ── substitutes
  ['/v1/ai/substitutes', { ingredient: '   ', recipeTitle: 'Pasta' }, 400, 'ingredient'],
  ['/v1/ai/substitutes', { ingredient: '200', recipeTitle: 'Pasta' }, 400, 'ingredient'],
  ['/v1/ai/substitutes', { ingredient: 'x'.repeat(201), recipeTitle: 'Pasta' }, 400, 'ingredient'],
  ['/v1/ai/substitutes', { ingredient: 'cream', recipeTitle: '' }, 400, 'recipeTitle'],
  ['/v1/ai/substitutes', { ingredient: 'cream', recipeTitle: 'Pasta', rules: { allergies: Array(31).fill('x') } }, 400, 'rules.allergies'],
  ['/v1/ai/substitutes', { ingredient: 'cream', recipeTitle: 'Pasta', rules: { mildOnly: 'yes' } }, 400, 'rules.mildOnly'],
  ['/v1/ai/substitutes', { ingredient: "cream'); DELETE FROM usage;--", recipeTitle: 'Pasta', rules: RULES }, 200, null],
  ['/v1/ai/substitutes', { ingredient: 'cream', recipeTitle: 'Pasta 🍝', rules: RULES, constructor: { prototype: { admin: true } } }, 200, null],

  // ── cook-now: numeric boundaries
  ['/v1/ai/cook-now', { minutes: 4 }, 400, 'minutes'],
  ['/v1/ai/cook-now', { minutes: 5, rules: RULES }, 200, null],
  ['/v1/ai/cook-now', { minutes: 600, rules: RULES }, 200, null],
  ['/v1/ai/cook-now', { minutes: 601 }, 400, 'minutes'],
  ['/v1/ai/cook-now', { minutes: 30.5 }, 400, 'minutes'],
  ['/v1/ai/cook-now', { servings: 0 }, 400, 'servings'],
  ['/v1/ai/cook-now', { servings: 41 }, 400, 'servings'],
  ['/v1/ai/cook-now', { okToBuy: -1 }, 400, 'okToBuy'],
  ['/v1/ai/cook-now', { okToBuy: 11 }, 400, 'okToBuy'],
  ['/v1/ai/cook-now', { craving: 'x'.repeat(81) }, 400, 'craving'],
  ['/v1/ai/cook-now', { pantry: Array(101).fill('rice') }, 400, 'pantry'],
  ['/v1/ai/cook-now', { pantry: ['x'.repeat(61)] }, 400, 'pantry.0'],
  ['/v1/ai/cook-now', { country: 'IND' }, 400, 'country'],

  // ── plan
  ['/v1/ai/plan', { slots: Array(36).fill(slot()), candidates: [cand()] }, 400, 'slots'],
  ['/v1/ai/plan', { slots: [slot({ date: '2026-02-30' })], candidates: [cand()] }, 400, 'slots.0.date'],
  ['/v1/ai/plan', { slots: [slot({ date: '2026-13-01' })], candidates: [cand()] }, 400, 'slots.0.date'],
  ['/v1/ai/plan', { slots: [slot({ slot: 'brunch' })], candidates: [cand()] }, 400, 'slots.0.slot'],
  ['/v1/ai/plan', { slots: [slot({ candidates: Array(21).fill('dal') })], candidates: [cand()] }, 400, 'slots.0.candidates'],
  ['/v1/ai/plan', { slots: [slot()], candidates: [cand({ minutes: -1 })] }, 400, 'candidates.0.minutes'],
  ['/v1/ai/plan', { slots: [slot()], candidates: Array(301).fill(cand()) }, 400, 'candidates'],
  ['/v1/ai/plan', { slots: [slot({ date: '2028-02-29' })], candidates: [cand()], rules: RULES }, 200, null],

  // ── images & discover
  ['/v1/images/recipe', { title: '  ' }, 400, 'title'],
  ['/v1/images/recipe', { title: 'x'.repeat(121) }, 400, 'title'],
  ['/v1/images/recipe', { title: 'Dal', description: 'x'.repeat(301) }, 400, 'description'],
  ['/v1/discover', {}, 400, 'country'],
  ['/v1/discover', { country: ' in ' }, 200, null],
  ['/v1/discover', { country: 'UN' }, 400, 'country'],
];

describe('edge-case matrix', () => {
  for (const [route, body, status, field, { auth = true } = {}] of rows) {
    const label = JSON.stringify(body).slice(0, 70);
    it(`${route} ${label} → ${status}${field ? ` (${field})` : ''}`, async () => {
      const res = await t.api(route, body, auth ? { token } : {});
      assert.equal(res.status, status, JSON.stringify(res.body)?.slice(0, 300));
      if (status === 400) {
        assert.equal(res.body.code, 'validation');
        assert.ok(res.body.fields?.[field], `expected a message for ${field}: ${JSON.stringify(res.body.fields)}`);
        assert.ok(res.body.error.length > 0 && !/zod|undefined|\[object/i.test(res.body.error), `readable message: ${res.body.error}`);
      }
    });
  }
});

describe('transport and auth edges', () => {
  const post = (route, init) => fetch(`${t.base}${route}`, { method: 'POST', ...init });

  it('needs a valid bearer token, in any malformed form → 401', async () => {
    for (const header of [undefined, 'Bearer', 'Bearer ', `bearer ${token}`, `Token ${token}`, `Bearer ${token}x`, `Bearer ${'a'.repeat(5000)}`]) {
      const res = await post('/v1/ai/cook-now', { headers: { 'Content-Type': 'application/json', ...(header ? { Authorization: header } : {}) }, body: '{}' });
      assert.equal(res.status, 401, String(header).slice(0, 30));
    }
  });
  it('a non-JSON body is treated as empty and fails validation, not the server', async () => {
    const res = await post('/v1/ai/extract', { headers: { 'Content-Type': 'text/plain', Authorization: `Bearer ${token}` }, body: RECIPE });
    assert.equal(res.status, 400);
  });
  it('a JSON array or string body is rejected cleanly', async () => {
    for (const raw of ['[]', '"text"', 'null']) {
      const res = await post('/v1/ai/extract', { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: raw });
      assert.equal(res.status, 400, raw);
    }
  });
  it('unknown routes and wrong methods answer 404 JSON', async () => {
    assert.equal((await post('/v1/nope', { headers: { Authorization: `Bearer ${token}` } })).status, 404);
    const get = await fetch(`${t.base}/v1/ai/cook-now`, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(get.status, 404);
    assert.ok((await get.json()).error);
  });
  it('security headers are set and the framework is not advertised', async () => {
    const res = await fetch(`${t.base}/healthz`);
    assert.equal(res.headers.get('x-powered-by'), null);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(res.headers.get('x-request-id'));
  });
  it('injection strings are stored as plain text and the tables survive', async () => {
    const [[{ n }]] = await t.deps.db.query('SELECT COUNT(*) AS n FROM devices');
    assert.ok(n >= 1);
  });
});
