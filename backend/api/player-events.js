// GET /api/player-events?key=...&player_id=... — one player's full event
// timeline, for the dashboard's player-wise view.
//
// Same auth model as stats.js: a single shared DASHBOARD_KEY checked against
// a query param, fails closed if unset. See stats.js for the reasoning.
//
// player_id is validated as a UUID before it goes anywhere near SQL, and
// even so it is only ever passed as a bound parameter ($1), never
// interpolated into the query string -- so a malformed or hostile value is
// either rejected outright or simply matches nothing.

const { getPool } = require("../db/client");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_EVENTS = 2000;

module.exports = async function handler(req, res) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "GET") return res.status(405).json({ error: "method_not_allowed" });

  const key = process.env.DASHBOARD_KEY;
  if (!key) return res.status(503).json({ error: "dashboard_not_configured" });

  const url = new URL(req.url, "http://localhost");
  if (url.searchParams.get("key") !== key) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const playerId = url.searchParams.get("player_id") || "";
  if (!UUID_RE.test(playerId)) {
    return res.status(400).json({ error: "invalid_player_id" });
  }

  const pool = getPool();
  try {
    const [player, events] = await Promise.all([
      pool.query(
        `SELECT player_id, first_seen_at, last_seen_at FROM players WHERE player_id = $1`,
        [playerId]
      ),
      pool.query(
        `SELECT session_id, event_name, payload, client_ts, server_ts
         FROM events WHERE player_id = $1
         ORDER BY client_ts ASC
         LIMIT $2`,
        [playerId, MAX_EVENTS]
      ),
    ]);

    if (player.rows.length === 0) {
      return res.status(404).json({ error: "player_not_found" });
    }

    return res.status(200).json({
      player: player.rows[0],
      events: events.rows,
    });
  } catch (err) {
    console.error("player-events query failed:", err.message);
    return res.status(500).json({ error: "internal_error" });
  }
};
