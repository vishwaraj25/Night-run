// POST /api/events — anonymous telemetry ingestion for Night Run.
//
// This endpoint is public and unauthenticated, which means anyone who finds
// the URL can post to it. Everything below is written on that assumption:
// the goal is that the worst a hostile caller can achieve is inserting junk
// rows that look exactly like real ones, and that no request can cause
// personal data to be stored even if the client is modified to send it.
//
// The rules, in order of how much they matter:
//
// 1. STRICT ALLOW-LIST, keys and types. An event whose name isn't known is
//    rejected. A key that isn't in that event's schema is rejected -- not
//    stripped and stored, rejected -- so a tampered client cannot smuggle a
//    field into the payload. Strings are length-capped and, where the set is
//    known (item names, death reasons), checked against it.
//
// 2. NOTHING IDENTIFYING IS READ OFF THE REQUEST. No user agent, no IP, no
//    headers of any kind are stored. The only identifier is the anonymous id
//    the game generated on the device and put in the body.
//
// 3. CORS IS AN ALLOW-LIST, not "*". Only the origins the game is actually
//    served from can call this from a browser. "*" would let any page on the
//    internet post as your game.
//
// 4. RATE LIMITED per player id, in-process. Not bulletproof across many
//    serverless instances, but it stops a single client -- buggy or hostile --
//    from hammering the database, and it costs nothing.
//
// 5. NO REFLECTION IN ERRORS. Error responses are fixed strings. The earlier
//    draft echoed the rejected event name back to the caller, which is a
//    small reflection sink and tells an attacker what to try next.

const { getPool } = require("../db/client");

const MAX_EVENTS_PER_BATCH = 50;
const MAX_BODY_BYTES = 16_000;
const MAX_STRING_LEN = 64;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Origins allowed to call this from a browser. Set ALLOWED_ORIGINS in the
// environment as a comma-separated list once the game has a real home.
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

// A clock skew window. Events claiming to be from next year, or from 1970,
// are junk; accept a generous but bounded range around now.
const MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

// --- the allow-list -------------------------------------------------------
// For each event: every key it may carry, and what that key is allowed to be.
// "enum" is the tightest and is used wherever the set of values is finite.
const num = (min, max) => ({ type: "number", min, max });
const int = (min, max) => ({ type: "int", min, max });
const enumOf = (...values) => ({ type: "enum", values: new Set(values) });
const bool = () => ({ type: "bool" });

const EVENT_SCHEMA = {
  run_start: {},
  run_end: {
    reason: enumOf("defeated", "fell", "boss_defeated", "quit"),
    score: int(0, 10_000_000),
    duration_sec: num(0, 86_400),
    x: int(-1000, 40_000),
  },
  // The drop-off signal, sent every 2000px of progress and flushed at once.
  // People leave browser games by closing the tab, so the answer to "where do
  // they stop" has to already be here before they go.
  progress: { x: int(-1000, 40_000) },
  menu_click: {
    button: enumOf("play", "controls", "close_controls", "quit"),
  },
  item_collected: {
    item: enumOf(
      "machine_gun", "double_mg", "laser", "flamethrower", "medkit", "jetpack"
    ),
  },
  enemy_defeated: {
    enemy: enumOf("sentry_bot", "flyer_squadron", "trap_shooter", "mech_boss"),
    // World-space x in the level. This is a position in the GAME, not a
    // location in the world -- it is how you find out where people die.
    x: int(-1000, 40_000),
  },
  boss_defeated: { score: int(0, 10_000_000) },
  checkpoint_reached: { x: int(-1000, 40_000) },
  player_died: {
    reason: enumOf("defeated", "fell"),
    x: int(-1000, 40_000),
  },
  // Whether anyone actually uses the shield's deflect mechanic, and whether
  // they land the perfect-timing window it was tuned around. Fired every
  // time a hit is successfully blocked, not just when the shield is raised
  // -- raising it and never taking a hit tells you nothing about the timing.
  shield_deflect: { perfect: bool() },
  // The air jump specifically, not the ground jump -- ground jumping is core
  // movement and using it is a given. Whether people find and use the second
  // jump is not.
  double_jump: {},
};

module.exports = async function handler(req, res) {
  const origin = req.headers.origin;
  const allowed = ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin);

  if (origin && allowed) res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Max-Age", "86400");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  if (!allowed) return res.status(403).json({ error: "origin_not_allowed" });

  const body = await readBody(req);
  if (body === TOO_LARGE) return res.status(413).json({ error: "payload_too_large" });
  if (body === null) return res.status(400).json({ error: "invalid_json" });

  const batch = validateBatch(body);
  if (!batch.ok) return res.status(400).json({ error: batch.reason });

  if (isRateLimited(batch.playerId)) {
    return res.status(429).json({ error: "rate_limited" });
  }

  const pool = getPool();
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `INSERT INTO players (player_id) VALUES ($1)
       ON CONFLICT (player_id) DO UPDATE SET last_seen_at = now()`,
      [batch.playerId]
    );

    const values = [];
    const rows = batch.events.map((e, i) => {
      const b = i * 5;
      values.push(batch.playerId, batch.sessionId, e.name, JSON.stringify(e.payload), e.at);
      return `($${b + 1}, $${b + 2}, $${b + 3}, $${b + 4}, $${b + 5})`;
    });
    await client.query(
      `INSERT INTO events (player_id, session_id, event_name, payload, client_ts)
       VALUES ${rows.join(",")}`,
      values
    );
    await client.query("COMMIT");
    return res.status(200).json({ accepted: batch.events.length });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    // Logged server-side only. The response says nothing about what broke.
    console.error("events insert failed:", err.message);
    return res.status(500).json({ error: "internal_error" });
  } finally {
    client.release();
  }
};

