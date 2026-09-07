-- Night Run telemetry schema. Postgres (Supabase / Neon / RDS / anything).
--
-- PRIVACY POSITION, and the reason the schema looks like this:
--
-- The only identifier stored is an anonymous id the game generates on the
-- player's own device. There is deliberately NOWHERE in this schema to put
-- a name, an email, an IP address, a user agent, a device id, or a location.
-- Not "we don't currently write it" -- there is no column, so a future bug or
-- a malicious sender cannot cause it to be stored.
--
-- The previous draft had a `user_agent` column on sessions. That is a coarse
-- device fingerprint and it is gone.
--
-- `payload` is JSONB, but the API validates every key and type against a
-- per-event allow-list before it reaches this table, so it cannot become a
-- dumping ground for arbitrary client data. See backend/api/events.js.

CREATE TABLE IF NOT EXISTS players (
    -- UUIDv4 generated on the device. Not derived from anything about the
    -- device or the person -- it is a random number kept in the game's own
    -- save data, and clearing the game's data gives a brand new one.
    player_id      UUID PRIMARY KEY,
    first_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
    id          BIGSERIAL PRIMARY KEY,
    player_id   UUID NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,
    -- One run of the game. Lets you separate "played 3 short runs" from
    -- "played one long one" without needing anything else about the player.
    session_id  UUID NOT NULL,
    event_name  TEXT NOT NULL,
    payload     JSONB NOT NULL DEFAULT '{}',
    client_ts   TIMESTAMPTZ NOT NULL,          -- when it happened on the device
    server_ts   TIMESTAMPTZ NOT NULL DEFAULT now()  -- when this service received it
);

CREATE INDEX IF NOT EXISTS idx_events_player   ON events(player_id);
CREATE INDEX IF NOT EXISTS idx_events_session  ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_name     ON events(event_name);
CREATE INDEX IF NOT EXISTS idx_events_server_ts ON events(server_ts);

-- ---------------------------------------------------------------------------
-- Deletion. A player asking to be forgotten only needs their id, which the
-- game can show them (see Telemetry.player_id). ON DELETE CASCADE means one
-- statement removes them and every event they ever sent:
--
--   DELETE FROM players WHERE player_id = '<uuid>';
--
-- Retention. Nothing here needs to live forever; run this on a schedule so
-- the dataset stays small and old data expires rather than accumulating:
--
--   DELETE FROM events WHERE server_ts < now() - INTERVAL '180 days';
--   DELETE FROM players WHERE last_seen_at < now() - INTERVAL '180 days';
-- ---------------------------------------------------------------------------

-- Example questions this can answer -----------------------------------------
--
-- Where do people stop playing?
--   SELECT (payload->>'x')::int / 1000 * 1000 AS zone, COUNT(*)
--   FROM events WHERE event_name = 'player_died' GROUP BY zone ORDER BY zone;
--
-- How far does a typical run get, and how many finish?
--   SELECT payload->>'reason', COUNT(*), AVG((payload->>'duration_sec')::float)
--   FROM events WHERE event_name = 'run_end' GROUP BY 1;
--
-- Which weapons actually get picked up?
--   SELECT payload->>'item', COUNT(*) FROM events
--   WHERE event_name = 'item_collected' GROUP BY 1 ORDER BY 2 DESC;
