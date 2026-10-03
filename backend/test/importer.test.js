import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { fixture, setup, stubFetcher } from './helpers.js';

// Import pipeline end to end over HTTP: public caption/description → creator's website → AI,
// with the network replaced by fixtures. Never downloads videos, never reads comments.
let t;
let fetcher;
let token;

before(async () => {
  fetcher = stubFetcher({
    'https://spicekitchen.example/palak': await fixture('recipe-jsonld.html'),
    'https://grandma.example/soup': await fixture('no-jsonld.html'),
    'https://www.instagram.com/reel/pasta/': await fixture('instagram.html'),
    'https://www.instagram.com/p/curry/': await fixture('instagram-link.html'),
    'https://mariaskitchen.example/curry': await fixture('creator-site.html'),
    'https://www.instagram.com/reel/talky/': '<html><head><meta property="og:description" content="NO_RECIPE so good, recipe in the video! #dinner #easy"></head></html>',
    'https://www.instagram.com/p/private/': '<html><head></head><body>Log in</body></html>',
    'https://www.tiktok.com/oembed': (url) => {
      if (url.includes('%40blocked')) throw new Error('That site took too long to answer.'); // like a DNS-blocked network
      return { title: 'Garlic noodles\nIngredients\n200 g noodles\n4 cloves garlic\nMethod\n1. Boil the noodles for 5 min', author_name: 'noodlequeen', thumbnail_url: 'https://p16.example/t.jpg' };
    },
    'https://www.youtube.com/oembed': { json: { title: 'Easy Shakshuka', author_name: 'Chef Lee', thumbnail_url: 'https://i.ytimg.example/s.jpg' } },
    'https://www.youtube.com/watch?v=shak123': '<html><head><meta property="og:description" content="Shakshuka\nIngredients\n4 eggs\n400 g tomatoes\n1 onion"></head></html>',
  });
  t = await setup({ fetcher, env: { FREE_IMPORTS_PER_WEEK: '50' } });
  token = await t.register();
});
after(() => t.teardown());

const importLink = (url, extra = {}) => t.api('/v1/imports', { url, ...extra }, { token });

describe('recipe websites', () => {
  it('uses the JSON-LD recipe card directly — no AI call needed', async () => {
    const calls = t.ai.calls.length;
    const res = await importLink('https://spicekitchen.example/palak');
    assert.equal(res.status, 200);
    assert.equal(res.body.via, 'recipe card');
    assert.equal(res.body.recipe.title, 'Palak Paneer & Jeera Rice');
    assert.equal(res.body.recipe.sourceName, 'Spice Kitchen');
    assert.equal(res.body.recipe.servings, 4);
    assert.equal(res.body.recipe.ingredients.length, 5);
    assert.equal(res.body.recipe.method, 'link');
    assert.equal(t.ai.calls.length, calls);
  });
  it('reads the visible article text with AI when there is no recipe card', async () => {
    const res = await importLink('https://grandma.example/soup');
    assert.equal(res.status, 200);
    assert.equal(res.body.via, 'page');
    assert.ok(res.body.recipe.ingredients.some((i) => /lentils/.test(i.text)));
    assert.ok(!JSON.stringify(t.ai.calls.at(-1).body).includes('window.tracking'), 'scripts never reach the AI');
  });
  it('uses page text the app already fetched instead of fetching again', async () => {
    const before = fetcher.requests.length;
    const res = await importLink('https://another.example/stew', { pageText: 'Beef stew\nIngredients\n500 g beef\n2 carrots\nMethod\n1. Brown the beef\n2. Stew for 90 min' });
    assert.equal(res.status, 200);
    assert.equal(fetcher.requests.length, before);
    assert.equal(res.body.recipe.title, 'Beef stew');
  });
});

describe('social posts (public captions only)', () => {
  it('Instagram: reads the caption from the public link preview', async () => {
    const res = await importLink('https://www.instagram.com/reel/pasta/?igsh=abc123');
    assert.equal(res.status, 200);
    assert.equal(res.body.via, 'caption');
    assert.equal(res.body.recipe.sourceName, 'Instagram');
    assert.equal(res.body.recipe.sourceURL, 'https://www.instagram.com/reel/pasta/', 'tracking removed');
    assert.equal(res.body.recipe.imageURL, 'https://scontent.example/pasta.jpg');
    assert.ok(res.body.recipe.ingredients.length >= 3);
    assert.ok(res.body.recipe.steps.length >= 2);
  });
  it('follows a recipe link in the caption to the creator’s website (skipping link-in-bio pages)', async () => {
    const res = await importLink('https://www.instagram.com/p/curry/');
    assert.equal(res.status, 200);
    assert.equal(res.body.via, "creator's website");
    assert.equal(res.body.recipe.title, 'Weeknight Chickpea Curry');
    assert.equal(res.body.recipe.servings, 4);
    assert.equal(res.body.recipe.steps.length, 3);
    assert.ok(res.body.notes[0].includes('mariaskitchen.example'));
    assert.ok(!fetcher.requests.some((url) => url.includes('linktr.ee')));
  });
  it('TikTok: uses the official oEmbed caption', async () => {
    const res = await importLink('https://www.tiktok.com/@noodlequeen/video/7?is_from_webapp=1&sender_device=pc');
    assert.equal(res.status, 200);
    assert.equal(res.body.recipe.creator, 'noodlequeen');
    assert.equal(res.body.recipe.title, 'Garlic noodles');
    assert.ok(fetcher.requests.at(-1).startsWith('https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40noodlequeen%2Fvideo%2F7'));
  });
  it('YouTube without an API key: oEmbed title + public description; missing steps are flagged, not invented', async () => {
    const res = await importLink('https://youtu.be/shak123?si=xyz');
    assert.equal(res.status, 200);
    assert.equal(res.body.via, 'description');
    assert.equal(res.body.recipe.creator, 'Chef Lee');
    assert.equal(res.body.recipe.steps.length, 0);
    assert.ok(res.body.notes.some((note) => /steps weren’t in the post|Steps were not/.test(note)));
  });
  it('private or caption-less posts get a clear way forward', async () => {
    const res = await importLink('https://www.instagram.com/p/private/');
    assert.equal(res.status, 422);
    assert.match(res.body.error, /Instagram didn't share a caption.*Text tab.*Video tab/);
    assert.equal(res.body.code, 'no_caption');
  });
  it('TikTok unreachable (blocked network) → a clear way forward, not a timeout', async () => {
    const res = await importLink('https://www.tiktok.com/@blocked/video/7000000000000000001');
    assert.equal(res.status, 422);
    assert.equal(res.body.code, 'no_caption');
    assert.match(res.body.error, /couldn't reach TikTok.*Text tab.*Video tab/);
  });
  it('a caption without a recipe points to the Video tab (the recipe is probably spoken)', async () => {
    const res = await importLink('https://www.instagram.com/reel/talky/');
    assert.equal(res.status, 422);
    assert.equal(res.body.code, 'no_caption');
    assert.match(res.body.error, /spoken in the video.*Video tab/);
  });
});

describe('caching', () => {
  it('the same post (even with different tracking links) is imported once', async () => {
    const calls = t.ai.calls.length;
    const fetches = fetcher.requests.length;
    const a = await importLink('https://www.instagram.com/reel/pasta/?utm_source=ig_web_copy_link');
    const b = await importLink('https://www.instagram.com/reel/pasta/#comments');
    assert.equal(a.status, 200);
    assert.deepEqual(a.body, b.body);
    assert.equal(t.ai.calls.length, calls);
    assert.equal(fetcher.requests.length, fetches);
  });
});
