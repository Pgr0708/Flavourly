import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { dishSlug, matchScore, soundKey } from '../src/dishes.js';
import { setup, stubFetcher } from './helpers.js';

// Search any dish: autocomplete from each country's dish names, recipes from a shared library
// (TheMealDB, else AI once), and recipe videos.
let t;
let token;
const chats = () => t.ai.calls.filter((c) => c.path.includes('chat')).length;

before(async () => {
  const fetcher = stubFetcher({
    'https://www.themealdb.com/': (url) => (url.includes('Teriyaki')
      ? { meals: [{ idMeal: '52772', strMeal: 'Teriyaki Chicken Casserole', strArea: 'Japanese', strMealThumb: 'https://www.themealdb.com/images/t.jpg', strTags: 'Meat,Casserole',
        strInstructions: 'Preheat oven to 180C.\r\nMix the sauce for 5 min.\r\nBake for 30 minutes.',
        strIngredient1: 'soy sauce', strMeasure1: '3/4 cup', strIngredient2: 'chicken breasts', strMeasure2: '2', strIngredient3: 'brown sugar', strMeasure3: '1/2 cup', strIngredient4: '', strMeasure4: '' }] }
      : { meals: null }),
    'https://www.googleapis.com/youtube/v3/search': { items: [
      { id: { videoId: 'abc123' }, snippet: { title: 'Aloo Puri Recipe | Gujarati Breakfast &amp; More', channelTitle: 'Cook &#39;n&#39; Eat', thumbnails: { high: { url: 'https://i.ytimg.com/abc.jpg' } } } },
      { id: { videoId: 'zzz999' }, snippet: { title: 'My weekend vlog', channelTitle: 'Random', thumbnails: {} } },
    ] },
    'https://en.wikipedia.org/': { query: { pages: {} } },
    'https://api.openverse.org/': { results: [] },
  });
  t = await setup({ fetcher, user: 'premium-dishes', env: { PREMIUM_DISH_AI_PER_WEEK: '3', YOUTUBE_API_KEY: 'yt-key' } });
  token = await t.register();
});
after(() => t.teardown());

describe('dish names', () => {
  it('spelling-tolerant keys: aloo/alu, poori/puri, paneer/panir, channa/chana', () => {
    assert.equal(soundKey('Aloo Poori'), soundKey('alu puri'));
    assert.equal(soundKey('Paneer'), soundKey('panir'));
    assert.equal(soundKey('Channa'), soundKey('chana'));
    assert.equal(dishSlug('Aloo Puri (fried bread)'), 'alu-puri');
    assert.equal(matchScore('alu', 'Aloo Puri'), 3);
    assert.equal(matchScore('puri', 'Aloo Puri'), 2);
    assert.equal(matchScore('zz', 'Aloo Puri'), 0);
  });
});

describe('POST /v1/dishes/suggest', () => {
  it('"alu" in Surat, Gujarat → Aloo Puri first (local region), no duplicates or junk', async () => {
    const res = await t.api('/v1/dishes/suggest', { q: 'alu', country: 'IN', region: 'Gujarat' }, { token });
    assert.equal(res.status, 200);
    const names = res.body.suggestions.map((s) => s.name);
    assert.equal(names[0], 'Aloo Puri');
    assert.equal(res.body.suggestions[0].region, 'Gujarat');
    assert.deepEqual(new Set(names), new Set(['Aloo Puri', 'Aloo Paratha', 'Aloo Gobi']));
  });
  it('"poori" finds both spellings; the country list is built once and shared', async () => {
    const calls = chats();
    const res = await t.api('/v1/dishes/suggest', { q: 'poori', country: 'IN' }, { token: await t.register() });
    assert.deepEqual(res.body.suggestions.map((s) => s.name), ['Poori Bhaji', 'Aloo Puri']);
    assert.equal(chats(), calls);
  });
  it('a single letter suggests nothing (no wasted work)', async () => {
    assert.deepEqual((await t.api('/v1/dishes/suggest', { q: 'a', country: 'IN' }, { token })).body.suggestions, []);
  });
});

