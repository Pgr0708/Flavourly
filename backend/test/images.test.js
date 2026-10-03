import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, beforeEach, describe, it } from 'node:test';
import { createCache } from '../src/cache.js';
import { createImages, describesDish, photoQueries } from '../src/services.js';

// Recipe photos: free sources first (each photo must show the dish and keep its licence credit), GPT last.
const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'flavourly-photos-'));
after(() => fs.rm(dir, { recursive: true, force: true }));

const json = (body, status = 200) => ({ ok: status < 400, status, json: async () => body });
const credit = (url) => Object.fromEntries(new URL(url).hash.slice(1).split('&').map((p) => p.split('=').map(decodeURIComponent)));

let calls;
let gpt;
function setup({ routes = {}, keys = {}, spoonPerDay = 40, imageGeneration = true } = {}) {
  calls = [];
  gpt = 0;
  const route = (url) => {
    calls.push(url);
    const hit = Object.entries(routes).find(([prefix]) => url.startsWith(prefix));
    if (!hit) throw new Error(`unexpected ${url}`);
    return typeof hit[1] === 'function' ? hit[1](url) : hit[1];
  };
  const config = {
    IMAGE_DIR: dir, PUBLIC_URL: 'https://api.example.com', IMAGE_GENERATION: imageGeneration, IMAGE_MODEL: 'gpt-image-1', IMAGE_QUALITY: 'low',
    SPOONACULAR_API_KEY: '', PEXELS_API_KEY: '', UNSPLASH_ACCESS_KEY: '', PIXABAY_API_KEY: '', THEMEALDB_API_KEY: '1', SPOONACULAR_PHOTOS_PER_DAY: spoonPerDay, ...keys,
  };
  const ai = { image: async () => { gpt += 1; return Buffer.from('jpeg'); } };
  return createImages({
    config, ai, cache: createCache({}),
    fetcher: { fetchJson: async (url) => route(url) },
    http: async (url) => {
      const body = route(url);
      return Buffer.isBuffer(body) ? { ok: true, status: 200, arrayBuffer: async () => body } : json(body);
    },
  });
}
const nothingOnWikipedia = { 'https://en.wikipedia.org/': { query: { pages: { '-1': { title: 'x', missing: '' } } } } };

describe('photo relevance', () => {
  it('searches names in other scripts by their English name', () => {
    assert.deepEqual(photoQueries('粥 (Congee)'), ['Congee']);
    assert.deepEqual(photoQueries('饺子 (Jiǎozi - Dumplings)'), ['Jiǎozi - Dumplings', 'Jiǎozi', 'Dumplings']);
    assert.deepEqual(photoQueries('Khubz (Afghan Bread)'), ['Khubz', 'Afghan Bread']);
    assert.deepEqual(photoQueries('Pav bhaji'), ['Pav bhaji']);
  });
  it('most of the dish name must describe the photo', () => {
    assert.equal(describesDish('Garlic butter noodles', 'Bowl of noodles with garlic and butter'), true);
    assert.equal(describesDish('Paneer tikka', 'Chicken curry in a pot'), false);
    assert.equal(describesDish('Pav Bhaji', 'Pav bhaji'), true);
    assert.equal(describesDish('Easy homemade dal', 'Yellow dal tadka'), true); // "easy", "homemade" don't count
    assert.equal(describesDish('Dal', ''), false);
  });
});

