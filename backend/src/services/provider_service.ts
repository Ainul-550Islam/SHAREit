import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import type { Environment } from '../config/env.js';
import { Database, type Actor, audit, hash, canonical, idempotent, dbNow } from '../db/database.js';
import { ensure, AppError } from '../domain/errors.js';
import { parse, providerPayload } from '../domain/validation.js';
import type { RewardService } from './reward_service.js';
import type { WalletService } from './wallet_service.js';

export class ProviderService {
  constructor(readonly db: Database, readonly env: Environment, readonly rewards: RewardService, readonly wallet: WalletService) {}
  async ingest(providerId: string, raw: Buffer, timestamp: string | undefined, signature: string | undefined, requestId: string) {
    const provider = (await this.db.query("SELECT * FROM providers WHERE id=$1 AND enabled AND kind<>'internal' AND protocol='sharebondhu-hmac-v1'", [providerId])).rows[0];
    const secret = provider ? this.env.providerSecret(provider.secret_ref) : undefined;
    ensure(provider && secret && timestamp && /^\d{10}$/.test(timestamp) && signature && /^[a-fA-F0-9]{64}$/.test(signature), 'invalid_provider_signature', 403);
    const seconds = Number(timestamp);
    ensure(Number.isSafeInteger(seconds) && Math.abs(Math.floor(Date.now() / 1000) - seconds) <= this.env.replaySeconds, 'invalid_provider_signature', 403);
    const expected = createHmac('sha256', secret).update(timestamp).update('.').update(raw).digest();
    const provided = Buffer.from(signature, 'hex');
    ensure(expected.length === provided.length && timingSafeEqual(expected, provided), 'invalid_provider_signature', 403);
    let decoded: unknown; try { decoded = JSON.parse(raw.toString('utf8')); } catch { throw new AppError('invalid_request'); }
    const event = parse(providerPayload, decoded);
    const kind = { adCompletion: 'ad', offerCompletion: 'offer', promotionConversion: 'promotion', payoutResult: 'payout' }[event.type];
    ensure(provider.kind === kind, 'invalid_provider_signature', 403);
    const signedAt = new Date(seconds * 1000);
    return this.db.transaction(tx => idempotent(tx,this.env,`provider:${providerId}`,'provider.ingest',event.eventId,event,async () => {
      const table = event.rewardSessionId ? 'reward_sessions' : event.offerStartId ? 'offer_starts' : 'withdrawal_requests';
      const contextId = event.rewardSessionId ?? event.offerStartId ?? event.withdrawalId!;
      const context = (await tx.query(`SELECT * FROM ${table} WHERE id=$1 AND provider_id=$2`, [contextId,providerId])).rows[0];
      ensure(context, 'not_found', 404);
      await this.wallet.lockWallet(tx,context.user_id,event.type !== 'payoutResult');
      if (event.type === 'payoutResult') {
        ensure(event.withdrawalId && event.status && event.reference && context.status === 'processing', 'conflict', 409);
      } else {
        ensure(event.platform, 'invalid_request');
        const policy = (await tx.query('SELECT * FROM reward_policies WHERE id=$1', [context.policy_id])).rows[0];
        ensure(policy?.enabled && policy.platforms.includes(event.platform), 'restricted', 403);
        const started = context.issued_at ?? context.created_at;
        ensure(signedAt.getTime() >= new Date(started).getTime() - 1000 && signedAt < context.expires_at, 'expired_offer', 409);
        ensure(event.type !== 'adCompletion' || context.source === 'adReward', 'invalid_request');
        ensure(event.type !== 'promotionConversion' || context.source === 'promotionReward', 'invalid_request');
        ensure(event.type !== 'offerCompletion' || event.offerStartId, 'invalid_request');
        if (event.rewardSessionId) ensure(context.availability === 'eligible', 'restricted', 403);
      }
      const existing = (await tx.query('SELECT * FROM provider_events WHERE provider_id=$1 AND provider_event_id=$2', [providerId,event.eventId])).rows[0];
      const fingerprint = hash(canonical(event));
      if (existing) { ensure(existing.body_hash === fingerprint, 'duplicate_event', 409); return { providerEventId: existing.id, accepted: true }; }
      const actor: Actor = { kind: 'provider', id: providerId, userId: context.user_id, requestId };
      const proof = (await tx.query(`INSERT INTO provider_events(id,provider_id,provider_event_id,event_type,user_id,reward_session_id,offer_start_id,withdrawal_id,body_hash,signed_timestamp,outcome,external_reference,payload)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING *`,
        [randomUUID(),providerId,event.eventId,event.type,context.user_id,event.rewardSessionId ?? null,event.offerStartId ?? null,event.withdrawalId ?? null,
          fingerprint,signedAt,event.status ?? null,event.reference ?? null,event])).rows[0];
      await audit(tx,actor,context.user_id,'provider.ingest','provider_event',proof.id,'Configured generic HMAC partner evidence verified.',{ bodyHash: hash(raw), providerEventId: event.eventId });
      if (event.type === 'payoutResult') {
        const withdrawal = await this.wallet.transitionWithdrawalIn(tx,context.id,event.status!,actor,'Verified provider payout result.',proof.id);
        return { providerEventId: proof.id, accepted: true, withdrawal };
      }
      const reward = await this.rewards.ingestEvidenceIn(tx,proof,actor);
      return { providerEventId: proof.id, accepted: true, reward };
    }));
  }
}
