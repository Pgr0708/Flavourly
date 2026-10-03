// Real-data accuracy check: 30 everyday ingredient lines through the live USDA lookup vs reference calories.
//   USDA_API_KEY=... npm run check:nutrition     (needs a real key; DEMO_KEY is rate-limited)

const { loadConfig } = await import('../src/config.js');
const { createCache } = await import('../src/cache.js');
const { createNutrition } = await import('../src/nutrition.js');
const config = loadConfig(); const cache = createCache({}); const n = createNutrition({ config: { ...config, SPOONACULAR_API_KEY: '' }, cache });
// Reference kcal (USDA SR Legacy household measures).
const expected = {'200 g cooked white rice':260,'2 large eggs':143,'1 tbsp olive oil':119,'2 tbsp butter':204,'1 cup milk':149,'1 tsp salt':0,'200 g spaghetti':742,'400 g canned tomatoes':80,'1 cup cooked lentils':230,'150 g greek yogurt':110,'100 g raw chicken breast':120,'1 medium onion':44,'2 cloves garlic':9,'1 cup all-purpose flour':455,'1 tbsp sugar':48,'1 medium potato':160,'1 tbsp soy sauce':9,'100 g cheddar cheese':403,'1 banana':105,'1 cup frozen peas':110,
  '1 cup chickpeas, cooked':269,'1 avocado':240,'2 tomatoes':44,'1 carrot':25,'1 cup spinach':7,'1 tbsp honey':64,'1 cup heavy cream':821,'200 g salmon':416,'1 lemon':17,'1 tsp cumin seeds':8};
let off = 0;
for (const [line, want] of Object.entries(expected)) {
  const r = await n.forLines([line], 1, { minCoverage: 0.5 });
  const got = r?.calories; const bad = got == null || Math.abs(got - want) > Math.max(25, want * 0.25);
  if (bad) off++;
  console.log((bad ? '✘ ' : '✔ ') + line.padEnd(26), String(got ?? 'no match').padStart(9), `kcal  (reference ≈ ${want})`);
}
console.log(`${Object.keys(expected).length - off} of ${Object.keys(expected).length} within 25%`);
process.exitCode = off > 2 ? 1 : 0;
await cache.close();
