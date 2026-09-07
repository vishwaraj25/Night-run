# Hosting Night Run

Two independent pieces. **The game works with neither** — telemetry is off by
default, so you can ship the game today and add the backend whenever.

```
build/web/     the game, static files, ~51 MB   -> any static host
backend/       the telemetry API + Postgres      -> optional
```

## 1. The game (do this first)

The build is already made and verified — it runs, and I played it in a browser
from `build/web/`. Any static host works. Easiest first:

**itch.io** — the standard for browser games, and free.
1. `cd build/web && zip -r ../night-run-web.zip .`
2. New project → Kind: **HTML**, upload the zip, tick *This file will be played
   in the browser*.
3. Set the viewport to **960 × 540**, tick fullscreen.

**Cloudflare Pages / Netlify** — free, HTTPS, and they read `build/web/_headers`
so the security headers apply automatically. Drag the `build/web` folder into
Netlify Drop, or point Pages at the repo with build output `build/web`.

**GitHub Pages** works, but *cannot set headers* — the CSP and Permissions-Policy
in `_headers` are silently ignored. Fine for a demo among friends; use one of
the above if you're sharing the link widely.

Serve it locally to check anything:

```bash
cd build/web && python3 -m http.server 8777   # then open localhost:8777

Before uploading anywhere, make sure the security headers file is in place:

```bash
cp deploy/_headers build/web/_headers
```
```

### Why the web build is the one to share

Sandboxed by the browser, no install, no permissions, and `_headers` denies
camera/mic/location/USB outright. See PRIVACY.md.

The APK (`build/night-run.apk`) is signed with a **debug key** — fine to
sideload to people you know, but Android warns on install and it is not fit for
a store listing without a real upload key.

## 2. The telemetry backend (optional)

### Database

Any managed Postgres. Neon and Supabase both have a free tier that is far more
than this needs.

```bash
psql "$DATABASE_URL" -f backend/db/schema.sql
```

### API

Runs either as a serverless function or as a plain process — same file.

**Vercel:** point it at `backend/`. `api/events.js` becomes `/api/events`
automatically and `vercel.json` supplies the security headers.

**Render / Fly / Railway / a VPS:**

```bash
cd backend && npm ci && npm start     # server.js, listens on $PORT
```

Environment:

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Postgres connection string. TLS is verified — see below |
| `ALLOWED_ORIGINS` | yes | Comma-separated. The exact origin(s) the game is served from, e.g. `https://yourname.itch.io`. **Leave it unset and every origin is allowed** — fine locally, wrong in production |
| `PGSSLROOTCERT` | only if needed | Path to a CA file, if your provider uses a private CA. This exists so you never have to disable certificate verification |

Check it:

```bash
curl -s https://your-api/healthz            # {"ok":true}
cd backend && npm test                      # 14 tests, the privacy ones included
```

### Connecting the game to it

Three edits, in this order:

1. `game/autoload/telemetry.gd` → set `ENDPOINT_URL` to your `/api/events` URL.
2. Same file → `enabled` to `true`.
3. `build/web/_headers` → add the API origin to `connect-src`:
   `connect-src 'self' https://your-api;`
   The CSP blocks it otherwise, which is the point: the game can only talk to
   origins you have listed.

Then rebuild and redeploy:

```bash
godot --headless \
  --path game --export-release "Web" ../build/web/index.html
```

Note the Android preset has `permissions/internet=false`. If you want telemetry
from the APK too, that has to become `true` — and then the app does request
internet access, which is worth being deliberate about.

## Checking it worked

```sql
SELECT event_name, COUNT(*) FROM events GROUP BY 1 ORDER BY 2 DESC;
SELECT COUNT(DISTINCT player_id) FROM events;
-- where people give up:
SELECT (payload->>'x')::int / 1000 * 1000 AS zone, COUNT(*)
FROM events WHERE event_name = 'run_end' GROUP BY zone ORDER BY zone;
```

## What I could not verify

I built and played the web export, and the backend's validation layer is
tested. But I have no database and no host, so **the API has never run against
a real Postgres** and the schema has never been applied. The first `psql -f`
and the first `curl` are the real test.
