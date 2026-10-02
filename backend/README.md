# Flavourly API

Node.js (Express 5) + MySQL + Redis backend for the Flavourly iOS app.

- **No login.** Each install gets an anonymous device token (stored hashed). Recipes, plans and lists stay on the phone and in iCloud.
- **The OpenAI key lives only in `backend/.env`.** The app never sees it.
- **Imports are legitimate.** The API reads public captions and descriptions, linked recipe websites and text the user pastes or scans. It never downloads videos and never reads comments.
- **Everything is validated twice.** The app checks input first; the server cleans it (control characters, invisible characters, HTML tags) and validates every field again. Each problem comes back with a readable message.
- **Built to scale.** The API is stateless and runs as PM2 cluster workers. Sessions, caches, rate limits and free-plan counters are shared through Redis and MySQL, so you can add CPU cores or whole servers.

| Endpoint | What it does | Free plan |
|---|---|---|
| `POST /v1/devices` | Anonymous device token | 20 new sessions an hour per network |
| `POST /v1/imports` | Link → recipe (website card, caption, linked site) | 5 a week |
| `POST /v1/ai/extract` | Pasted text, OCR or transcript → recipe | 20 a day |
| `POST /v1/ai/substitutes` | Allergy-safe ingredient swaps | 10 a week |
| `POST /v1/ai/cook-now` | 3 ideas from time, craving and pantry | 5 a week |
| `POST /v1/ai/plan` | Picks the week from a rule-safe shortlist | 1 a week |
| `POST /v1/discover` | Popular home dishes for a country (+ local staples and cravings), shared by all users | free |
| `POST /v1/nutrition` | Verified nutrition for ingredient lines (USDA, then Spoonacular) | free |
| `POST /v1/usage` | This device's free-plan counters, so the app shows the server's numbers | — |
| `POST /v1/images/recipe` | Optional AI recipe photo | 3 a week |
| `POST /v1/devices/erase` | Deletes this device's server data | — |
| `GET /healthz`, `GET /readyz` | Liveness, and readiness for DB, Redis and AI | — |

Premium users, verified with RevenueCat, have no limits. Failed requests never use up a free credit.

**Verified nutrition.** Every imported, scanned, AI-suggested and local recipe gets its nutrition calculated from **USDA FoodData Central** (public-domain data): each ingredient line is parsed ("1 1/2 cups flour"), converted to grams with USDA's own household portions (a cup of rice, a medium egg), and summed per serving. Lines USDA can't match go to **Spoonacular** when `SPOONACULAR_API_KEY` is set. If under 60% of lines can be verified, the AI estimate is kept and labelled "AI estimate" in the app. Every food is cached in Redis for 30 days, so each one is looked up once for all users.

**Local food.** `/v1/discover` asks gpt-4o-mini once per country for ~21 well-known home dishes (breakfast, mains, regional specialities, street food, sweets), then caches them in Redis for 30 days for every user. With `IMAGE_GENERATION=1` the server also paints one photo per dish in the background (about $0.01–0.04 each with gpt-image-1, once per dish, then served from `public/images`). Set `IMAGE_GENERATION=1` in `.env` if you want the photo cards; without it the app shows illustrated covers.

---

## Deploy on the Hostinger VPS (your other sites keep running)

Every step only *adds* things for Flavourly:

- a new folder (`/var/www/flavourly-api`)
- a new MySQL database and user
- a new PM2 app (`flavourly-api`)
- new Nginx blocks that answer only for `flavourly.dakshyaminfotech.store`

Nginx is **reloaded** (`systemctl reload`), never restarted, and only after `nginx -t` passes, so live sites keep serving traffic.

### 0. Look before changing anything (read-only)

```bash
node -v
pm2 -v
pm2 ls
sudo ss -ltnp | grep ':4815 ' || echo "port 4815 is free"
redis-cli ping
mysql --version
ls -l /etc/nginx/sites-enabled/ | grep centillion
```

