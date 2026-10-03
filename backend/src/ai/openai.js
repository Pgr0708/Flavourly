import { HttpError, log, sleep } from '../util.js';

/**
 * Minimal OpenAI Chat Completions client with Structured Outputs (strict JSON Schema), timeouts and
 * retries on 429/5xx. Native fetch — no SDK needed. The key never leaves this server.
 */
export function createOpenAI({ apiKey, model, baseUrl, timeoutMs }) {
  async function call(path, body, { attempts = 3, form = false } = {}) {
    if (!apiKey) throw new HttpError(503, 'AI is not set up on the server yet.');
    let lastError;
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetch(`${baseUrl.replace(/\/$/, '')}${path}`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${apiKey}`, ...(form ? {} : { 'Content-Type': 'application/json' }) },
          body: form ? body() : JSON.stringify(body),
          signal: controller.signal,
        });
        if (response.ok) return await response.json();
        const detail = await response.text().catch(() => '');
        lastError = new HttpError(response.status === 429 ? 503 : 502, 'The AI service is busy. Please try again in a minute.');
        log.warn('openai error', { status: response.status, attempt, detail: detail.slice(0, 300) });
        if (response.status !== 429 && response.status < 500) break; // bad request: retrying won't help
      } catch (error) {
        lastError = new HttpError(504, 'The AI took too long to answer. Please try again.');
        log.warn('openai request failed', { attempt, error: error.name });
      } finally {
        clearTimeout(timer);
      }
      if (attempt < attempts) await sleep(400 * 2 ** (attempt - 1) + Math.random() * 200);
    }
    throw lastError;
  }

  /** Returns the parsed JSON object the model produced for `schema` (a strict JSON Schema). */
  async function json({ name, schema, system, user, temperature = 0.3, maxTokens = 2_500, model: override }) {
    const reply = await call('/chat/completions', {
      model: override ?? model,
      temperature,
      max_tokens: maxTokens,
      response_format: { type: 'json_schema', json_schema: { name, strict: true, schema } },
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
    });
    const message = reply?.choices?.[0]?.message;
    if (message?.refusal) throw new HttpError(422, "The AI couldn't help with that request.");
    if (reply?.choices?.[0]?.finish_reason === 'length') throw new HttpError(502, 'That recipe was too long for the AI to finish. Try a shorter text.');
    try {
      const data = JSON.parse(message?.content ?? '');
      log.info('openai ok', { name, tokens: reply.usage?.total_tokens });
      return data;
    } catch {
      throw new HttpError(502, 'The AI sent an unreadable answer. Please try again.');
    }
  }

  /** gpt-image-1: returns raw image bytes (JPEG). */
  async function image({ prompt, model: imageModel, quality = 'low' }) {
    const reply = await call('/images/generations', {
      model: imageModel,
      prompt,
      size: '1024x1024',
      quality,
      output_format: 'jpeg',
      n: 1,
    }, { attempts: 2 });
    const b64 = reply?.data?.[0]?.b64_json;
    if (!b64) throw new HttpError(502, "The photo couldn't be created.");
    return Buffer.from(b64, 'base64');
  }

  /** Speech → text for the audio of a video the user picked themselves. `audio` is a Buffer. */
  async function transcribe({ audio, mimeType, model: speechModel, prompt }) {
    const ext = mimeType.includes('mp4') || mimeType.includes('m4a') ? 'm4a' : mimeType.split('/')[1]?.replace(/[^a-z0-9]/g, '') || 'm4a';
    // A fresh FormData per attempt: a consumed body can't be re-sent on retry.
    const form = () => {
      const data = new FormData();
      data.append('file', new Blob([audio], { type: mimeType }), `audio.${ext}`);
      data.append('model', speechModel);
      data.append('response_format', 'json');
      if (prompt) data.append('prompt', prompt);
      return data;
    };
    const reply = await call('/audio/transcriptions', form, { attempts: 2, form: true });
    log.info('openai transcribe ok', { bytes: audio.length });
    return String(reply?.text ?? '').trim();
  }

  /** Free OpenAI moderation: true when the text breaks the content rules (checked before anything is shared). */
  async function flagged(text) {
    const reply = await call('/moderations', { model: 'omni-moderation-latest', input: String(text).slice(0, 4_000) }, { attempts: 2 });
    return Boolean(reply?.results?.[0]?.flagged);
  }

  return { json, image, transcribe, flagged, get configured() { return Boolean(apiKey); } };
}
