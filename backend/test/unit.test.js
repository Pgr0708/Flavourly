import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkUrl, isPrivateIP } from '../src/fetcher.js';
import { findRecipe, instructionsOf, parseDuration, parseYield, plain, readPage } from '../src/parsers/jsonld.js';
import { canonicalize, captionFromMeta, findLinks, platformOf, youtubeId } from '../src/parsers/social.js';
import { toDraft } from '../src/recipe.js';
import { dayStart, weekStart } from '../src/util.js';
import { cleanText, schemas } from '../src/validation.js';
import { loadConfig } from '../src/config.js';
import { fixture } from './helpers.js';

describe('cleanText (mirrors the app’s Sanitize.text)', () => {
  it('strips tags, invisible and control characters and collapses whitespace', () => {
    assert.equal(cleanText('  Hello​ <b>World</b>\t!  '), 'Hello World !');
    assert.equal(cleanText('a\u0007b'), 'ab');
    assert.equal(cleanText('abc‮def'), 'abcdef');
    assert.equal(cleanText('a\nb'), 'a b');
  });
  it('keeps multiline structure, emoji, scripts and lone angle brackets', () => {
    assert.equal(cleanText('line1\n\n\n\nline2  \n  line3', { multiline: true }), 'line1\n\nline2\nline3');
    assert.equal(cleanText('👩‍🍳 Chef'), '👩‍🍳 Chef');
    assert.equal(cleanText('पनीर टिक्का'), 'पनीर टिक्का');
    assert.equal(cleanText('cook < 5 min'), 'cook < 5 min');
    assert.equal(cleanText('é'), 'é');
  });
  it('never throws on non-strings', () => {
    assert.equal(cleanText(undefined), '');
    assert.equal(cleanText(42), '');
  });
});

describe('request schemas', () => {
  const ok = (schema, value) => schema.safeParse(value);
  it('device: install id format, platform and version', () => {
    assert.equal(ok(schemas.device, { installID: 'A1B2C3D4-0000-1111-2222-333344445555', platform: 'ios', appVersion: '1.0' }).success, true);
    assert.equal(ok(schemas.device, { installID: 'short' }).success, false);
    assert.equal(ok(schemas.device, { installID: 'A1B2C3D4-0000-1111-2222-333344445555', platform: 'android' }).success, false);
    assert.equal(ok(schemas.device, { installID: '../../etc/passwd' }).success, false);
    assert.equal(ok(schemas.device, { installID: 'A'.repeat(65) }).success, false);
  });
  it('import link: public http(s) only, cleaned', () => {
    const good = ok(schemas.importLink, { url: '  https://www.tiktok.com/@chef/video/1 ', rules: {} });
    assert.equal(good.success, true);
    assert.equal(good.data.url, 'https://www.tiktok.com/@chef/video/1');
    for (const url of ['ftp://x.com/a', 'javascript:alert(1)', 'https://user:pw@x.com', 'https://x.com:8080/a', 'https://localhost/a', '', 'x'.repeat(2049)]) {
      assert.equal(ok(schemas.importLink, { url }).success, false, url);
    }
    assert.equal(ok(schemas.importLink, { url: 'https://a.com', pageText: 'x'.repeat(20_001) }).success, false);
  });
  it('rules: defaults, list limits, cleaning and de-duplication', () => {
    const parsed = ok(schemas.substitutes, { ingredient: '200 ml cream', recipeTitle: 'Pasta', rules: { allergies: [' Peanuts ', 'Peanuts', ''], mildOnly: true } });
    assert.equal(parsed.success, true);
    assert.deepEqual(parsed.data.rules.allergies, ['Peanuts']);
    assert.deepEqual(parsed.data.rules.diets, []);
    assert.equal(ok(schemas.substitutes, { ingredient: '200 ml cream', recipeTitle: 'Pasta', rules: { allergies: Array(31).fill('x') } }).success, false);
  });
  it('extract: needs 20+ characters with letters, max 20,000 (the app paste limit)', () => {
    assert.equal(ok(schemas.extract, { text: 'too short' }).success, false);
    assert.equal(ok(schemas.extract, { text: '1234567890 1234567890 123' }).success, false);
    assert.equal(ok(schemas.extract, { text: 'Tomato soup with basil and cream', kind: 'ocr' }).success, true);
    assert.equal(ok(schemas.extract, { text: 'a'.repeat(20_001) }).success, false);
    assert.equal(ok(schemas.extract, { text: 'Tomato soup '.repeat(1_600) }).success, true);
    assert.equal(ok(schemas.extract, { text: 'Tomato soup with basil and cream', kind: 'video' }).success, false);
  });
  it('cook now: number ranges and optional minutes', () => {
    assert.equal(ok(schemas.cookNow, { craving: 'pasta', pantry: ['eggs'], okToBuy: 2, servings: 2 }).success, true);
    assert.equal(ok(schemas.cookNow, { minutes: 3 }).success, false);
    assert.equal(ok(schemas.cookNow, { minutes: 30.5 }).success, false);
    assert.equal(ok(schemas.cookNow, { servings: 0 }).success, false);
    assert.equal(ok(schemas.cookNow, { okToBuy: 11 }).success, false);
    assert.equal(ok(schemas.cookNow, { craving: 'x'.repeat(81) }).success, false);
    assert.equal(ok(schemas.cookNow, { minutes: null }).success, true);
  });
  it('plan: date format, slot names, sizes', () => {
    const base = { slots: [{ date: '2026-10-05', slot: 'dinner', candidates: ['a'] }], candidates: [{ id: 'a', title: 'Dal', minutes: 30, slots: ['dinner'], protein: 20 }] };
    assert.equal(ok(schemas.plan, base).success, true);
    assert.equal(ok(schemas.plan, { ...base, slots: [] }).success, false);
    assert.equal(ok(schemas.plan, { ...base, slots: [{ date: '5/10/2026', slot: 'dinner', candidates: [] }] }).success, false);
    assert.equal(ok(schemas.plan, { ...base, slots: [{ date: '2026-10-05', slot: 'brunch', candidates: [] }] }).success, false);
  });
  it('image: title needs letters', () => {
    assert.equal(ok(schemas.image, { title: '12' }).success, false);
    assert.equal(ok(schemas.image, { title: 'Dal tadka' }).success, true);
  });
});

