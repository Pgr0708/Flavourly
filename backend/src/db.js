import fs from 'node:fs/promises';
import path from 'node:path';
import mysql from 'mysql2/promise';
import { ROOT } from './config.js';
import { log } from './util.js';

/** A small pool per process; with PM2 cluster mode total connections = DB_POOL_SIZE × instances. */
export function createPool(config) {
  return mysql.createPool({
    ...(config.DB_SOCKET ? { socketPath: config.DB_SOCKET } : { host: config.DB_HOST, port: config.DB_PORT }),
    user: config.DB_USER,
    password: config.DB_PASSWORD,
    database: config.DB_NAME,
    connectionLimit: config.DB_POOL_SIZE,
    maxIdle: config.DB_POOL_SIZE,
    idleTimeout: 60_000,
    waitForConnections: true,
    queueLimit: 200,
    enableKeepAlive: true,
    charset: 'utf8mb4',
    timezone: 'Z',
    dateStrings: true,
    connectTimeout: 10_000,
  });
}

/**
 * Applies migrations/*.sql once each, in order. A MySQL named lock makes this safe when several
 * instances (PM2 cluster, or more servers) start at the same time.
 */
export async function migrate(pool) {
  const connection = await pool.getConnection();
  try {
    const [[lock]] = await connection.query("SELECT GET_LOCK('flavourly_migrations', 30) AS ok");
    if (lock.ok !== 1) throw new Error('Could not get the migration lock (another instance is migrating).');
    await connection.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(64) NOT NULL PRIMARY KEY,
      applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`);
    const [rows] = await connection.query('SELECT version FROM schema_migrations');
    const done = new Set(rows.map((row) => row.version));
    const dir = path.join(ROOT, 'migrations');
    const files = (await fs.readdir(dir)).filter((file) => file.endsWith('.sql')).sort();
    for (const file of files) {
      if (done.has(file)) continue;
      const sql = await fs.readFile(path.join(dir, file), 'utf8');
      const statements = sql.split(/;\s*$/m).map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean);
      for (const statement of statements) await connection.query(statement);
      await connection.query('INSERT INTO schema_migrations (version) VALUES (?)', [file]);
      log.info('migration applied', { file });
    }
  } finally {
    await connection.query("SELECT RELEASE_LOCK('flavourly_migrations')").catch(() => {});
    connection.release();
  }
}
