// Premium "make it my way": a cook's own version of a dish ("add paneer", "air fryer"), written by AI once,
// checked by moderation, saved, and shown to other cooks in the same country — same region first.
import { variationTasks } from './ai/tasks.js';
import { dishSlug } from './dishes.js';
import { toDraft } from './recipe.js';
import { HttpError, log } from './util.js';
import { cleanText, countryName } from './validation.js';

export function createVariations({ db, ai, nutrition, images, usage }) {
  const toItem = (row) => {
    const recipe = typeof row.recipe === 'string' ? JSON.parse(row.recipe) : row.recipe;
    return {
      id: String(row.id),
      title: row.title,
      change: row.change_text,
      baseTitle: row.base_title,
      country: row.country,
      region: row.region,
      tried: Number(row.tried),
      recipe: { ...recipe, remoteID: `variation-${row.id}`, imageURL: row.image_url ?? recipe.imageURL ?? null },
    };
  };

  return {
    async create({ base, change, country, region, deviceId, premium }) {
      await usage.assertAllowed(deviceId, 'variation', premium);
      const wish = cleanText(change).slice(0, 200);
      // Shared with other people, so the cook's words are checked first (OpenAI moderation is free).
      if (await ai.flagged(wish)) throw new HttpError(422, "We can't make that change. Try describing it differently.", { code: 'unsafe' });

      const result = await ai.json(variationTasks.make({
        base: { title: base.title, servings: base.servings ?? null, ingredients: base.ingredients, steps: base.steps },
        change: wish,
        country: country ? countryName(country) : null,
        region: region ?? null,
      }));
      if (!result.ok || !(result.recipe?.ingredients?.length >= 2) || !result.recipe?.steps?.length) {
        throw new HttpError(422, "That change doesn't work for this dish. Try another idea — like an ingredient to add, swap or skip.", { code: 'bad_change' });
      }
      let draft = toDraft(result.recipe, { method: 'variation' });
      if (!draft.title || dishSlug(draft.title) === dishSlug(base.title)) draft.title = `${base.title} (${wish})`.slice(0, 120);
      if (await ai.flagged(draft.title)) throw new HttpError(422, "We can't make that change. Try describing it differently.", { code: 'unsafe' });
      draft = await nutrition.enrich(draft);

      // Free photo of the new dish when one exists, else the original's. Never GPT here.
      const photo = await images.recipePhoto({ title: draft.title, freeOnly: true }).then((p) => p.url, () => null);
      const imageURL = photo ?? base.imageURL ?? null;

      const [insert] = await db.query(
        'INSERT INTO variations (base_slug, base_title, title, change_text, country, region, recipe, image_url, device_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [dishSlug(base.title), base.title.slice(0, 160), draft.title.slice(0, 160), wish, country ?? null, region ?? null, JSON.stringify(draft), imageURL, deviceId],
      );
      await usage.consume(deviceId, 'variation', premium);
      log.info('variation added', { base: base.title, title: draft.title });
      const [[row]] = await db.query('SELECT * FROM variations WHERE id = ?', [insert.insertId]);
      return { variation: toItem(row) };
    },

    /** Versions of this dish made by cooks in the same country, same region first, most tried first. */
    async list({ title, country, region }) {
      if (!country) return { variations: [] };
      const [rows] = await db.query(
        `SELECT * FROM variations WHERE base_slug = ? AND country = ?
         ORDER BY (region <=> ?) DESC, tried DESC, created_at DESC LIMIT 20`,
        [dishSlug(title), country, region ?? null],
      );
      return { variations: rows.map(toItem) };
    },

    /** "I tried it": counted once per device. */
    async tried({ id, deviceId }) {
      const [result] = await db.query(
        'INSERT IGNORE INTO variation_tries (variation_id, device_id) SELECT id, ? FROM variations WHERE id = ?',
        [deviceId, id],
      );
      if (result.affectedRows) await db.query('UPDATE variations SET tried = tried + 1 WHERE id = ?', [id]);
      const [[row]] = await db.query('SELECT tried FROM variations WHERE id = ?', [id]);
      if (!row) throw new HttpError(404, 'That version was removed.');
      return { tried: Number(row.tried) };
    },
  };
}