// --- request reading ------------------------------------------------------

const TOO_LARGE = Symbol("too_large");

// Reads the body with a hard byte cap enforced DURING the read, so an
// attacker cannot make the process buffer a huge request before we notice.
async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body; // pre-parsed by the platform
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) return TOO_LARGE;
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    return null;
  }
}

// --- validation -----------------------------------------------------------

function validateBatch(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, reason: "invalid_body" };
  }
  if (typeof body.playerId !== "string" || !UUID_RE.test(body.playerId)) {
    return { ok: false, reason: "invalid_player_id" };
  }
  if (typeof body.sessionId !== "string" || !UUID_RE.test(body.sessionId)) {
    return { ok: false, reason: "invalid_session_id" };
  }
  if (!Array.isArray(body.events) || body.events.length === 0) {
    return { ok: false, reason: "missing_events" };
  }
  if (body.events.length > MAX_EVENTS_PER_BATCH) {
    return { ok: false, reason: "batch_too_large" };
  }

  const now = Date.now();
  const events = [];
  for (const e of body.events) {
    if (!e || typeof e !== "object") return { ok: false, reason: "invalid_event" };
    if (typeof e.name !== "string" || !Object.hasOwn(EVENT_SCHEMA, e.name)) {
      return { ok: false, reason: "unknown_event" };
    }
    if (typeof e.ts !== "number" || !Number.isFinite(e.ts)) {
      return { ok: false, reason: "invalid_ts" };
    }
    const atMs = e.ts * 1000;
    if (Math.abs(atMs - now) > MAX_CLOCK_SKEW_MS) {
      return { ok: false, reason: "ts_out_of_range" };
    }
    const payload = validatePayload(e.name, e.payload);
    if (payload === null) return { ok: false, reason: "invalid_payload" };
    events.push({ name: e.name, payload, at: new Date(atMs) });
  }
  return { ok: true, playerId: body.playerId, sessionId: body.sessionId, events };
}

// Returns a NEW object built only from allowed keys, or null to reject the
// whole batch. Building a fresh object rather than mutating the input is what
// guarantees nothing extra survives into the database -- there is no path by
// which an unexpected key reaches the INSERT.
function validatePayload(eventName, payload) {
  const schema = EVENT_SCHEMA[eventName];
  if (payload === undefined || payload === null) return {};
  if (typeof payload !== "object" || Array.isArray(payload)) return null;

  const keys = Object.keys(payload);
  if (keys.length > Object.keys(schema).length) return null;

  const out = {};
  for (const key of keys) {
    if (!Object.hasOwn(schema, key)) return null; // unknown key -> reject
    const rule = schema[key];
    const value = payload[key];
    switch (rule.type) {
      case "bool":
        if (typeof value !== "boolean") return null;
        out[key] = value;
        break;
      case "enum":
        if (typeof value !== "string" || value.length > MAX_STRING_LEN) return null;
        if (!rule.values.has(value)) return null;
        out[key] = value;
        break;
      case "int":
        if (typeof value !== "number" || !Number.isFinite(value)) return null;
        if (value < rule.min || value > rule.max) return null;
        out[key] = Math.trunc(value);
        break;
      case "number":
        if (typeof value !== "number" || !Number.isFinite(value)) return null;
        if (value < rule.min || value > rule.max) return null;
        out[key] = value;
        break;
      default:
        return null;
    }
  }
  return out;
}

// --- rate limiting --------------------------------------------------------
// Keyed on the player id from the body, never on IP -- an IP is personal data
// and this service makes a point of not touching it.

const RATE_WINDOW_MS = 60_000;
const RATE_MAX_REQUESTS = 30; // the game flushes every 8s, so this is ~8x headroom
const buckets = new Map();

function isRateLimited(playerId) {
  const now = Date.now();
  const bucket = buckets.get(playerId);
  if (!bucket || now - bucket.start > RATE_WINDOW_MS) {
    buckets.set(playerId, { start: now, count: 1 });
    if (buckets.size > 10_000) pruneBuckets(now);
    return false;
  }
  bucket.count += 1;
  return bucket.count > RATE_MAX_REQUESTS;
}

function pruneBuckets(now) {
  for (const [key, b] of buckets) {
    if (now - b.start > RATE_WINDOW_MS) buckets.delete(key);
  }
}

// exported for the test suite
module.exports.validateBatch = validateBatch;
module.exports.validatePayload = validatePayload;
module.exports.EVENT_SCHEMA = EVENT_SCHEMA;
