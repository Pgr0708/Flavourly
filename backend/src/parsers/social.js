import { plain } from './jsonld.js';

const HOSTS = [
  ['instagram', /(^|\.)instagram\.com$/],
  ['tiktok', /(^|\.)tiktok\.com$/],
  ['youtube', /(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$/],
  ['pinterest', /(^|\.)pinterest\.[a-z.]+$|^pin\.it$/],
  ['facebook', /(^|\.)(facebook\.com|fb\.watch|fb\.com)$/],
  ['x', /(^|\.)(twitter\.com|x\.com)$/],
];

export const PLATFORM_NAMES = { instagram: 'Instagram', tiktok: 'TikTok', youtube: 'YouTube', pinterest: 'Pinterest', facebook: 'Facebook', x: 'X' };

const NOT_RECIPES = /(^|\.)(linktr\.ee|beacons\.ai|bio\.link|linkin\.bio|amazon\.[a-z.]+|amzn\.to|spotify\.com|apple\.com|patreon\.com)$/;

const TRACKING = /^(utm_\w+|fbclid|gclid|mc_cid|mc_eid|igsh|igshid|ref_src)$/i;
// On social links these only describe how the post was shared, never which post it is.
const SOCIAL_TRACKING = /^(si|feature|share_id|_t|_r|is_from_webapp|sender_device|ref|s|t|lang)$/i;

export function platformOf(url) {
  const host = new URL(url).hostname.toLowerCase();
  return HOSTS.find(([, pattern]) => pattern.test(host))?.[0] ?? 'web';
}

export function youtubeId(raw) {
  const url = new URL(raw);
  const host = url.hostname.toLowerCase();
  if (host.endsWith('youtu.be')) return url.pathname.slice(1).split('/')[0] || null;
  if (url.searchParams.get('v')) return url.searchParams.get('v');
  const match = /^\/(?:shorts|embed|live|v)\/([\w-]{6,})/.exec(url.pathname);
  return match ? match[1] : null;
}

/** Same post → same cache key: no tracking parameters, no fragment, canonical YouTube form. */
export function canonicalize(raw) {
  const url = new URL(raw);
  url.hash = '';
  url.hostname = url.hostname.toLowerCase();
  const social = platformOf(url.toString()) !== 'web';
  for (const key of [...url.searchParams.keys()]) {
    if (TRACKING.test(key) || (social && SOCIAL_TRACKING.test(key))) url.searchParams.delete(key);
  }
  if (platformOf(url.toString()) === 'youtube') {
    const id = youtubeId(url.toString());
    if (id) return `https://www.youtube.com/watch?v=${id}`;
  }
  return url.toString();
}

/** Instagram's og:description is "123 likes, 4 comments - chef on May 1, 2025: "caption"". Keep the caption. */
export function captionFromMeta(description) {
  const text = plain(description);
  const match = /^[\d.,\s]*[KMk]?\s*likes?,.*?:\s*["“](.*)["”]\s*\.?$/s.exec(text) || /^.*? on (?:Instagram|TikTok)\s*:\s*["“](.*)["”]\s*$/s.exec(text);
  return (match ? match[1] : text).trim();
}

/** Recipe website links inside a caption or description (never other social posts or link-in-bio pages). */
export function findLinks(text) {
  const links = [];
  for (const match of String(text).matchAll(/https?:\/\/[^\s<>"'()]+/gi)) {
    const candidate = match[0].replace(/[.,;:!?]+$/, '');
    try {
      const url = new URL(candidate);
      const host = url.hostname.toLowerCase();
      if (platformOf(candidate) !== 'web' || NOT_RECIPES.test(host)) continue;
      if (!links.includes(candidate)) links.push(candidate);
    } catch {
      // not a URL after all
    }
  }
  return links.slice(0, 3);
}