describe('recipe photo sources', () => {
  beforeEach(async () => {
    for (const file of await fs.readdir(dir)) await fs.rm(path.join(dir, file));
  });

  it('Pexels: skips an unrelated first result, keeps photographer credit', async () => {
    const images = setup({
      keys: { PEXELS_API_KEY: 'px' },
      routes: { 'https://api.pexels.com/': { photos: [
        { alt: 'Chicken curry in a pot', src: { large: 'https://images.pexels.com/1.jpg' }, photographer: 'A', url: 'https://pexels.com/1' },
        { alt: 'Paneer tikka on skewers', src: { large: 'https://images.pexels.com/2.jpg' }, photographer: 'Asha', url: 'https://pexels.com/2' },
      ] } },
    });
    const { url } = await images.recipePhoto({ title: 'Paneer tikka' });
    assert.ok(url.startsWith('https://images.pexels.com/2.jpg#'));
    assert.deepEqual(credit(url), { credit: 'Photo by Asha on Pexels', credit_url: 'https://pexels.com/2' });
    assert.equal(gpt, 0);
    // Found once, then served from cache without searching again.
    const searches = calls.length;
    assert.equal((await images.recipePhoto({ title: 'Paneer tikka' })).url, url);
    assert.equal(await images.existing('Paneer tikka'), url);
    assert.equal(calls.length, searches);
  });

  it('Unsplash: credits the photographer and pings the download endpoint (API guideline)', async () => {
    const images = setup({
      keys: { UNSPLASH_ACCESS_KEY: 'us' },
      routes: {
        'https://api.unsplash.com/search': { results: [{ alt_description: 'masala dosa with chutney', urls: { regular: 'https://images.unsplash.com/d.jpg' },
          links: { download_location: 'https://api.unsplash.com/photos/d/download?ixid=1' }, user: { name: 'Ravi', links: { html: 'https://unsplash.com/@ravi' } } }] },
        'https://api.unsplash.com/photos/d/download': {},
      },
    });
    const { url } = await images.recipePhoto({ title: 'Masala dosa' });
    assert.deepEqual(credit(url), { credit: 'Photo by Ravi on Unsplash', credit_url: 'https://unsplash.com/@ravi?utm_source=flavourly&utm_medium=referral' });
    await new Promise((resolve) => setImmediate(resolve));
    assert.ok(calls.includes('https://api.unsplash.com/photos/d/download?ixid=1&client_id=us'));
  });

  it('Wikipedia: free licence with author credit; non-free "fair use" images are refused', async () => {
    const page = { query: { pages: { 1: { title: 'Pav bhaji', pageimage: 'Pav.jpg', thumbnail: { source: 'https://upload.wikimedia.org/pav.jpg' } } } } };
    const file = (meta) => ({ query: { pages: { 2: { imageinfo: [{ descriptionurl: 'https://commons.wikimedia.org/wiki/File:Pav.jpg', extmetadata: meta }] } } } });
    let images = setup({ routes: { 'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages': page,
      'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=imageinfo': file({ Artist: { value: '<a href="x">Meena K</a>' }, LicenseShortName: { value: 'CC BY-SA 4.0' } }) } });
    const { url } = await images.recipePhoto({ title: 'Pav bhaji' });
    assert.deepEqual(credit(url), { credit: 'Photo: Meena K · CC BY-SA 4.0', credit_url: 'https://commons.wikimedia.org/wiki/File:Pav.jpg' });

    images = setup({ routes: { 'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages': page,
      'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=imageinfo': file({ LicenseShortName: { value: 'Fair use' }, NonFree: { value: 'true' } }) } });
    const ai = await images.recipePhoto({ title: 'Pav bhaji' });
    assert.equal(gpt, 1, 'non-free image skipped, GPT used instead');
    assert.equal(credit(ai.url).credit, 'AI-generated image');
  });

  it('Wikipedia: trusts a redirect from the exact dish name, not a different article', async () => {
    const page = (from, to) => ({ query: { redirects: from ? [{ from, to }] : [], pages: { 1: { title: to, pageimage: 'C.jpg', thumbnail: { source: 'https://upload.wikimedia.org/c.jpg' } } } } });
    const file = { query: { pages: { 2: { imageinfo: [{ descriptionurl: 'https://commons.wikimedia.org/wiki/File:C.jpg', extmetadata: { LicenseShortName: { value: 'CC BY 2.0' } } }] } } } };
    let images = setup({ routes: { 'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages': page('Spaghetti carbonara', 'Carbonara'),
      'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=imageinfo': file } });
    assert.equal(credit((await images.recipePhoto({ title: 'Spaghetti carbonara' })).url).credit, 'Photo: Wikimedia Commons · CC BY 2.0');
    images = setup({ routes: { 'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages': page(null, 'Carbonara') } });
    await images.recipePhoto({ title: 'Spaghetti carbonara' });
    assert.equal(gpt, 1, 'no redirect and only half the words match → not trusted');
  });

  it('searches by the dish name without the bracketed note ("Khubz (Afghan Bread)" → "Khubz")', async () => {
    const images = setup({ routes: { 'https://www.themealdb.com/': { meals: null },
      'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages': (url) => (url.endsWith('titles=Khubz')
        ? { query: { pages: { 1: { title: 'Khubz', pageimage: 'K.jpg', thumbnail: { source: 'https://upload.wikimedia.org/k.jpg' } } } } }
        : { query: { pages: { '-1': { missing: '' } } } }),
      'https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=imageinfo': { query: { pages: { 2: { imageinfo: [{ descriptionurl: 'https://commons.wikimedia.org/wiki/File:K.jpg', extmetadata: { LicenseShortName: { value: 'CC BY 4.0' } } }] } } } },
      'https://api.openverse.org/': { results: [] } } });
    const { url } = await images.recipePhoto({ title: 'Khubz (Afghan Bread)' });
    assert.ok(url.startsWith('https://upload.wikimedia.org/k.jpg#'));
    assert.equal(gpt, 0);
  });

  it('Spoonacular: only matching titles, and photos stay inside their own daily budget', async () => {
    const images = setup({
      keys: { SPOONACULAR_API_KEY: 'sp' }, spoonPerDay: 1,
      routes: { 'https://api.spoonacular.com/recipes/complexSearch': { results: [{ id: 7, title: 'Thai green curry', image: 'https://img.spoonacular.com/7.jpg' }] }, ...nothingOnWikipedia },
    });
    const { url } = await images.recipePhoto({ title: 'Green curry' });
    assert.deepEqual(credit(url), { credit: 'Photo via spoonacular', credit_url: 'https://spoonacular.com/recipes/-7' });
    await images.recipePhoto({ title: 'Red curry' }); // budget used up → Spoonacular not even asked
    assert.equal(calls.filter((c) => c.includes('spoonacular')).length, 1);
  });

  it('TheMealDB: the exact dish, credited', async () => {
    const images = setup({ routes: { 'https://www.themealdb.com/api/json/v1/1/search.php': { meals: [{ idMeal: '52772', strMeal: 'Teriyaki Chicken Casserole', strMealThumb: 'https://www.themealdb.com/images/media/meals/x.jpg' }] } } });
    const { url } = await images.recipePhoto({ title: 'Teriyaki chicken casserole' });
    assert.deepEqual(credit(url), { credit: 'Photo: TheMealDB', credit_url: 'https://www.themealdb.com/meal/52772' });
  });

  it('Pixabay: downloaded and served by us (no hotlinking), with credit', async () => {
    const images = setup({
      keys: { PIXABAY_API_KEY: 'pb' },
      routes: {
        'https://www.themealdb.com/': { meals: null },
        'https://pixabay.com/api/': { hits: [{ tags: 'salad, bowl', largeImageURL: 'https://pixabay.com/get/1.jpg', pageURL: 'https://pixabay.com/photos/1', user: 'Zed' },
          { tags: 'lemon rice, rice, indian food', largeImageURL: 'https://pixabay.com/get/2.jpg', pageURL: 'https://pixabay.com/photos/2', user: 'Mira' }] },
        'https://pixabay.com/get/2.jpg': Buffer.alloc(5_000, 1),
      },
    });
    const { url } = await images.recipePhoto({ title: 'Lemon rice' });
    assert.match(url, /^https:\/\/api\.example\.com\/images\/pb-[0-9a-f]{32}\.jpg#/);
    assert.deepEqual(credit(url), { credit: 'Image by Mira from Pixabay', credit_url: 'https://pixabay.com/photos/2' });
    assert.equal((await fs.stat(path.join(dir, path.basename(new URL(url).pathname)))).size, 5_000);
  });

  it('Openverse: commercial-use Creative Commons only, with licence credit', async () => {
    const images = setup({ routes: {
      'https://www.themealdb.com/': { meals: null }, ...nothingOnWikipedia,
      'https://api.openverse.org/': { results: [{ title: 'Bowl of khow suey', tags: [{ name: 'noodles' }], thumbnail: 'https://api.openverse.org/v1/images/k/thumb/',
        creator: 'Lin', license: 'by-sa', license_version: '2.0', foreign_landing_url: 'https://flickr.com/k' }] },
    } });
    const { url } = await images.recipePhoto({ title: 'Khow suey' });
    assert.deepEqual(credit(url), { credit: 'Photo: Lin · CC BY-SA 2.0', credit_url: 'https://flickr.com/k' });
    assert.ok(calls.some((c) => c.includes('license_type=commercial')));
  });

  it('freeOnly: never GPT, and a miss is remembered so free APIs are not asked again for days', async () => {
    const images = setup({ routes: { 'https://www.themealdb.com/': { meals: null }, ...nothingOnWikipedia, 'https://api.openverse.org/': { results: [] } } });
    await assert.rejects(images.recipePhoto({ title: 'Grandma special stew', freeOnly: true }), (error) => error.status === 404 && error.extra?.code === 'no_photo');
    const asked = calls.length;
    await assert.rejects(images.recipePhoto({ title: 'Grandma special stew', freeOnly: true }), (error) => error.status === 404);
    assert.equal(calls.length, asked, 'second lookup used the remembered miss');
    assert.equal(gpt, 0);
    await images.recipePhoto({ title: 'Grandma special stew' }); // asking for a photo explicitly may still use GPT
    assert.equal(gpt, 1);
  });

  it('a Chinese-titled dish finds a free photo through its English name instead of GPT', async () => {
    const images = setup({ keys: { PEXELS_API_KEY: 'px' }, routes: {
      'https://www.themealdb.com/': { meals: null },
      'https://api.pexels.com/': (url) => (url.includes('Dumplings') ? { photos: [{ alt: 'Plate of steamed dumplings', src: { large: 'https://images.pexels.com/d.jpg' }, photographer: 'Li', url: 'https://pexels.com/d' }] } : { photos: [] }),
      ...nothingOnWikipedia, 'https://api.openverse.org/': { results: [] } } });
    const { url } = await images.recipePhoto({ title: '饺子 (Jiǎozi - Dumplings)' });
    assert.ok(url.startsWith('https://images.pexels.com/d.jpg#'));
    assert.equal(gpt, 0);
  });

  it('nothing free matches → GPT once, then the same photo for everyone from disk', async () => {
    const images = setup({ routes: nothingOnWikipedia });
    const first = await images.recipePhoto({ title: 'Grandma special stew' });
    assert.equal(gpt, 1);
    assert.equal(credit(first.url).credit, 'AI-generated image');
    assert.equal((await images.recipePhoto({ title: 'Grandma special stew' })).url, first.url);
    assert.equal(gpt, 1);
  });

  it('a failing source never blocks the rest', async () => {
    const images = setup({
      keys: { PEXELS_API_KEY: 'px' },
      routes: { 'https://api.pexels.com/': () => { throw new Error('boom'); }, ...nothingOnWikipedia },
    });
    await images.recipePhoto({ title: 'Lemon rice' });
    assert.equal(gpt, 1);
  });

  it('photos off and nothing free → 501, no GPT', async () => {
    const images = setup({ routes: nothingOnWikipedia, imageGeneration: false });
    await assert.rejects(images.recipePhoto({ title: 'Lemon rice' }), (error) => error.status === 501);
    assert.equal(gpt, 0);
  });
});
