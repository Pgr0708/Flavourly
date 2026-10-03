// Live check of every outside service Flavourly depends on — real requests, through the same code the server uses.
//   npm run check:live            (reads backend/.env; services without a key are reported as skipped)
// Costs nothing: OpenAI is checked by listing models (no tokens), the rest are free APIs.
import { createCache } from '../src/cache.js';
import { loadConfig } from '../src/config.js';
import { createFetcher } from '../src/fetcher.js';
import { createNutrition } from '../src/nutrition.js';

const config = loadConfig();
const fetcher = createFetcher({ userAgent: config.FETCH_USER_AGENT });
const results = [];

async function check(name, run) {
  const started = Date.now();
  try {
    const detail = await run();
    results.push({ name, ok: detail !== 'skip', detail: detail === 'skip' ? 'skipped (no key in .env)' : detail, ms: Date.now() - started });
  } catch (error) {
    results.push({ name, ok: false, detail: error.message, ms: Date.now() - started });
  }
}
const expect = (condition, message) => { if (!condition) throw new Error(message); };

await check('OpenAI (key + model access)', async () => {
  if (!config.OPENAI_API_KEY) return 'skip';
  const res = await fetch(`${config.OPENAI_BASE_URL}/models`, { headers: { Authorization: `Bearer ${config.OPENAI_API_KEY}` } });
  expect(res.ok, `HTTP ${res.status}`);
  const ids = new Set((await res.json()).data.map((m) => m.id));
  const missing = [config.OPENAI_MODEL, config.TRANSCRIBE_MODEL, ...(config.IMAGE_GENERATION ? [config.IMAGE_MODEL] : [])].filter((m) => !ids.has(m));
  expect(!missing.length, `key works but these models are not available: ${missing.join(', ')}`);
  return `${config.OPENAI_MODEL}, ${config.TRANSCRIBE_MODEL}${config.IMAGE_GENERATION ? `, ${config.IMAGE_MODEL}` : ''} available`;
});

await check(`USDA FoodData Central (${config.USDA_API_KEY === 'DEMO_KEY' ? 'DEMO_KEY — get a free key' : 'own key'})`, async () => {
  const cache = createCache({});
  const nutrition = createNutrition({ config: { ...config, SPOONACULAR_API_KEY: '' }, cache });
  const result = await nutrition.forLines(['200 g cooked white rice', '2 large eggs'], 2, { minCoverage: 0.5 });
  await cache.close();
  expect(result?.calories > 150 && result.calories < 400, `unexpected calories per serving: ${JSON.stringify(result)}`);
  return `rice + eggs ÷ 2 = ${result.calories} kcal, ${result.protein} g protein per serving`;
});

await check('Spoonacular', async () => {
  if (!config.SPOONACULAR_API_KEY) return 'skip';
  const res = await fetch(`https://api.spoonacular.com/recipes/parseIngredients?apiKey=${config.SPOONACULAR_API_KEY}&includeNutrition=true`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'ingredientList=1 banana&servings=1',
  });
  expect(res.ok, `HTTP ${res.status}${res.status === 402 ? ' (daily points used up)' : ''}`);
  const [banana] = await res.json();
  const kcal = banana?.nutrition?.nutrients?.find((n) => n.name === 'Calories')?.amount;
  expect(kcal > 50 && kcal < 200, `unexpected banana calories ${kcal}`);
  return `1 banana = ${Math.round(kcal)} kcal`;
});

await check('Open Food Facts (barcodes, called by the app)', async () => {
  const res = await fetch('https://world.openfoodfacts.org/api/v2/product/3017620422003.json?fields=product_name,brands,allergens_tags', {
    headers: { 'User-Agent': 'Flavourly/1.0 (live-check; https://flavourly.dakshyaminfotech.store)' },
  });
  expect(res.ok, `HTTP ${res.status}`);
  const { status, product } = await res.json();
  expect(status === 1 && product?.allergens_tags?.length, 'product or allergens missing');
  return `${product.brands} ${product.product_name}: ${product.allergens_tags.join(', ')}`;
});