- **Node** must be 18.18 or newer (20 or 22 recommended).
- **`pm2 ls`** shows your existing apps. Nothing below touches them.
- **Port 4815** must be free. If it isn't, pick another port and use it in both `.env` and the Nginx upstream.
- **`redis-cli ping`** answering `PONG` means Redis is already installed.
- **`centillion`** must appear in `sites-enabled`, which confirms that file is live.

### 1. Upload the code

From your Mac, in the project folder:

```bash
rsync -av --exclude node_modules --exclude .env --exclude logs --exclude public/images backend/ USER@YOUR_SERVER_IP:/var/www/flavourly-api/
```

Or use `git clone` / `git pull` into `/var/www/flavourly-api` on the server.

### 2. Install dependencies (this folder only)

```bash
cd /var/www/flavourly-api
npm ci --omit=dev
mkdir -p logs public/images
```

### 3. Database: a new database and user, nothing else touched

First set a strong password in the file. It must be the same as `DB_PASSWORD` in `.env`.

```bash
nano deploy/setup-mysql.sql
mysql -u root -p < deploy/setup-mysql.sql
```

### 4. Configure

```bash
cp .env.example .env
nano .env
chmod 600 .env
npm run migrate
```

In `.env`, set at least `OPENAI_API_KEY`, `DB_PASSWORD`, `PORT` and `REDIS_URL`. `npm run migrate` should print `Database is up to date.`

### 5. Redis (skip if `redis-cli ping` already said PONG)

```bash
sudo apt-get update && sudo apt-get install -y redis-server
sudo systemctl enable --now redis-server
redis-cli ping
```

Redis listens on 127.0.0.1 only. Every Flavourly key starts with `flavourly:`, so a Redis server shared with other apps is safe. Never run `FLUSHALL` or `FLUSHDB` on a shared Redis.

### 6. Start with PM2

This starts only this app, as a cluster of 2 workers:

```bash
cd /var/www/flavourly-api
pm2 start ecosystem.config.cjs --env production
pm2 save
curl -s http://127.0.0.1:4815/healthz
curl -s http://127.0.0.1:4815/readyz
```

- `pm2 save` adds `flavourly-api` to PM2's saved list, which already includes your other apps.
- `/healthz` should return `{"ok":true}`.
- `/readyz` should return `{"database":"ok","redis":"ok","cache":"redis","ai":"configured"}`.

If PM2 was never set to start on boot, run `pm2 startup` once and run the command it prints. If your other apps already come back after a reboot, this is done and you can skip it.

### 7. DNS

In Hostinger hPanel, open **DNS Zone** for `dakshyaminfotech.store` and add an **A record**:

- Name: `flavourly`
- Points to: your VPS IP

Check it from the server:

```bash
dig +short flavourly.dakshyaminfotech.store
```

### 8. Nginx step 1: HTTP, so Let's Encrypt can issue the certificate

This backs up `centillion`, then appends the HTTP block to it:

```bash
cd /var/www/flavourly-api
sudo cp /etc/nginx/sites-available/centillion /etc/nginx/sites-available/centillion.bak-$(date +%F-%H%M)
sudo mkdir -p /var/www/flavourly-acme
sudo tee -a /etc/nginx/sites-available/centillion < deploy/nginx-step1-http.conf > /dev/null
sudo nginx -t && sudo systemctl reload nginx
```

### 9. Certificate

`certonly` only creates the certificate. It doesn't edit any Nginx file. Renewal uses the same webroot automatically through the existing certbot timer.

```bash
sudo certbot certonly --webroot -w /var/www/flavourly-acme -d flavourly.dakshyaminfotech.store
```

If certbot isn't installed yet:

```bash
sudo apt-get install -y certbot
```

### 10. Nginx step 2: HTTPS reverse proxy to PM2

