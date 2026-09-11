import pg, { type PoolClient, type QueryResultRow } from 'pg';
import { createHash, randomUUID } from 'node:crypto';
import type { Environment } from '../config/env.js';
import { AppError, ensure } from '../domain/errors.js';

export type Tx = PoolClient;
export interface Actor { kind: 'user' | 'admin' | 'provider' | 'system' | 'anonymous'; id?: string; userId?: string; role?: 'user' | 'reviewer' | 'admin'; requestId: string; ipHash?: string; deviceHash?: string }
export class Database {
  readonly pool: pg.Pool;
  constructor(readonly env: Environment, migration = false) {
    this.pool = new pg.Pool({ connectionString: env.databaseUrl(migration), max: 12, connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 10000, application_name: 'sharebondhu', ssl: env.databaseSsl ? { rejectUnauthorized: true } : false,
      options: `-c search_path=${env.schema},public -c timezone=UTC` });
    this.pool.on('error', () => { /* Requests map connection failures to redacted errors. */ });
  }
  query<T extends QueryResultRow = QueryResultRow>(text: string, values: unknown[] = []) { return this.pool.query<T>(text, values); }
  async transaction<T>(operation: (tx: Tx) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const tx = await this.pool.connect();
      try {
        await tx.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
        await tx.query("SET LOCAL lock_timeout='5s'");
        await tx.query("SET LOCAL statement_timeout='15s'");
        const result = await operation(tx);
        await tx.query('COMMIT');
        return result;
      } catch (error) {
        try { await tx.query('ROLLBACK'); } catch {}
        const code = (error as { code?: string }).code;
        if ((code === '40001' || code === '40P01') && attempt < 3) {
          await new Promise(resolve => setTimeout(resolve, 10 * (attempt + 1)));
        } else { throw error; }
      } finally { tx.release(); }
    }
    throw new AppError('conflict', 409);
  }
  close() { return this.pool.end(); }
}

export function canonical(input: unknown): string {
  function ordered(value: unknown): unknown {
    if (typeof value === 'bigint') return value.toString();
    if (Array.isArray(value)) return value.map(ordered);
    if (value && typeof value === 'object' && !(value instanceof Date)) {
      const data = value as Record<string, unknown>;
      return Object.fromEntries(Object.keys(data).sort().map(key => [key, ordered(data[key])]));
    }
    return value;
  }
  return JSON.stringify(ordered(input));
}
export function hash(input: string | Buffer): string { return createHash('sha256').update(input).digest('hex'); }
export async function dbNow(tx: Tx): Promise<Date> { return (await tx.query<{ now: Date }>('SELECT now() AS now')).rows[0].now; }
export async function audit(tx: Tx, actor: Actor, account: string | null, action: string, entityType: string, entityId: string | null, reason: string, context: Record<string, unknown> = {}): Promise<string> {
  const id = randomUUID();
  await tx.query('INSERT INTO audit_logs(id,actor_kind,actor_id,account_id,action,entity_type,entity_id,request_id,reason,context) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
    [id, actor.kind, actor.id ?? null, account, action, entityType, entityId, actor.requestId, reason, canonical(context)]);
  return id;
}
export async function idempotent<T>(tx: Tx, env: Environment, scope: string, operation: string, key: string, payload: unknown, action: () => Promise<T>): Promise<T> {
  const fingerprint = hash(canonical(payload));
  const inserted = await tx.query('INSERT INTO idempotency_keys(actor_scope,operation,key,payload_hash,expires_at) VALUES($1,$2,$3,$4,now()+($5::text ||\' hours\')::interval) ON CONFLICT DO NOTHING RETURNING key',
    [scope, operation, key, fingerprint, env.idempotencyHours]);
  if (!inserted.rowCount) {
    const row = (await tx.query('SELECT * FROM idempotency_keys WHERE actor_scope=$1 AND operation=$2 AND key=$3 FOR UPDATE', [scope, operation, key])).rows[0];
    ensure(row && row.payload_hash === fingerprint, 'conflict', 409);
    ensure(new Date(row.expires_at).getTime() > (await dbNow(tx)).getTime(), 'conflict', 409);
    ensure(row.response !== null, 'conflict', 409);
    return row.response as T;
  }
  const result = await action();
  await tx.query('UPDATE idempotency_keys SET response=$4 WHERE actor_scope=$1 AND operation=$2 AND key=$3', [scope, operation, key, canonical(result)]);
  return result;
}