await check('Wikipedia (known-dish filter)', async () => {
  const data = await fetcher.fetchJson('https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=3&srsearch=pav%20bhaji%20India%20food');
  const titles = data?.query?.search?.map((s) => s.title) ?? [];
  expect(titles.some((t) => /pav bhaji/i.test(t)), `no match in ${JSON.stringify(titles)}`);
  return `found "${titles[0]}"`;
});

await check('YouTube oEmbed (link import)', async () => {
  const embed = await fetcher.fetchJson(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent('https://www.youtube.com/watch?v=dQw4w9WgXcQ')}`);
  expect(embed?.title && embed?.author_name, 'no title/author');
  return `"${embed.title}" by ${embed.author_name}`;
});

await check('YouTube Data API (descriptions)', async () => {
  if (!config.YOUTUBE_API_KEY) return 'skip';
  const data = await fetcher.fetchJson(`https://www.googleapis.com/youtube/v3/videos?part=snippet&id=dQw4w9WgXcQ&key=${config.YOUTUBE_API_KEY}`);
  expect(data?.items?.[0]?.snippet?.description, 'no description');
  return 'description readable';
});

await check('TikTok oEmbed (link import)', async () => {
  const embed = await fetcher.fetchJson(`https://www.tiktok.com/oembed?url=${encodeURIComponent('https://www.tiktok.com/@scout2015/video/6718335390845095173')}`);
  expect(embed?.author_name, 'no author');
  return `caption from @${embed.author_name} readable`;
});

await check('TheMealDB (dish photos)', async () => {
  const data = await fetcher.fetchJson(`https://www.themealdb.com/api/json/v1/${config.THEMEALDB_API_KEY}/search.php?s=Lasagne`);
  expect(data?.meals?.[0]?.strMealThumb, 'no photo');
  return `${data.meals[0].strMeal} photo found${config.THEMEALDB_API_KEY === '1' ? ' (development key "1")' : ''}`;
});

await check('Pixabay (photos)', async () => {
  if (!config.PIXABAY_API_KEY) return 'skip';
  const res = await fetch(`https://pixabay.com/api/?key=${config.PIXABAY_API_KEY}&q=pancakes&image_type=photo&category=food&per_page=3`);
  expect(res.ok, `HTTP ${res.status}${res.status === 400 ? ' (wrong key?)' : ''}`);
  return `${(await res.json()).totalHits} pancake photos`;
});

await check('Pexels (photos)', async () => {
  if (!config.PEXELS_API_KEY) return 'skip';
  const res = await fetch('https://api.pexels.com/v1/search?query=pancakes&per_page=1', { headers: { Authorization: config.PEXELS_API_KEY } });
  expect(res.ok, `HTTP ${res.status}`);
  return 'key works';
});

await check('Unsplash (photos)', async () => {
  if (!config.UNSPLASH_ACCESS_KEY) return 'skip';
  const res = await fetch(`https://api.unsplash.com/search/photos?query=pancakes&per_page=1&client_id=${config.UNSPLASH_ACCESS_KEY}`);
  expect(res.ok, `HTTP ${res.status}`);
  return `key works, ${res.headers.get('x-ratelimit-remaining') ?? '?'} requests left this hour`;
});

await check('Openverse (CC photos)', async () => {
  const data = await fetcher.fetchJson('https://api.openverse.org/v1/images/?q=pancakes&license_type=commercial&page_size=1');
  expect(data?.results?.length, 'no results');
  return `${data.result_count} commercial-use photos`;
});

await check('RevenueCat (Premium check)', async () => {
  if (!config.REVENUECAT_SECRET_KEY) return 'skip';
  const res = await fetch(`${config.REVENUECAT_BASE_URL}/subscribers/live-check-user`, { headers: { Authorization: `Bearer ${config.REVENUECAT_SECRET_KEY}` } });
  expect(res.ok, `HTTP ${res.status}${res.status === 401 ? ' (wrong secret key)' : ''}`);
  return 'secret key accepted';
});

for (const r of results) console.log(`${r.ok ? '✔' : r.detail.startsWith('skipped') ? '–' : '✘'} ${r.name}: ${r.detail} (${r.ms} ms)`);
const failed = results.filter((r) => !r.ok && !r.detail.startsWith('skipped'));
console.log(failed.length ? `\n${failed.length} service(s) failing` : '\nAll reachable services OK');
process.exit(failed.length ? 1 : 0);
