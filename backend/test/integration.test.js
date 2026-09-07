// End-to-end over real HTTP, with the database stubbed.
//
// The unit tests check the validator in isolation. This drives the actual
// server the way a browser does -- real sockets, real headers, real JSON --
// and then asserts on THE EXACT VALUES THAT WOULD REACH POSTGRES. That last
// part is the one that matters: it is the difference between "the validator
// returns null for an email field" and "an email field cannot end up in the
// database", which is the claim PRIVACY.md actually makes.
//
// Postgres itself is stubbed because there is none on this machine. What is
// NOT stubbed: routing, CORS, the body cap, validation, rate limiting, and
// the SQL text and parameters.

const { test, before, after } = require("node:test");
const assert = require("node:assert");
const http = require("node:http");
const path = require("node:path");

// Swap in a fake pool before events.js is loaded, by pre-seeding the module
// cache for db/client.js.
const clientPath = require.resolve("../db/client.js");
const captured = [];
require.cache[clientPath] = {
  id: clientPath,
  filename: clientPath,
  loaded: true,
  exports: {
    getPool: () => ({
      connect: async () => ({
        query: async (sql, params) => {
          captured.push({ sql, params });
          return { rows: [] };
        },
        release: () => {},
      }),
    }),
  },
};

process.env.ALLOWED_ORIGINS = "https://night-run.example";
const handler = require("../api/events.js");

let server, base;

before(async () => {
  server = http.createServer(async (req, res) => {
    res.status = (c) => { res.statusCode = c; return res; };
    res.json = (o) => { res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(o)); return res; };
    if (new URL(req.url, "http://x").pathname !== "/api/events") return res.status(404).json({});
    try { await handler(req, res); }
    catch (e) { if (!res.headersSent) res.status(500).json({ error: "internal_error" }); }
  });
  await new Promise((r) => server.listen(0, r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const ORIGIN = "https://night-run.example";
const PLAYER = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const SESSION = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d";
const now = () => Date.now() / 1000;

async function post(body, { origin = ORIGIN, raw = null, id = PLAYER } = {}) {
  const payload = raw ?? JSON.stringify({ playerId: id, sessionId: SESSION, ...body });
  const res = await fetch(`${base}/api/events`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: origin },
    body: payload,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json, headers: res.headers };
}

test("a normal batch is accepted", async () => {
  captured.length = 0;
  const r = await post({ events: [
    { name: "run_start", ts: now(), payload: {} },
    { name: "progress", ts: now(), payload: { x: 14000 } },
    { name: "run_end", ts: now(), payload: { reason: "fell", score: 90, duration_sec: 41.2, x: 15990 } },
  ]});
  assert.equal(r.status, 200);
  assert.equal(r.json.accepted, 3);
});

test("what reaches Postgres is the id and allow-listed keys, nothing else", async () => {
  captured.length = 0;
  await post({ events: [{ name: "item_collected", ts: now(), payload: { item: "laser" } }] });

  const insert = captured.find((c) => c.sql.includes("INSERT INTO events"));
  assert.ok(insert, "an events INSERT should have been issued");

  // The parameters are the only thing that reaches the database.
  const flat = JSON.stringify(insert.params);
  for (const forbidden of ["Mozilla", "127.0.0.1", "user-agent", "@", "origin"]) {
    assert.ok(!flat.toLowerCase().includes(forbidden.toLowerCase()),
      `parameters must not contain ${forbidden}: ${flat}`);
  }
  // ...and the payload column is exactly what was allowed.
  assert.equal(insert.params[3], JSON.stringify({ item: "laser" }));

  // Parameterised, not interpolated: no player-controlled text in the SQL.
  assert.ok(!insert.sql.includes("laser"));
  assert.ok(insert.sql.includes("$1"));
});

test("a tampered client cannot smuggle a field into the database", async () => {
  captured.length = 0;
  const r = await post({ events: [{
    name: "item_collected", ts: now(),
    payload: { item: "laser", email: "someone@example.com", ip: "8.8.8.8" },
  }]});
  assert.equal(r.status, 400);
  assert.equal(captured.length, 0, "nothing should have been written at all");
});

test("SQL injection in the ids is rejected before any query runs", async () => {
  captured.length = 0;
  const r = await post({ events: [{ name: "run_start", ts: now() }] },
    { id: "'; DROP TABLE events;--" });
  assert.equal(r.status, 400);
  assert.equal(r.json.error, "invalid_player_id");
  assert.equal(captured.length, 0);
});

test("another site cannot post as the game", async () => {
  const r = await post({ events: [{ name: "run_start", ts: now() }] },
    { origin: "https://evil.example" });
  assert.equal(r.status, 403);
  assert.equal(r.headers.get("access-control-allow-origin"), null);
});

test("the allowed origin is echoed back, and only that origin", async () => {
  const r = await post({ events: [{ name: "run_start", ts: now() }] });
  assert.equal(r.headers.get("access-control-allow-origin"), ORIGIN);
  assert.notEqual(r.headers.get("access-control-allow-origin"), "*");
});

test("oversized bodies are refused", async () => {
  const huge = JSON.stringify({
    playerId: PLAYER, sessionId: SESSION,
    events: [{ name: "run_start", ts: now(), payload: { item: "x".repeat(60_000) } }],
  });
  const r = await post({}, { raw: huge });
  assert.equal(r.status, 413);
});

test("error responses never echo the request back", async () => {
  const r = await post({ events: [{ name: "<img src=x onerror=alert(1)>", ts: now() }] });
  assert.equal(r.status, 400);
  assert.ok(!JSON.stringify(r.json).includes("<img"), "response reflected input");
});

test("a flood from one player is rate limited", async () => {
  const flood = "b7e2c1a0-1111-4222-8333-444455556666";
  let limited = false;
  for (let i = 0; i < 40; i++) {
    const r = await post({ events: [{ name: "run_start", ts: now() }] }, { id: flood });
    if (r.status === 429) { limited = true; break; }
  }
  assert.ok(limited, "should have been rate limited within 40 requests");
});

test("security headers are present on every response", async () => {
  const r = await post({ events: [{ name: "run_start", ts: now() }] });
  assert.equal(r.headers.get("x-content-type-options"), "nosniff");
  assert.equal(r.headers.get("referrer-policy"), "no-referrer");
});