describe('SSRF guard', () => {
  it('classifies addresses', () => {
    for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1',
      '::1', '::', 'fe80::1', 'fd00::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', '64:ff9b::10.0.0.1', 'not-an-ip']) {
      assert.equal(isPrivateIP(ip), true, ip);
    }
    for (const ip of ['8.8.8.8', '172.32.0.1', '1.1.1.1', '2606:4700:4700::1111', '::ffff:8.8.8.8']) assert.equal(isPrivateIP(ip), false, ip);
  });
  it('rejects bad links before any network access', () => {
    for (const url of ['file:///etc/passwd', 'gopher://x.com', 'http://localhost/', 'http://printer.local/x', 'http://127.0.0.1/', 'http://[::1]/',
      'http://10.0.0.5/', 'https://user:pw@example.com', 'https://example.com:22/', 'not a url']) {
      assert.throws(() => checkUrl(url), url);
    }
    assert.equal(checkUrl('https://www.example.com/recipe?id=1').hostname, 'www.example.com');
  });
});

describe('JSON-LD recipe parsing', () => {
  it('durations and yields in every common form', () => {
    assert.equal(parseDuration('PT1H30M'), 90);
    assert.equal(parseDuration('P0DT45M'), 45);
    assert.equal(parseDuration('PT90S'), 2);
    assert.equal(parseDuration('1 hour 15 mins'), 75);
    assert.equal(parseDuration(20), 20);
    assert.equal(parseDuration(''), 0);
    assert.equal(parseDuration('soon'), 0);
    assert.equal(parseYield(['4', '4 servings']), 4);
    assert.equal(parseYield('Serves 6-8'), 6);
    assert.equal(parseYield(3), 3);
    assert.equal(parseYield('a lot'), null);
  });
  it('instructions: strings, numbered blocks, steps and sections', () => {
    assert.deepEqual(instructionsOf('Boil water.\nAdd pasta.'), ['Boil water.', 'Add pasta.']);
    assert.deepEqual(instructionsOf('1. Boil water. 2. Add pasta.'), ['Boil water.', 'Add pasta.']);
    assert.deepEqual(instructionsOf([{ '@type': 'HowToSection', itemListElement: [{ text: 'A' }, { text: 'B' }] }, 'C']), ['A', 'B', 'C']);
    assert.deepEqual(instructionsOf(null), []);
  });
  it('decodes entities and tags', () => {
    assert.equal(plain('Mac &amp; cheese &#8211; <i>quick</i>'), 'Mac & cheese – quick');
  });
  it('reads a full page: @graph, array types, sections, nutrition, broken blocks skipped', async () => {
    const { recipe, page } = readPage(await fixture('recipe-jsonld.html'));
    assert.equal(recipe.title, 'Palak Paneer & Jeera Rice');
    assert.equal(recipe.summary, 'Creamy spinach curry with soft paneer.');
    assert.equal(recipe.creator, 'Asha Rao');
    assert.equal(recipe.imageURL, 'https://spicekitchen.example/palak.jpg');
    assert.equal(recipe.servings, 4);
    assert.deepEqual([recipe.prepMinutes, recipe.cookMinutes, recipe.totalMinutes], [15, 25, 40]);
    assert.equal(recipe.cuisine, 'Indian');
    assert.equal(recipe.ingredients.length, 5);
    assert.deepEqual(recipe.steps.map((s) => s.text), ['Blanch the spinach for 2 minutes, then blend.', 'Fry the onion until golden – about 8 minutes.', 'Add paneer and simmer for 5 minutes.']);
    assert.equal(recipe.nutrition.calories, 350);
    assert.equal(recipe.nutrition.sodium, 600, 'grams of sodium become milligrams');
    assert.equal(page.siteName, 'Spice Kitchen');
  });
  it('falls back to visible article text when there is no recipe card', async () => {
    const { recipe, text } = readPage(await fixture('no-jsonld.html'));
    assert.equal(recipe, null);
    assert.match(text, /200 g red lentils/);
    assert.doesNotMatch(text, /tracking|Home Recipes About|©/);
  });
  it('finds a recipe however deeply it is nested', () => {
    assert.equal(findRecipe({ mainEntity: { itemListElement: [{ item: { '@type': 'Recipe', name: 'X' } }] } }).name, 'X');
    assert.equal(findRecipe({ '@type': 'Article' }), null);
  });
});

