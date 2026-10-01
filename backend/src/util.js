import crypto from 'node:crypto';

/** An error that becomes `{ error: message }` with this status. The app shows `message` to the user. */
export class HttpError extends Error {
  constructor(status, message, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

export const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** One JSON line per event; PM2 writes stdout/stderr to its log files. Never logs request bodies. */
export const log = {
  info: (msg, data = {}) => process.stdout.write(`${JSON.stringify({ t: new Date().toISOString(), level: 'info', msg, ...data })}\n`),
  warn: (msg, data = {}) => process.stderr.write(`${JSON.stringify({ t: new Date().toISOString(), level: 'warn', msg, ...data })}\n`),
  error: (msg, data = {}) => process.stderr.write(`${JSON.stringify({ t: new Date().toISOString(), level: 'error', msg, ...data })}\n`),
};

/** Monday (UTC) of the week containing `date`, as YYYY-MM-DD — matches the app's Monday-first weeks. */
export function weekStart(date = new Date()) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = (d.getUTCDay() + 6) % 7; // 0 = Monday
  d.setUTCDate(d.getUTCDate() - day);
  return d.toISOString().slice(0, 10);
}

export const dayStart = (date = new Date()) => date.toISOString().slice(0, 10);
