// Premium "make it my way" variations: moderation, weekly cap, saved and shown to cooks nearby.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { setup, stubFetcher } from './helpers.js';

const PREMIUM = { 'X-RC-App-User': 'premium-cook' };
const base = {
  title: 'Aloo Puri',
  servings: 2,
  ingredients: ['4 potatoes', '300 g wheat flour', '1 tsp cumin'],
  steps: ['Boil the potatoes', 'Fry the puris'],
  imageURL: 'https://flavourly.example.com/images/aloo.jpg',
};
let t;
before(async () => { t = await setup({ fetcher: stubFetcher({}), env: { PREMIUM_VARIATIONS_PER_WEEK: '2', RATE_LIMIT_PER_MINUTE: '1000' } }); });
after(() => t.teardown());

const make = (token, change, extra = {}) => t.api('/v1/variations', { base, change, country: 'IN', region: 'Gujarat', ...extra }, { token, headers: PREMIUM });

describe('POST /v1/variations', () => {
  it('free cooks are told it is Premium, and OpenAI is never called', async () => {
    const before = t.ai.calls.length;
    const res = await t.api('/v1/variations', { base, change: 'add paneer', country: 'IN' }, { token: await t.register() });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'premium');
    assert.equal(t.ai.calls.length, before);
  });
  it('Premium gets a whole new recipe with a new name, saved with the original photo when no free one exists', async () => {
    const res = await make(await t.register(), 'add paneer');
    assert.equal(res.status, 200);
    const { variation } = res.body;
    assert.equal(variation.title, 'Paneer Aloo Puri');
    assert.equal(variation.change, 'add paneer');
    assert.equal(variation.region, 'Gujarat');
    assert.ok(variation.recipe.ingredients.length >= 3 && variation.recipe.steps.length >= 2);
    assert.equal(variation.recipe.imageURL, base.imageURL);
    assert.match(variation.recipe.remoteID, /^variation-\d+$/);
    assert.ok(!t.ai.calls.some((c) => c.path === '/v1/images/generations'), 'never a GPT photo');
  });
  it('refuses unsafe words (moderation) and changes that are not about food, without using a credit', async () => {
    const token = await t.register();
    const flagged = await make(token, 'FLAG_ME please');
    assert.equal(flagged.status, 422);
    assert.equal(flagged.body.code, 'unsafe');
    const silly = await make(token, 'not food at all');
    assert.equal(silly.status, 422);
    assert.equal(silly.body.code, 'bad_change');
    assert.equal((await make(token, 'air fryer')).status, 200, 'failures did not use the weekly cap');
  });
  it('weekly cap per Premium device', async () => {
    const token = await t.register();
    assert.equal((await make(token, 'less spicy')).status, 200);
    assert.equal((await make(token, 'more garlic')).status, 200);
    const third = await make(token, 'extra crispy');
    assert.equal(third.status, 429);
    assert.match(third.body.error, /2 recipe variations.*Monday/);
  });
  it('validates the request', async () => {
    const token = await t.register();
    for (const body of [{ base, change: '' }, { base: { ...base, ingredients: [] }, change: 'add paneer' }, { base, change: 'x'.repeat(201) }, { base, change: 'add paneer', country: 'XX' }]) {
      assert.equal((await t.api('/v1/variations', body, { token, headers: PREMIUM })).status, 400, JSON.stringify(body).slice(0, 80));
    }
  });
});

describe('versions made nearby', () => {
  it('lists versions from the same country, own region first; other countries never see them', async () => {
    const token = await t.register();
    await make(token, 'with cheese', { region: 'Kerala' });
    const list = await t.api('/v1/variations/list', { title: 'alu poori', country: 'IN', region: 'Gujarat' }, { token: await t.register() });
    assert.equal(list.status, 200);
    const { variations } = list.body;
    assert.ok(variations.length >= 4);
    assert.equal(variations[0].region, 'Gujarat');
    assert.equal(variations.at(-1).region, 'Kerala');
    const elsewhere = await t.api('/v1/variations/list', { title: 'Aloo Puri', country: 'US' }, { token });
    assert.deepEqual(elsewhere.body.variations, []);
  });
  it('"I tried it" counts once per device and moves popular versions up', async () => {
    const token = await t.register();
    const { variations } = (await t.api('/v1/variations/list', { title: 'Aloo Puri', country: 'IN', region: 'Kerala' }, { token })).body;
    const id = variations.at(-1).id;
    assert.equal((await t.api('/v1/variations/tried', { id }, { token })).body.tried, 1);
    assert.equal((await t.api('/v1/variations/tried', { id }, { token })).body.tried, 1, 'same device twice');
    assert.equal((await t.api('/v1/variations/tried', { id }, { token: await t.register() })).body.tried, 2);
    assert.equal((await t.api('/v1/variations/tried', { id: '999999' }, { token })).status, 404);
    assert.equal((await t.api('/v1/variations/tried', { id: 'abc' }, { token })).status, 400);
  });
  it('erasing a device removes the versions it made', async () => {
    const token = await t.register();
    const made = (await make(token, 'no onion garlic')).body.variation;
    await t.api('/v1/devices/erase', {}, { token });
    const [[row]] = await t.deps.db.query('SELECT COUNT(*) AS n FROM variations WHERE id = ?', [made.id]);
    assert.equal(Number(row.n), 0);
  });
});