describe('social links', () => {
  it('detects platforms', () => {
    assert.equal(platformOf('https://www.instagram.com/reel/abc/'), 'instagram');
    assert.equal(platformOf('https://vm.tiktok.com/xyz'), 'tiktok');
    assert.equal(platformOf('https://youtu.be/abcdefgh'), 'youtube');
    assert.equal(platformOf('https://pin.it/abc'), 'pinterest');
    assert.equal(platformOf('https://www.allrecipes.com/x'), 'web');
    assert.equal(platformOf('https://notinstagram.com/x'), 'web');
  });
  it('reads YouTube ids', () => {
    assert.equal(youtubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10'), 'dQw4w9WgXcQ');
    assert.equal(youtubeId('https://youtu.be/dQw4w9WgXcQ?si=abc'), 'dQw4w9WgXcQ');
    assert.equal(youtubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    assert.equal(youtubeId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    assert.equal(youtubeId('https://www.youtube.com/@chef'), null);
  });
  it('canonicalises: tracking removed, same post → same URL', () => {
    assert.equal(canonicalize('https://www.instagram.com/reel/abc/?igsh=xyz&utm_source=ig#c'), 'https://www.instagram.com/reel/abc/');
    assert.equal(canonicalize('https://youtu.be/dQw4w9WgXcQ?si=1'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    assert.equal(canonicalize('https://www.tiktok.com/@a/video/1?is_from_webapp=1&sender_device=pc'), 'https://www.tiktok.com/@a/video/1');
    assert.equal(canonicalize('https://blog.example/recipe?s=pasta&utm_medium=x'), 'https://blog.example/recipe?s=pasta', 'search params on normal sites are kept');
  });
  it('pulls the caption out of Instagram’s description and finds recipe links', () => {
    assert.equal(captionFromMeta('1,234 likes, 56 comments - chef on May 1, 2026: "Best dal ever"'), 'Best dal ever');
    assert.equal(captionFromMeta('12K likes, 3 comments - chef on May 1, 2026: “Dal”.'), 'Dal');
    assert.equal(captionFromMeta('Just a description'), 'Just a description');
    assert.deepEqual(findLinks('Recipe: https://site.example/dal. More: https://www.instagram.com/p/x https://linktr.ee/me https://site.example/dal'), ['https://site.example/dal']);
  });
});

describe('toDraft — the exact shape the iOS decoder expects', () => {
  it('cleans, clamps and drops empties', () => {
    const draft = toDraft({
      title: '  <b>Dal</b>  ', servings: 0, prepMinutes: -4, cookMinutes: 99_999, mealTypes: ['Dinner', 'brunch'],
      tags: ['quick', 'quick', ' ', 'x'.repeat(40)], sourceURL: 'javascript:alert(1)', imageURL: 'https://img.example/a.jpg',
      ingredients: ['2 cups toor dal', { text: '', name: '' }, { text: '1 tsp salt', quantity: Number.NaN, quantityMax: 5, unit: 'tsp', name: 'salt' }],
      steps: ['  ', { text: 'Boil', timerSeconds: 999_999 }],
      nutrition: { calories: 300, protein: -1, matched: 5, total: 2 },
    });
    assert.equal(draft.title, 'Dal');
    assert.equal(draft.servings, 1);
    assert.equal(draft.prepMinutes, 0);
    assert.equal(draft.cookMinutes, 2880);
    assert.deepEqual(draft.mealTypes, ['dinner']);
    assert.deepEqual(draft.tags, ['quick', 'x'.repeat(30)]);
    assert.equal(draft.sourceURL, undefined);
    assert.equal(draft.imageURL, 'https://img.example/a.jpg');
    assert.equal(draft.ingredients.length, 2);
    assert.equal(draft.ingredients[1].quantity, undefined);
    assert.equal(draft.ingredients[1].quantityMax, undefined, 'a max without a min is dropped');
    assert.deepEqual(draft.steps, [{ text: 'Boil', timerSeconds: 86_400 }]);
    assert.deepEqual(Object.keys(draft.nutrition).sort(), ['calories', 'carbs', 'fat', 'fiber', 'matched', 'protein', 'sodium', 'sugar', 'total'].sort());
    assert.equal(draft.nutrition.total, 5);
  });
  it('omits nutrition when there are no calories and never emits nulls', () => {
    const draft = toDraft({ title: 'X', ingredients: ['1 egg'], nutrition: { calories: 0 } });
    assert.equal(draft.nutrition, undefined);
    assert.equal(JSON.stringify(draft).includes('null'), false);
  });
});

describe('periods and config', () => {
  it('weeks start on Monday (UTC), days are dates', () => {
    assert.equal(weekStart(new Date('2026-10-04T23:00:00Z')), '2026-09-28'); // Sunday → previous Monday
    assert.equal(weekStart(new Date('2026-10-05T00:00:00Z')), '2026-10-05'); // Monday
    assert.equal(dayStart(new Date('2026-10-05T13:00:00Z')), '2026-10-05');
  });
  it('fails fast with a readable list of bad settings', () => {
    assert.throws(() => loadConfig({ PORT: 'abc', DB_NAME: 'bad-name!' }), /PORT[\s\S]*DB_NAME/);
    assert.throws(() => loadConfig({ NODE_ENV: 'production' }), /OPENAI_API_KEY is required/);
    assert.equal(loadConfig({}).OPENAI_MODEL, 'gpt-4o-mini');
    assert.equal(loadConfig({}).HOST, '127.0.0.1');
  });
});
