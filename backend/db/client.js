// Shared Postgres pool.
//
// One pool per process (module-level singleton), because serverless instances
// are numerous and short-lived -- a pool per request would exhaust the
// database's connection limit under any real traffic.

const { Pool } = require("pg");

let pool;

function getPool() {
  if (!pool) {
    if (!process.env.DATABASE_URL) {
      throw new Error("DATABASE_URL is not set");
    }
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 5,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
      // TLS with the certificate ACTUALLY VERIFIED. The previous draft had
      // rejectUnauthorized: false, which is the standard copy-paste fix for
      // managed-Postgres cert errors and also turns the connection into one
      // that any machine on the path can impersonate. If your provider uses a
      // private CA, give it the CA rather than switching verification off:
      // set PGSSLROOTCERT to the CA file and it is picked up below.
      ssl: process.env.PGSSLROOTCERT
        ? { ca: require("fs").readFileSync(process.env.PGSSLROOTCERT).toString() }
        : { rejectUnauthorized: true },
    });
  }
  return pool;
}

module.exports = { getPool };
