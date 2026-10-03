import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { dishSlug, matchScore, soundKey } from '../src/dishes.js';
import { setup, stubFetcher } from './helpers.js';

// Search any dish: autocomplete from each country's dish names, recipes from a shared library
// (TheMealDB, else AI once), and recipe videos.
const WIKI_KHICHDI = `{{Recipe summary | category = Rice recipes | servings = 4 | time = 1 hour | difficulty = 2}}
'''Khichdi''' is a [[Cookbook:Cuisine of India|Indian]] comfort dish.<ref>A note</ref>
== Ingredients ==
* 1 [[Cookbook:Cup|cup]] [[Cookbook:Rice|rice]]
* ½ cup moong dal
* 1 tsp [[Cookbook:Turmeric|turmeric]]
* 2 tbsp ghee
* 1 tsp cumin seeds
* 4 cups water
== Procedure ==
# Wash the rice and dal and soak for 20 minutes.
# Heat the ghee and add the cumin.
# Add rice, dal, turmeric and water; pressure cook for 15 minutes.
== Notes, tips, and variations ==
* Serve with yogurt.`;
const SPOON_PAD_SEE_EW = {
  id: 716429, title: 'Pad See Ew', servings: 2, readyInMinutes: 25, cuisines: ['Thai'], image: 'https://img.spoonacular.com/recipes/716429-556x370.jpg',
  sourceName: 'Example Kitchen', sourceUrl: 'https://example.com/pad-see-ew',
  extendedIngredients: [{ original: '200 g wide rice noodles', amount: 200, unit: 'g', name: 'rice noodles' }, { original: '2 tbsp soy sauce', amount: 2, unit: 'tbsp', name: 'soy sauce' }, { original: '1 cup gai lan', amount: 1, unit: 'cup', name: 'gai lan' }],
  analyzedInstructions: [{ steps: [{ step: 'Soak the noodles.', length: { number: 10, unit: 'minutes' } }, { step: 'Stir-fry everything over high heat.' }] }],
};
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
    'https://en.wikibooks.org/w/api.php': (url) => {
      if (url.includes('list=search')) return { query: { search: url.includes('Khichdi') ? [{ title: 'Cookbook:Sunday Roast' }, { title: 'Cookbook:Moong Dal Khichdi' }] : [] } };
      return { parse: { wikitext: WIKI_KHICHDI } };
    },
    'https://api.spoonacular.com/recipes/complexSearch': (url) => ({ results: url.includes('Pad%20See%20Ew') ? [SPOON_PAD_SEE_EW] : [] }),
    'https://api.spoonacular.com/recipes/716429/information': SPOON_PAD_SEE_EW,
    'https://www.googleapis.com/youtube/v3/search': { items: [
      { id: { videoId: 'abc123' }, snippet: { title: 'Aloo Puri Recipe | Gujarati Breakfast &amp; More', channelTitle: 'Cook &#39;n&#39; Eat', thumbnails: { high: { url: 'https://i.ytimg.com/abc.jpg' } } } },
      { id: { videoId: 'zzz999' }, snippet: { title: 'My weekend vlog', channelTitle: 'Random', thumbnails: {} } },
    ] },
    'https://en.wikipedia.org/': { query: { pages: {} } },
    'https://api.openverse.org/': { results: [] },
  });
  t = await setup({ fetcher, user: 'premium-dishes', env: { PREMIUM_DISH_AI_PER_WEEK: '3', YOUTUBE_API_KEY: 'yt-key', SPOONACULAR_API_KEY: 'spoon-key' } });
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
  it('a dish nobody has: the dish model writes it, a too-short answer is written out in full, then everyone gets the saved copy', async () => {
    const calls = chats();
    const first = await t.api('/v1/dishes/find', { name: 'Aloo Puri', country: 'IN', region: 'Gujarat' }, { token });
    assert.equal(first.status, 200);
    assert.equal(first.body.cached, false);
    assert.equal(first.body.recipe.remoteID, 'dish-alu-puri');
    assert.ok(first.body.recipe.ingredients.length >= 10 && first.body.recipe.steps.length >= 8, 'detailed after the second pass');
    assert.equal(chats(), calls + 2, 'recipe, then "write it out in full"');
    const used = t.ai.calls.filter((c) => c.path.includes('chat')).slice(-2);
    assert.deepEqual(used.map((c) => c.body.model), ['gpt-4.1-mini', 'gpt-4.1-mini']);
    assert.deepEqual(used.map((c) => c.body.response_format.json_schema.name), ['dish_recipe', 'recipe_expand']);
    const again = await t.api('/v1/dishes/find', { name: 'alu poori' }, { token: await t.register() });
    assert.equal(again.body.cached, true, 'other spelling, other device: from the library');
    assert.equal(again.body.recipe.title, first.body.recipe.title);
    assert.equal(chats(), calls + 2, 'no more AI calls');
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
  it('Wikibooks Cookbook next: the matching page, wiki markup cleaned, credited and saved — no AI', async () => {
    const calls = chats();
    const res = await t.api('/v1/dishes/find', { name: 'Moong Dal Khichdi' }, { token, headers: { 'X-RC-App-User': 'free-cook' } });
    assert.equal(res.status, 200, 'free cooks get it: no AI involved');
    const { recipe } = res.body;
    assert.equal(recipe.title, 'Moong Dal Khichdi');
    assert.equal(recipe.servings, 4);
    assert.equal(recipe.ingredients.length, 6);
    assert.equal(recipe.ingredients[0].text, '1 cup rice');
    assert.equal(recipe.steps.length, 3);
    assert.match(recipe.sourceName, /Wikibooks.*CC BY-SA/);
    assert.match(recipe.sourceURL, /en\.wikibooks\.org\/wiki\/Cookbook%3AMoong_Dal_Khichdi/);
    assert.equal(chats(), calls);
    const [[row]] = await t.deps.db.query("SELECT source FROM dishes WHERE slug = 'mung-dal-khichdi'");
    assert.equal(row?.source, 'wikibooks');
  });
  it('Spoonacular after that: served live and never saved (their terms); the next lookup goes straight to the recipe', async () => {
    const calls = chats();
    const res = await t.api('/v1/dishes/find', { name: 'Pad See Ew' }, { token, headers: { 'X-RC-App-User': 'free-cook' } });
    assert.equal(res.status, 200);
    assert.equal(res.body.live, true);
    assert.equal(res.body.recipe.title, 'Pad See Ew');
    assert.equal(res.body.recipe.sourceName, 'Example Kitchen');
    assert.equal(res.body.recipe.steps[0].timerSeconds, 600);
    assert.equal(chats(), calls);
    const [[row]] = await t.deps.db.query("SELECT COUNT(*) AS n FROM dishes WHERE slug = 'pad-si-ev'");
    assert.equal(Number(row.n), 0, 'not stored');
    const again = await t.api('/v1/dishes/find', { name: 'pad see ew' }, { token });
    assert.equal(again.body.live, true);
    assert.ok(t.deps.fetcher.requests.some((u) => u.includes('/recipes/716429/information')), 'by id the second time');
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
