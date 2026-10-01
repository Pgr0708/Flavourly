import assert from 'node:assert/strict';
import http from 'node:http';
import zlib from 'node:zlib';
import { after, before, describe, it } from 'node:test';
import { createFetcher, guardedLookup, isPrivateIP } from '../src/fetcher.js';

// A local site; the fetcher is told 127.0.0.1 is "public" so it can reach it, while every other
// private address (169.254.169.254 metadata, 10.x, localhost names…) stays blocked.
let server;
let base;
before(async () => {
  server = http.createServer((req, res) => {
    const send = (status, body, headers = {}) => {
      res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', ...headers });
      res.end(body);
    };
    switch (req.url) {
      case '/gzip':
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Encoding': 'gzip' });
        return res.end(zlib.gzipSync('<h1>Gzipped dal</h1>'));
      case '/brotli':
        res.writeHead(200, { 'Content-Type': 'text/html', 'Content-Encoding': 'br' });
        return res.end(zlib.brotliCompressSync('<h1>Brotli dal</h1>'));
      case '/latin1':
        res.writeHead(200, { 'Content-Type': 'text/html; charset=iso-8859-1' });
        return res.end(Buffer.from([0x63, 0x72, 0xe8, 0x6d, 0x65])); // "crème"
      case '/redirect':
        return send(302, '', { Location: '/gzip' });
      case '/redirect-metadata':
        return send(302, '', { Location: 'http://169.254.169.254/latest/meta-data/' });
      case '/redirect-localhost':
        return send(301, '', { Location: 'http://localhost:9/' });
      case '/redirect-loop':
        return send(302, '', { Location: '/redirect-loop' });
      case '/big':
        return send(200, 'x'.repeat(200_000));
      case '/slow':
        return setTimeout(() => send(200, 'late'), 1_500);
      case '/json':
        return send(200, '{"title":"hello"}', { 'Content-Type': 'application/json' });
      case '/404':
        return send(404, 'nope');
      default:
        return send(200, `<p>${req.headers['user-agent']}</p>`);
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => new Promise((resolve) => {
  server.closeAllConnections?.();
  server.close(resolve);
}));

const fetcher = (options = {}) => createFetcher({
  userAgent: 'FlavourlyTest/1', isAllowed: (ip) => ip === '127.0.0.1', allowPort: () => true, timeoutMs: 800, maxBytes: 100_000, maxRedirects: 3, ...options,
});

describe('safe fetcher', () => {
  it('decodes gzip, brotli and latin-1 and sends our user agent', async () => {
    assert.match((await fetcher().fetchPage(`${base}/gzip`)).body, /Gzipped dal/);
    assert.match((await fetcher().fetchPage(`${base}/brotli`)).body, /Brotli dal/);
    assert.equal((await fetcher().fetchPage(`${base}/latin1`)).body, 'crème');
    assert.match((await fetcher().fetchPage(`${base}/ua`)).body, /FlavourlyTest\/1/);
  });
  it('follows normal redirects and reports the final URL', async () => {
    const page = await fetcher().fetchPage(`${base}/redirect`);
    assert.equal(page.url, `${base}/gzip`);
    assert.match(page.body, /Gzipped/);
  });
  it('refuses redirects to cloud metadata or localhost', async () => {
    await assert.rejects(fetcher().fetchPage(`${base}/redirect-metadata`), /private addresses/);
    await assert.rejects(fetcher().fetchPage(`${base}/redirect-localhost`), /private addresses/);
  });
  it('stops redirect loops, oversized pages and slow sites', async () => {
    await assert.rejects(fetcher().fetchPage(`${base}/redirect-loop`), /redirects too many times/);
    await assert.rejects(fetcher().fetchPage(`${base}/big`), /too large/);
    await assert.rejects(fetcher().fetchPage(`${base}/slow`), /too long/);
  });
  it('blocks private IPs by default — even when a hostname resolves to one (DNS rebinding)', async () => {
    const strict = createFetcher({ userAgent: 'x', timeoutMs: 800, allowPort: () => true });
    await assert.rejects(strict.fetchPage(`${base}/gzip`), /private addresses/);
    // The connect-time lookup re-checks every answer: a public-looking name that resolves to
    // 127.0.0.1 ("localhost" stands in for a rebinding domain here, resolved from /etc/hosts) is refused.
    const lookup = guardedLookup((ip) => !isPrivateIP(ip));
    const error = await new Promise((resolve) => lookup('localhost', { all: true }, (e) => resolve(e)));
    assert.equal(error?.code, 'EBLOCKED');
    const allowed = await new Promise((resolve) => guardedLookup(() => true)('localhost', {}, (e, address) => resolve(e ?? address)));
    assert.match(String(allowed), /127\.0\.0\.1|::1/);
  });
  it('parses JSON and maps HTTP errors', async () => {
    assert.deepEqual(await fetcher().fetchJson(`${base}/json`), { title: 'hello' });
    await assert.rejects(fetcher().fetchJson(`${base}/404`), /private, deleted or unavailable/);
  });
});
