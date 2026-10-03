import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { setup } from './helpers.js';

// Premium video listening: the app sends only the audio of a video the user picked.
let t;
before(async () => { t = await setup({ env: { PREMIUM_TRANSCRIBE_MINUTES_PER_WEEK: '2', TRANSCRIBE_MAX_MB: '1' } }); });
after(() => t.teardown());

const audio = (size = 4_000, marker = '') => Buffer.concat([Buffer.from(marker), Buffer.alloc(size, 7)]);
const send = (token, body, { user = 'premium-user', type = 'audio/m4a' } = {}) => fetch(`${t.base}/v1/ai/transcribe`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': type, ...(user ? { 'X-RC-App-User': user } : {}) },
  body,
}).then(async (res) => ({ status: res.status, body: await res.json() }));

describe('POST /v1/ai/transcribe', () => {
  it('free users are told it is Premium, and OpenAI is never called', async () => {
    const before = t.ai.calls.length;
    const res = await send(await t.register(), audio(), { user: null });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'premium');
    assert.equal(t.ai.calls.length, before);
  });
  it('Premium gets the spoken text, using the configured model', async () => {
    const res = await send(await t.register(), audio());
    assert.equal(res.status, 200);
    assert.match(res.body.text, /200 g noodles/);
    assert.equal(t.ai.calls.at(-1).path, '/v1/audio/transcriptions');
    assert.equal(t.ai.calls.at(-1).body.model, 'gpt-4o-mini-transcribe');
  });
  it('rejects empty, oversized, wrong-type and silent audio clearly', async () => {
    assert.equal((await send(await t.register(), audio(10))).status, 400);
    assert.equal((await send(await t.register(), audio(1_200_000))).status, 413);
    assert.equal((await send(await t.register(), '{"a":1}', { type: 'application/json' })).status, 400);
    const silent = await send(await t.register(), audio(4_000, 'SILENT'));
    assert.equal(silent.status, 422);
    assert.match(silent.body.error, /couldn't hear a recipe/);
  });
  it('a weekly minutes cap per device keeps the bill bounded, even for Premium', async () => {
    const token = await t.register();
    assert.equal((await send(token, audio())).status, 200, 'a short clip counts as 1 minute');
    assert.equal((await send(token, audio())).status, 200);
    const third = await send(token, audio());
    assert.equal(third.status, 429);
    assert.equal(third.body.code, 'limit');
    assert.match(third.body.error, /2 minutes of video listening.*Monday/);
  });
});
