// Standalone HTTP server, for hosts that run a process rather than functions
// (Fly, Render, Railway, a VPS, or just `npm start` locally).
//
// No framework on purpose. The whole attack surface is one route and a health
// check, and every dependency is a thing that has to be trusted and patched;
// `pg` is the only one that earns its place.

const http = require("http");
const fs = require("fs");
const path = require("path");
const handler = require("./api/events");
const statsHandler = require("./api/stats");
const playerEventsHandler = require("./api/player-events");

const PORT = process.env.PORT || 8080;

const server = http.createServer(async (req, res) => {
  // Minimal Express-ish shims, so api/events.js runs unchanged on both a
  // serverless platform and here.
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (obj) => {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(obj));
    return res;
  };

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === "/healthz") {
    return res.status(200).json({ ok: true });
  }
  if (url.pathname === "/api/events") {
    try {
      return await handler(req, res);
    } catch (err) {
      console.error("unhandled:", err.message);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
      return;
    }
  }
  if (url.pathname === "/api/stats") {
    try {
      return await statsHandler(req, res);
    } catch (err) {
      console.error("unhandled:", err.message);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
      return;
    }
  }
  if (url.pathname === "/api/player-events") {
    try {
      return await playerEventsHandler(req, res);
    } catch (err) {
      console.error("unhandled:", err.message);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
      return;
    }
  }
  if (url.pathname === "/dashboard") {
    const html = fs.readFileSync(path.join(__dirname, "public", "dashboard.html"));
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(200).end(html);
  }
  return res.status(404).json({ error: "not_found" });
});

server.listen(PORT, () => console.log(`telemetry listening on :${PORT}`));
