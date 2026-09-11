import { createHmac } from 'node:crypto';
import type { FastifyRequest } from 'fastify';
import type { Environment, RateAction } from '../config/env.js';
import type { Database } from '../db/database.js';
import { ensure, AppError } from '../domain/errors.js';
import { id, parse } from '../domain/validation.js';

export class RateLimiter {
  constructor(readonly db: Database, readonly env: Environment) {}
  async consume(scope: string, action: RateAction) {
    const rule = this.env.rates[action];
    const fingerprint = createHmac('sha256',this.env.riskSecret()).update(scope).digest('hex');
    const result = await this.db.query(`INSERT INTO rate_limit_buckets(scope_hash,action,bucket,count,expires_at)
      VALUES($1,$2,floor(extract(epoch FROM clock_timestamp())/$3)::bigint,1,now()+($3::text || ' seconds')::interval*2)
      ON CONFLICT(scope_hash,action,bucket) DO UPDATE SET count=rate_limit_buckets.count+1
      WHERE rate_limit_buckets.count<$4 RETURNING count`, [fingerprint,action,rule.seconds,rule.limit]);
    ensure(result.rowCount, 'rate_limited',429);
  }
}
export function requestKey(request: FastifyRequest, body: { idempotencyKey: string }): string {
  const header = request.headers['idempotency-key'];
  const key = parse(id,header); ensure(key===body.idempotencyKey,'conflict',409); return key;
}
export function boundedJson(buffer: Buffer): unknown {
  if (buffer.length > 65536) throw new AppError('invalid_request');
  const decoder = new TextDecoder('utf-8',{fatal:true}); let text: string;
  try { text = decoder.decode(buffer); } catch { throw new AppError('invalid_request'); }
  let depth=0,quoted=false,escaped=false;
  for(const character of text){
    if(quoted){if(escaped)escaped=false;else if(character==='\\')escaped=true;else if(character==='"')quoted=false;}
    else if(character==='"')quoted=true;
    else if(character==='{'||character==='['){depth+=1;if(depth>32)throw new AppError('invalid_request');}
    else if(character==='}'||character===']'){depth-=1;if(depth<0)throw new AppError('invalid_request');}
  }
  if(quoted||depth!==0)throw new AppError('invalid_request');
  try { return JSON.parse(text); } catch { throw new AppError('invalid_request'); }
}
