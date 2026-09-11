import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv, type Environment } from '../config/env.js';
import { Database, hash } from './database.js';

export async function migrate(env: Environment, sqlPath = resolve('src/db/schema.sql')): Promise<void> {
  const db = new Database(env, true);
  const sql = await readFile(sqlPath, 'utf8');
  try {
    await db.transaction(async tx => {
      await tx.query("SELECT pg_advisory_xact_lock(hashtext('sharebondhu-migration-v1'))");
      await tx.query(`CREATE SCHEMA IF NOT EXISTS "${env.schema}"`);
      await tx.query(`SET LOCAL search_path="${env.schema}",public`);
      await tx.query('CREATE TABLE IF NOT EXISTS schema_migrations(version integer PRIMARY KEY, checksum char(64) NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())');
      const existing = (await tx.query('SELECT checksum FROM schema_migrations WHERE version=1')).rows[0];
      if (existing) {
        if (existing.checksum !== hash(sql)) throw new Error('Migration checksum changed. Create a new migration instead of rewriting database history.');
        return;
      }
      await tx.query(sql);
      await tx.query('INSERT INTO schema_migrations(version,checksum) VALUES(1,$1)', [hash(sql)]);
    });
  } finally { await db.close(); }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  migrate(loadEnv()).then(() => console.log('Database migration verified/applied.')).catch(() => { console.error('Migration failed; sensitive database details are redacted.'); process.exitCode = 1; });
}