```bash
sudo tee -a /etc/nginx/sites-available/centillion < deploy/nginx-step2-https.conf > /dev/null
sudo nginx -t && sudo systemctl reload nginx
curl -s https://flavourly.dakshyaminfotech.store/healthz
```

**If `nginx -t` ever fails**, nothing was reloaded and your sites are still running. Restore the backup (pick the newest file from `ls /etc/nginx/sites-available/centillion.bak-*`) and test again:

```bash
sudo cp /etc/nginx/sites-available/centillion.bak-YYYY-MM-DD-HHMM /etc/nginx/sites-available/centillion
sudo nginx -t && sudo systemctl reload nginx
```

The release build of the iOS app already points to `https://flavourly.dakshyaminfotech.store` (`Flavourly/Apis.swift`).

### Updating later (zero downtime, only this app)

```bash
cd /var/www/flavourly-api
git pull                     # or rsync again from your Mac
npm ci --omit=dev
npm run migrate
pm2 reload flavourly-api     # rolling reload: each worker restarts only after the new one is ready
```

### Day-to-day

```bash
pm2 logs flavourly-api --lines 100
pm2 monit
sudo tail -f /var/log/nginx/flavourly.error.log
```

**Commands that would affect your other apps** — don't run these:

- `pm2 kill`
- `pm2 delete all`
- `pm2 restart all`
- `pm2 update`
- `sudo systemctl restart nginx` (use `reload`)
- `redis-cli FLUSHALL`

---

## Scaling

**Vertical (one bigger server)**

- `pm2 scale flavourly-api 4` gives one worker per CPU core you want to spare. Only this app changes.
- Raise `DB_POOL_SIZE` only while `DB_POOL_SIZE × workers` stays well under MySQL's `max_connections`, which is shared with your other sites. Check it with:

  ```bash
  mysql -u root -p -e "SHOW VARIABLES LIKE 'max_connections'; SHOW STATUS LIKE 'Threads_connected';"
  ```

- `max_memory_restart` (400 MB) in `ecosystem.config.cjs` recycles a worker that leaks memory.

**Horizontal (more servers)**

The API keeps no state in memory that matters. Tokens, caches, rate limits and free-plan counters live in MySQL and Redis, which the test suite checks with two instances. To add a server:

1. Copy the folder and `.env`. Point `DB_HOST` and `REDIS_URL` at the primary server's **private** IP, and let only the new server reach MySQL (3306) and Redis (6379) through the firewall.
2. On the new server, set `HOST` to its private IP, and set `TRUST_PROXY` to the Nginx server's IP.
3. Add `server NEW_PRIVATE_IP:4815;` to `upstream flavourly_api_upstream`, then run `sudo nginx -t && sudo systemctl reload nginx`.
4. For AI photos, serve `public/images` from shared storage or keep `IMAGE_GENERATION=0`.

---

## Tests

The tests run against a real MySQL. Point `TEST_DB_*` at a server where the user can create and drop databases. The default is `root@127.0.0.1:3307` with no password, which is a throwaway instance. Each run creates and drops its own `flavourly_test_*` databases.

```bash
npm install          # includes redis-memory-server, which builds a test Redis inside node_modules
npm test
```

The tests cover:

- input cleaning and validation on every endpoint
- the SSRF guard (private IPs, redirects to cloud metadata, DNS rebinding, size and time limits)
- JSON-LD and social caption parsing
- the import pipeline: website card → caption → creator's site, plus caching
- AI outages, retries, timeouts and refusals
- free limits, Premium and weekly reset
- rate limits, erase and images
- two instances sharing MySQL and Redis

To run the API locally without an OpenAI key, start the fake OpenAI in one terminal:

```bash
npm run fake-openai
```

Then, with a local MySQL, start the API in another:

```bash
OPENAI_BASE_URL=http://127.0.0.1:9911/v1 OPENAI_API_KEY=local-dev-key npm run dev
```