describe('POST /v1/dishes/find', () => {
  it('a dish nobody has searched: AI writes it once, then everyone gets the saved copy', async () => {
    const calls = chats();
    const first = await t.api('/v1/dishes/find', { name: 'Aloo Puri', country: 'IN', region: 'Gujarat' }, { token });
    assert.equal(first.status, 200);
    assert.equal(first.body.cached, false);
    assert.equal(first.body.recipe.remoteID, 'dish-alu-puri');
    assert.ok(first.body.recipe.ingredients.length >= 3 && first.body.recipe.steps.length >= 2);
    assert.equal(chats(), calls + 1);
    const again = await t.api('/v1/dishes/find', { name: 'alu poori' }, { token: await t.register() });
    assert.equal(again.body.cached, true, 'other spelling, other device: from the library');
    assert.equal(again.body.recipe.title, first.body.recipe.title);
    assert.equal(chats(), calls + 1, 'no second AI call');
  });
  it('TheMealDB first: real recipe, amounts parsed, no AI', async () => {
    const calls = chats();
    const res = await t.api('/v1/dishes/find', { name: 'Teriyaki chicken casserole' }, { token });
    assert.equal(res.status, 200);
    const { recipe } = res.body;
    assert.equal(recipe.title, 'Teriyaki Chicken Casserole');
    assert.equal(recipe.cuisine, 'Japanese');
    assert.equal(recipe.ingredients.length, 3);
    assert.equal(recipe.ingredients[0].quantity, 0.75);
    assert.equal(recipe.steps.length, 3);
    assert.equal(chats(), calls);
  });
  it('found dishes show up in suggestions for everyone', async () => {
    const res = await t.api('/v1/dishes/suggest', { q: 'teri' }, { token });
    assert.deepEqual(res.body.suggestions.map((s) => s.name), ['Teriyaki Chicken Casserole']);
  });
  it('names that are not dishes: clear 404, and the miss is remembered', async () => {
    const res = await t.api('/v1/dishes/find', { name: 'Xyzzy blorp' }, { token });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'unknown_dish');
    const calls = chats();
    assert.equal((await t.api('/v1/dishes/find', { name: 'xyzzy blorp' }, { token })).status, 404);
    assert.equal(chats(), calls);
  });
  it('new AI dishes are capped per Premium device per week; saved dishes stay free', async () => {
    const device = await t.register();
    for (const name of ['Sev Tameta', 'Undhiyu', 'Handvo']) {
      assert.equal((await t.api('/v1/dishes/find', { name }, { token: device })).status, 200, name);
    }
    const blocked = await t.api('/v1/dishes/find', { name: 'Fafda' }, { token: device });
    assert.equal(blocked.status, 429);
    assert.match(blocked.body.error, /3 new AI dishes.*Monday/);
    assert.equal((await t.api('/v1/dishes/find', { name: 'Aloo Puri' }, { token: device })).status, 200);
  });
  it('free cooks get every saved dish, but a brand-new dish needs Premium (no AI call)', async () => {
    const free = { 'X-RC-App-User': 'free-cook' };
    const device = await t.register();
    assert.equal((await t.api('/v1/dishes/find', { name: 'Undhiyu' }, { token: device, headers: free })).status, 200);
    const calls = chats();
    const blocked = await t.api('/v1/dishes/find', { name: 'Khandvi' }, { token: device, headers: free });
    assert.equal(blocked.status, 403);
    assert.equal(blocked.body.code, 'premium');
    assert.equal(chats(), calls);
    // Autocomplete for a country nobody built yet: only the shared library, no AI list.
    const res = await t.api('/v1/dishes/suggest', { q: 'und', country: 'US' }, { token: device, headers: free });
    assert.deepEqual(res.body.suggestions.map((d) => d.name), ['Undhiyu']);
    assert.equal(chats(), calls);
  });
  it('validates the name', async () => {
    for (const name of ['', '1', 'x'.repeat(81), 42]) assert.equal((await t.api('/v1/dishes/find', { name }, { token })).status, 400, String(name));
  });
});

describe('POST /v1/videos', () => {
  it('matching YouTube videos (titles decoded, unrelated ones dropped) plus a search link', async () => {
    const res = await t.api('/v1/videos', { title: 'Aloo Puri (fried bread)' }, { token });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.videos.map((v) => v.id), ['abc123']);
    assert.equal(res.body.videos[0].title, 'Aloo Puri Recipe | Gujarati Breakfast & More');
    assert.equal(res.body.videos[0].channel, "Cook 'n' Eat");
    assert.equal(res.body.videos[0].url, 'https://www.youtube.com/watch?v=abc123');
    assert.equal(res.body.searchURL, 'https://www.youtube.com/results?search_query=Aloo%20Puri%20recipe');
  });
});
