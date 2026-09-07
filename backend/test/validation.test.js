// Tests for the validation layer, which is the part that actually enforces
// the privacy promise: if this is right, no request can cause anything other
// than an anonymous id and an allow-listed event to be stored.

const { test } = require("node:test");
const assert = require("node:assert");
const { validateBatch, validatePayload } = require("../api/events.js");

const PLAYER = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const SESSION = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d";
const now = () => Date.now() / 1000;

const batch = (events, over = {}) => ({
  playerId: PLAYER, sessionId: SESSION, events, ...over,
});

test("accepts a well-formed batch", () => {
  const r = validateBatch(batch([
    { name: "run_start", ts: now(), payload: {} },
    { name: "item_collected", ts: now(), payload: { item: "laser" } },
  ]));
  assert.equal(r.ok, true);
  assert.equal(r.events.length, 2);
});

test("rejects an unknown event name", () => {
  const r = validateBatch(batch([{ name: "drop_table", ts: now(), payload: {} }]));
  assert.equal(r.ok, false);
  assert.equal(r.reason, "unknown_event");
});

test("error text never echoes what the caller sent", () => {
  const r = validateBatch(batch([{ name: "<script>x</script>", ts: now() }]));
  assert.equal(r.ok, false);
  assert.ok(!r.reason.includes("script"), "reason must not reflect input");
});

// --- the privacy tests ----------------------------------------------------

test("an unknown payload key is REJECTED, not silently stored", () => {
  assert.equal(validatePayload("item_collected", { item: "laser", email: "a@b.c" }), null);
});

test("identifying fields cannot be smuggled in under any event", () => {
  for (const sneaky of [
    { ip: "8.8.8.8" }, { user_agent: "Mozilla/5.0" }, { name: "Yuvraj" },
    { email: "a@b.c" }, { lat: 51.5 }, { device_id: "abc" },
  ]) {
    for (const event of ["run_start", "run_end", "item_collected", "player_died"]) {
      assert.equal(validatePayload(event, sneaky), null,
        `${event} accepted ${JSON.stringify(sneaky)}`);
    }
  }
});

test("payload comes back as a fresh object, not the caller's", () => {
  const input = { item: "medkit" };
  const out = validatePayload("item_collected", input);
  assert.notStrictEqual(out, input);
  assert.deepEqual(out, { item: "medkit" });
});

test("prototype pollution attempts are rejected", () => {
  const evil = JSON.parse('{"__proto__": {"polluted": true}, "item": "laser"}');
  assert.equal(validatePayload("item_collected", evil), null);
  assert.equal({}.polluted, undefined);
});

test("enum values outside the known set are rejected", () => {
  assert.equal(validatePayload("item_collected", { item: "rocket_launcher" }), null);
  assert.equal(validatePayload("run_end", { reason: "hacked" }), null);
});

test("numbers outside their range are rejected", () => {
  assert.equal(validatePayload("run_end", { score: -1 }), null);
  assert.equal(validatePayload("run_end", { score: 1e12 }), null);
  assert.equal(validatePayload("checkpoint_reached", { x: 999999 }), null);
  assert.equal(validatePayload("run_end", { duration_sec: Infinity }), null);
});

test("wrong types are rejected", () => {
  assert.equal(validatePayload("run_end", { score: "100" }), null);
  assert.equal(validatePayload("item_collected", { item: 42 }), null);
  assert.equal(validatePayload("item_collected", ["laser"]), null);
});

// --- identifier and shape tests -------------------------------------------

test("player and session ids must be real UUIDv4", () => {
  for (const bad of ["", "abc", "../../etc/passwd", "'; DROP TABLE events;--",
                     "00000000-0000-0000-0000-000000000000"]) {
    assert.equal(validateBatch(batch([{ name: "run_start", ts: now() }], { playerId: bad })).ok,
      false, `accepted playerId ${bad}`);
    assert.equal(validateBatch(batch([{ name: "run_start", ts: now() }], { sessionId: bad })).ok,
      false, `accepted sessionId ${bad}`);
  }
});

test("oversized batches are rejected", () => {
  const many = Array.from({ length: 51 }, () => ({ name: "run_start", ts: now() }));
  assert.equal(validateBatch(batch(many)).reason, "batch_too_large");
});

test("timestamps far from now are rejected", () => {
  assert.equal(validateBatch(batch([{ name: "run_start", ts: 0 }])).reason, "ts_out_of_range");
  assert.equal(validateBatch(batch([{ name: "run_start", ts: now() + 1e7 }])).reason,
    "ts_out_of_range");
});

test("a missing payload is treated as empty, not as a failure", () => {
  const r = validateBatch(batch([{ name: "run_start", ts: now() }]));
  assert.equal(r.ok, true);
  assert.deepEqual(r.events[0].payload, {});
});

// --- the drop-off events --------------------------------------------------

test("progress and menu_click are accepted with their own keys only", () => {
  assert.deepEqual(validatePayload("progress", { x: 14000 }), { x: 14000 });
  assert.deepEqual(validatePayload("menu_click", { button: "play" }), { button: "play" });
  assert.equal(validatePayload("progress", { x: 14000, referrer: "google" }), null);
  assert.equal(validatePayload("menu_click", { button: "definitely_not_a_button" }), null);
});

test("run_end now carries where the run ended", () => {
  const out = validatePayload("run_end", {
    reason: "fell", score: 120, duration_sec: 45.5, x: 18000,
  });
  assert.deepEqual(out, { reason: "fell", score: 120, duration_sec: 45.5, x: 18000 });
});
