// Which dishes get a free, credited photo vs. GPT — real requests, GPT switched off (costs nothing).
//   npm run check:photos

const { loadConfig } = await import('../src/config.js');
const { createCache } = await import('../src/cache.js');
const { createFetcher } = await import('../src/fetcher.js');
const { createImages } = await import('../src/services.js');
const config = { ...loadConfig(), IMAGE_GENERATION: false };
const cache = createCache({});
const images = createImages({ config, ai: null, cache, fetcher: createFetcher({ userAgent: config.FETCH_USER_AGENT }) });
const dishes = ['Teriyaki chicken casserole', 'Lasagne', 'Beef Wellington', 'Peanut noodle bowl', 'Khow suey', 'Pav bhaji', 'Masala dosa', 'Paneer tikka', 'Chole bhature', 'Butter chicken', 'Pad thai', 'Shakshuka', 'Spaghetti carbonara', 'Garlic butter noodles', 'Aloo paratha', 'Grandma special lentil stew', 'Quick masala omelette'];
let free = 0;
for (const title of dishes) {
  try {
    const { url } = await images.recipePhoto({ title });
    const credit = decodeURIComponent(new URL(url).hash.match(/credit=([^&]*)/)?.[1] ?? '');
    free += 1;
    console.log('✔', title.padEnd(28), new URL(url).hostname.padEnd(24), credit);
  } catch (error) { console.log('·', title.padEnd(28), error.status === 501 ? '→ would use GPT (~$0.01, once)' : error.message); }
}
console.log(`${free} of ${dishes.length} found a free, credited photo`);
await cache.close();
