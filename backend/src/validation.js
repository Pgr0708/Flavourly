import net from 'node:net';
import { z } from 'zod';
import { isPrivateIP } from './fetcher.js';
import { HttpError } from './util.js';

// Mirrors the app's Sanitize/Validate (Flavourly/Domain/Validation.swift) so both sides agree.
const INVISIBLE = /[​⁠﻿­‪-‮⁦-⁩]/g;
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g;
const TAG = /<\/?[A-Za-z][^<>]{0,300}>/g;

/** Unicode-normalised, no control/invisible characters or HTML tags, whitespace collapsed, trimmed. */
export function cleanText(value, { multiline = false } = {}) {
  if (typeof value !== 'string') return '';
  let text = value.normalize('NFC').replace(TAG, ' ').replace(INVISIBLE, '').replace(/\r\n?/g, '\n').replace(/\t/g, ' ').replace(CONTROL, '');
  text = multiline ? text.replace(/[  ]{2,}/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n') : text.replace(/\s+/g, ' ');
  return text.trim();
}

const hasLetter = (text) => /\p{L}/u.test(text);

/** A string that is cleaned first, then length-checked (so "   " counts as empty). */
export const text = (max, { min = 0, multiline = false, letters = false } = {}) => {
  let schema = z.string({ invalid_type_error: 'must be text' }).transform((v) => cleanText(v, { multiline })).pipe(
    z.string().min(min, min <= 1 ? 'is required' : `must be at least ${min} characters`).max(max, `must be at most ${max} characters`),
  );
  if (letters) schema = schema.refine((v) => v === '' || hasLetter(v), 'needs some letters');
  return schema;
};

const list = (maxItems, maxLength) => z.array(text(maxLength)).max(maxItems, `can have at most ${maxItems} items`)
  .transform((items) => [...new Set(items.filter(Boolean))]);

export const rulesSchema = z.object({
  allergies: list(30, 60).default([]),
  diets: list(20, 40).default([]),
  dislikes: list(30, 60).default([]),
  mildOnly: z.boolean().default(false),
}).default({});

export const slotEnum = z.enum(['breakfast', 'lunch', 'dinner', 'snack']);

/** Public web link: http(s), no credentials, normal ports. The fetcher additionally blocks private addresses. */
export const webUrl = z.string().transform((v) => cleanText(v)).pipe(z.string().min(1, 'is required').max(2048, 'is too long'))
  .refine((value) => {
    try {
      const url = new URL(value);
      const host = url.hostname.replace(/^\[|\]$/g, '');
      return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password
        && (url.port === '' || url.port === '80' || url.port === '443') && host.includes('.')
        && !(net.isIP(host) && isPrivateIP(host)) && !/\.(local|localhost|internal|lan)$/i.test(host);
    } catch {
      return false;
    }
  }, 'must be a public http(s) link');

const regionNames = new Intl.DisplayNames(['en'], { type: 'region' });
// Codes Intl knows that are not places people live and cook.
const NOT_COUNTRIES = new Set(['EU', 'EZ', 'UN', 'QO', 'ZZ', 'AQ', 'BV', 'HM', 'TF', 'UM', 'CP', 'DG', 'EA', 'IC', 'TA', 'AC']);

/** English name for an ISO 3166 country code, or null for unknown codes. */
export function countryName(code) {
  if (!/^[A-Z]{2}$/.test(code ?? '') || NOT_COUNTRIES.has(code)) return null;
  const name = regionNames.of(code);
  return name && name !== code && !/unknown/i.test(name) ? name : null;
}

export const countryCode = z.string().transform((v) => cleanText(v).toUpperCase())
  .pipe(z.string().regex(/^[A-Z]{2}$/, 'must be a 2-letter country code'))
  .refine((code) => countryName(code) != null, 'is not a country we know');

export const schemas = {
  device: z.object({
    installID: z.string().regex(/^[A-Za-z0-9-]{8,64}$/, 'must be 8–64 letters, digits or dashes'),
    platform: z.enum(['ios']).default('ios'),
    appVersion: z.string().regex(/^[0-9A-Za-z.\-]{1,20}$/, 'must look like 1.2.3').default('1.0'),
  }),
  importLink: z.object({
    url: webUrl,
    pageText: text(20_000, { multiline: true }).optional().nullable(),
    rules: rulesSchema,
  }),
  extract: z.object({
    text: text(12_000, { min: 20, multiline: true, letters: true }),
    kind: z.enum(['text', 'ocr', 'transcript', 'caption']).default('text'),
    sourceURL: webUrl.optional().nullable(),
    rules: rulesSchema,
  }),
  substitutes: z.object({
    ingredient: text(200, { min: 1, letters: true }),
    recipeTitle: text(120, { min: 1 }),
    otherIngredients: list(100, 200).default([]),
    rules: rulesSchema,
  }),
  cookNow: z.object({
    minutes: z.number().int().min(5).max(600).optional().nullable(),
    craving: text(80).default(''),
    pantry: list(100, 60).default([]),
    okToBuy: z.number().int().min(0).max(10).default(2),
    servings: z.number().int().min(1).max(40).default(2),
    rules: rulesSchema,
    avoidTitles: list(40, 120).default([]),
    country: countryCode.optional().nullable(),
  }),
  plan: z.object({
    slots: z.array(z.object({
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'must be YYYY-MM-DD')
        .refine((value) => { const day = new Date(`${value}T00:00:00Z`); return !Number.isNaN(day.getTime()) && day.toISOString().startsWith(value); }, 'is not a real date'),
      slot: slotEnum,
      candidates: z.array(z.string().min(1).max(128)).max(20),
    })).min(1, 'needs at least one meal').max(35),
    candidates: z.array(z.object({
      id: z.string().min(1).max(128),
      title: text(120, { min: 1 }),
      minutes: z.number().int().min(0).max(2880),
      slots: z.array(slotEnum).max(4),
      cuisine: text(40).optional().nullable(),
      protein: z.number().int().min(0).max(500),
      reasons: list(5, 80).default([]),
    })).max(300),
    preferences: list(30, 80).default([]),
    rules: rulesSchema,
  }),
  image: z.object({
    title: text(120, { min: 2, letters: true }),
    description: text(300).optional().nullable(),
  }),
  discover: z.object({ country: countryCode }),
  empty: z.object({}).passthrough(),
};

/** Express middleware: replaces req.body with the cleaned, validated value or answers 400 with every problem. */
export const validate = (schema) => (req, _res, next) => {
  const result = schema.safeParse(req.body ?? {});
  if (!result.success) {
    const fields = {};
    for (const issue of result.error.issues) {
      const key = issue.path.join('.') || 'body';
      fields[key] ??= issue.message;
    }
    const [first] = Object.entries(fields);
    return next(new HttpError(400, `Please check ${first[0]}: ${first[1]}`, { code: 'validation', fields }));
  }
  req.body = result.data;
  next();
};
