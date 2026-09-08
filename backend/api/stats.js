// GET /api/stats — read-only aggregates for the dashboard.
//
// Separate from events.js on purpose: that endpoint is public and write-only
// (anyone can post an event), this one is read-only and gated behind a
// secret. Mixing them would mean either exposing aggregate data publicly or
// putting auth checks inside the hot ingestion path. Two small files, two
// clear responsibilities.
//
// AUTH: a single shared secret, DASHBOARD_KEY, checked against a query
// param. This is a solo-dev telemetry viewer, not a multi-user product --
// a bearer token in the URL is fine for that and needs no session storage,
// no login page, no extra dependency. It is never logged (see the CORS/log
// note below) and the key itself lives only in Vercel's env vars, same as
// DATABASE_URL.
//
// Every query below is fixed SQL with no string interpolation of request
// data, so there is no injection surface regardless of the auth outcome.

const { getPool } = require("../db/client");

module.exports = async function handler(req, res) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  // Never let a browser or proxy cache a response gated by a secret in the URL.
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "GET") return res.status(405).json({ error: "method_not_allowed" });

  const key = process.env.DASHBOARD_KEY;
  if (!key) return res.status(503).json({ error: "dashboard_not_configured" });

  const url = new URL(req.url, "http://localhost");
  if (url.searchParams.get("key") !== key) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const pool = getPool();
  try {
    const [totals, byEvent, dropoff, weapons, deaths, runEnds, daily] = await Promise.all([
      pool.query(`
        SELECT
          (SELECT COUNT(*) FROM players) AS player_count,
          (SELECT COUNT(*) FROM events) AS event_count,
          (SELECT COUNT(*) FROM players WHERE last_seen_at > now() - INTERVAL '24 hours') AS active_24h
      `),
      pool.query(`
        SELECT event_name, COUNT(*) AS n
        FROM events GROUP BY event_name ORDER BY n DESC
      `),
      pool.query(`
        SELECT ((payload->>'x')::int / 1000) * 1000 AS zone, COUNT(*) AS n
        FROM events
        WHERE event_name = 'player_died' AND payload ? 'x'
        GROUP BY zone ORDER BY zone
      `),
      pool.query(`
        SELECT payload->>'item' AS item, COUNT(*) AS n
        FROM events WHERE event_name = 'item_collected'
        GROUP BY 1 ORDER BY n DESC
      `),
      pool.query(`
        SELECT payload->>'reason' AS reason, COUNT(*) AS n
        FROM events WHERE event_name = 'player_died'
        GROUP BY 1 ORDER BY n DESC
      `),
      pool.query(`
        SELECT payload->>'reason' AS reason, COUNT(*) AS n,
               AVG((payload->>'duration_sec')::float) AS avg_duration,
               AVG((payload->>'score')::float) AS avg_score
        FROM events WHERE event_name = 'run_end'
        GROUP BY 1 ORDER BY n DESC
      `),
      pool.query(`
        SELECT date_trunc('day', server_ts) AS day, COUNT(DISTINCT player_id) AS players, COUNT(*) AS events
        FROM events
        WHERE server_ts > now() - INTERVAL '14 days'
        GROUP BY 1 ORDER BY 1 ASC
      `),
    ]);

    return res.status(200).json({
      totals: totals.rows[0],
      by_event: byEvent.rows,
      dropoff_by_zone: dropoff.rows,
      items_collected: weapons.rows,
      death_reasons: deaths.rows,
      run_ends: runEnds.rows,
      daily_last_14d: daily.rows,
    });
  } catch (err) {
    console.error("stats query failed:", err.message);
    return res.status(500).json({ error: "internal_error" });
  }
};
