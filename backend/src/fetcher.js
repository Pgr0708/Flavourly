import dns from 'node:dns';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import zlib from 'node:zlib';
import { HttpError } from './util.js';

const V4_BLOCKS = [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8], ['169.254.0.0', 16], ['172.16.0.0', 12],
  ['192.0.0.0', 24], ['192.0.2.0', 24], ['192.88.99.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15],
  ['198.51.100.0', 24], ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
];
const v4ToInt = (ip) => ip.split('.').reduce((acc, part) => (acc << 8) + Number(part), 0) >>> 0;

/** True for loopback, private, link-local, CGNAT, multicast, documentation and other non-public addresses. */
export function isPrivateIP(address) {
  if (net.isIPv4(address)) {
    const value = v4ToInt(address);
    return V4_BLOCKS.some(([base, bits]) => (value >>> (32 - bits)) === (v4ToInt(base) >>> (32 - bits)));
  }
  if (!net.isIPv6(address)) return true;
  const ip = address.toLowerCase().replace(/^\[|\]$/g, '').split('%')[0];
  const mapped = ip.match(/^(?:0*:)*:?ffff:(\d+\.\d+\.\d+\.\d+)$/) || ip.match(/^64:ff9b::(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateIP(mapped[1]);
  if (ip === '::' || ip === '::1') return true;
  const first = parseInt(ip.split(':')[0] || '0', 16);
  return (first & 0xfe00) === 0xfc00 // fc00::/7 unique local
    || (first & 0xffc0) === 0xfe80 // fe80::/10 link local
    || (first & 0xff00) === 0xff00 // multicast
    || ip.startsWith('2001:db8') // documentation
    || ip.startsWith('::ffff:') // other mapped forms
    || first === 0;
}

/** Shape checks that need no DNS: scheme, credentials, port, obvious internal names and IP literals. */
const standardPort = (port) => port === '' || port === '80' || port === '443';

export function checkUrl(raw, isAllowed = (ip) => !isPrivateIP(ip), allowPort = standardPort) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new HttpError(400, "That link isn't valid.");
  }
  if (!['http:', 'https:'].includes(url.protocol)) throw new HttpError(400, 'Only http and https links can be imported.');
  if (url.username || url.password) throw new HttpError(400, "Links with a username or password can't be imported.");
  if (!allowPort(url.port)) throw new HttpError(400, "Links on unusual ports can't be imported.");
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (host === 'localhost' || /\.(localhost|local|internal|lan|home)$/.test(host)) throw new HttpError(400, "Links to private addresses can't be imported.");
  if (net.isIP(host) && !isAllowed(host)) throw new HttpError(400, "Links to private addresses can't be imported.");
  return url;
}

/**
 * DNS lookup that refuses private answers at connect time, so a hostname that changes its DNS
 * between our check and the request (DNS rebinding) still can't reach internal services.
 */
export function guardedLookup(isAllowed) {
  return (hostname, options, callback) => {
    dns.lookup(hostname, { ...options, all: true }, (error, addresses) => {
      if (error) return callback(error);
      const list = Array.isArray(addresses) ? addresses : [{ address: addresses, family: options.family || 4 }];
      if (list.length === 0 || list.some((entry) => !isAllowed(entry.address))) {
        return callback(Object.assign(new Error(`Blocked address for ${hostname}`), { code: 'EBLOCKED' }));
      }
      if (options.all) return callback(null, list);
      return callback(null, list[0].address, list[0].family);
    });
  };
}

function decode(buffer, contentType = '') {
  const charset = /charset=([\w-]+)/i.exec(contentType)?.[1]?.toLowerCase() ?? 'utf-8';
  try {
    return new TextDecoder(charset === 'iso-8859-1' ? 'latin1' : charset).decode(buffer);
  } catch {
    return new TextDecoder('utf-8').decode(buffer);
  }
}

function requestOnce(url, { lookup, userAgent, accept, timeoutMs, maxBytes }) {
  return new Promise((resolve, reject) => {
    const client = url.protocol === 'https:' ? https : http;
    const request = client.get(url, {
      lookup,
      timeout: timeoutMs,
      headers: {
        'User-Agent': userAgent,
        Accept: accept,
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'en;q=0.9, *;q=0.5',
      },
    }, (response) => {
      const status = response.statusCode ?? 0;
      if (status >= 300 && status < 400 && response.headers.location) {
        response.resume();
        return resolve({ redirect: new URL(response.headers.location, url) });
      }
      const encoding = String(response.headers['content-encoding'] || '').toLowerCase();
      let stream = response;
      if (encoding.includes('br')) stream = response.pipe(zlib.createBrotliDecompress());
      else if (encoding.includes('gzip')) stream = response.pipe(zlib.createGunzip());
      else if (encoding.includes('deflate')) stream = response.pipe(zlib.createInflate());
      const chunks = [];
      let size = 0;
      stream.on('data', (chunk) => {
        size += chunk.length;
        if (size > maxBytes) {
          request.destroy();
          stream.destroy();
          reject(new HttpError(422, 'That page is too large to read.'));
          return;
        }
        chunks.push(chunk);
      });
      stream.on('end', () => {
        const contentType = String(response.headers['content-type'] || '');
        resolve({ status, contentType, body: decode(Buffer.concat(chunks), contentType) });
      });
      stream.on('error', reject);
    });
    request.on('timeout', () => request.destroy(new HttpError(504, 'That site took too long to answer.')));
    request.on('error', (error) => {
      if (error instanceof HttpError) return reject(error);
      if (error.code === 'EBLOCKED') return reject(new HttpError(400, "Links to private addresses can't be imported."));
      return reject(new HttpError(502, "We couldn't reach that site."));
    });
  });
}

/**
 * Fetches a public page safely: http(s) only, public IPs only (re-checked on every redirect and at
 * connect time), size and time limits, gzip/brotli. `isAllowed` exists so tests can allow 127.0.0.1.
 */
export function createFetcher({ userAgent, timeoutMs = 10_000, maxBytes = 3_000_000, maxRedirects = 4, isAllowed = (ip) => !isPrivateIP(ip), allowPort = standardPort } = {}) {
  const lookup = guardedLookup(isAllowed);
  async function fetchPage(rawUrl, { accept = 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.5' } = {}) {
    let url = checkUrl(String(rawUrl), isAllowed, allowPort);
    for (let hop = 0; hop <= maxRedirects; hop += 1) {
      const result = await requestOnce(url, { lookup, userAgent, accept, timeoutMs, maxBytes });
      if (result.redirect) {
        url = checkUrl(result.redirect.toString(), isAllowed, allowPort);
        continue;
      }
      return { url: url.toString(), ...result };
    }
    throw new HttpError(422, 'That link redirects too many times.');
  }

  async function fetchJson(rawUrl) {
    const page = await fetchPage(rawUrl, { accept: 'application/json' });
    if (page.status >= 400) throw new HttpError(page.status === 404 ? 404 : 502, 'That post is private, deleted or unavailable.');
    try {
      return JSON.parse(page.body);
    } catch {
      throw new HttpError(502, 'The site sent something unexpected.');
    }
  }

  return { fetchPage, fetchJson };
}
