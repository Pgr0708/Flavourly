// `npm run migrate` — applies migrations/*.sql to the database in backend/.env, then exits.
import { loadConfig } from './config.js';
import { createPool, migrate } from './db.js';

const pool = createPool(loadConfig());
try {
  await migrate(pool);
  console.log('Database is up to date.');
} catch (error) {
  console.error(`Migration failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
