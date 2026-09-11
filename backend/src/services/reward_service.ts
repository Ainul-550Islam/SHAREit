import { randomUUID } from 'node:crypto';
import type { QueryResultRow } from 'pg';
import type { Environment } from '../config/env.js';
import { Database, type Tx, type Actor, audit, dbNow, idempotent } from '../db/database.js';
import { AppError, ensure } from '../domain/errors.js';
import { number, money, iso, type RewardClaim, type PageQuery } from '../domain/validation.js';
import { rewardDto, sessionDto } from '../domain/mobile_dto.js';
import type { WalletService } from './wallet_service.js';

export class RewardService {
  constructor(readonly db: Database, readonly env: Environment, readonly wallet: WalletService) {}
  async policy(tx: Tx, source: string, targetId: string): Promise<QueryResultRow> {
    let row: QueryResultRow | undefined;
    if (source === 'promotionReward') {
      row = (await tx.query("SELECT p.*,m.id AS campaign_id,m.reward_coins AS campaign_coins,m.status AS campaign_status,m.starts_at,m.ends_at,m.destination_url,m.provider_id AS campaign_provider,m.countries AS campaign_countries FROM reward_policies p JOIN promotions m ON m.policy_id=p.id WHERE m.id::text=$1", [targetId])).rows[0];
    } else if (source === 'dailyReward') {
      row = (await tx.query("SELECT * FROM reward_policies WHERE source='dailyReward' AND ('daily:' || id::text || ':' || version::text)=$1", [targetId])).rows[0];
    } else {
      row = (await tx.query('SELECT * FROM reward_policies WHERE source=$1 AND policy_key=$2', [source,targetId])).rows[0];
    }
    ensure(row && row.source === source && row.enabled && this.env.rewardsEnabled, 'unavailable', 503);
    return row;
  }
  private async dayInfo(tx: Tx, userId: string, policyId: string, now: Date) {
    const today = iso(now).slice(0,10);
    const days = (await tx.query("SELECT DISTINCT s.quota_day::text AS day FROM reward_events e JOIN reward_sessions s ON s.id=e.reward_session_id WHERE e.user_id=$1 AND e.policy_id=$2 AND e.status IN ('approved','reconciled') ORDER BY day DESC LIMIT 7", [userId,policyId])).rows.map(row => row.day as string);
    const claimedToday = days[0] === today;
    let streak = 0;
    let expected = new Date(`${today}T00:00:00Z`).getTime() - (claimedToday ? 0 : 86400000);
    for (const day of days) {
      if (new Date(`${day}T00:00:00Z`).getTime() !== expected) break;
      streak += 1; expected -= 86400000;
    }
    return { today, claimedToday, day: claimedToday ? Math.max(1, streak) : streak % 7 + 1,
      nextDay: new Date(new Date(`${today}T00:00:00Z`).getTime() + 86400000) };
  }
  async dailyConfiguration(userId: string) {
    return this.db.transaction(async tx => {
      const policy = (await tx.query("SELECT * FROM reward_policies WHERE source='dailyReward' ORDER BY enabled DESC,updated_at DESC LIMIT 1")).rows[0];
      ensure(policy, 'unavailable', 503);
      const now = await dbNow(tx); const info = await this.dayInfo(tx,userId,policy.id,now);
      const steps = (await tx.query('SELECT * FROM daily_reward_steps WHERE policy_id=$1 ORDER BY day', [policy.id])).rows;
      ensure(steps.length === 7, 'unavailable', 503);
      const user = (await tx.query('SELECT * FROM users WHERE id=$1', [userId])).rows[0];
      const issued = (await tx.query("SELECT 1 FROM reward_sessions WHERE user_id=$1 AND policy_id=$2 AND quota_day=$3 AND source='dailyReward' AND availability='eligible'", [userId,policy.id,info.today])).rowCount;
      return { dayRewards: steps.map(step => number(step.reward_coins)), streakDay: info.day,
        eligible: Boolean(this.env.rewardsEnabled && policy.enabled && user.status === 'active' && user.country_verified_at && policy.countries.includes(user.country_code) && !issued),
        nextEligibleAt: iso(issued || info.claimedToday ? info.nextDay : now), version: `daily:${policy.id}:${policy.version}` };
    });
  }
  async adConfiguration(userId: string) {
    const row = (await this.db.query("SELECT p.*,v.enabled AS provider_enabled,v.secret_ref,u.status AS account_status FROM reward_policies p LEFT JOIN providers v ON v.id=p.provider_id AND v.kind='ad' CROSS JOIN users u WHERE p.source='adReward' AND p.policy_key='rewarded' AND u.id=$1 LIMIT 1", [userId])).rows[0];
    const active = Boolean(row && this.env.rewardsEnabled && row.enabled && row.provider_enabled && row.account_status === 'active' && row.ad_unit && this.env.providerSecret(row.secret_ref ?? ''));
    return { rewardedEnabled: active, bannerEnabled: false, interstitialEnabled: false, cooldownSeconds: row?.cooldown_seconds ?? 0,
      dailyLimit: active ? row.daily_limit : 0, premium: false, provider: active ? row.provider_id : null, units: active ? { rewarded: row.ad_unit } : {} };
  }

  async createSession(userId: string, input: { source: string; targetId: string; idempotencyKey: string }, actor: Actor) {
    return this.db.transaction(tx => idempotent(tx, this.env, `user:${userId}`, 'reward.session', input.idempotencyKey, input, async () => {
      const user = await this.wallet.lockWallet(tx,userId); const policy = await this.policy(tx,input.source,input.targetId); const now = await dbNow(tx);
      ensure(user.country_verified_at && policy.countries.includes(user.country_code), 'restricted', 403);
      ensure(now.getTime() - new Date(user.account_created).getTime() >= policy.minimum_account_age_seconds * 1000, 'restricted', 403);
      const providerId = input.source === 'promotionReward' ? policy.campaign_provider : policy.provider_id;
      const provider = (await tx.query('SELECT * FROM providers WHERE id=$1', [providerId])).rows[0];
      ensure(provider?.enabled && (provider.kind === 'internal' || this.env.providerSecret(provider.secret_ref ?? '')), 'unavailable', 503);
      if (input.source === 'promotionReward') {
        ensure(policy.campaign_status === 'active' && policy.campaign_countries.includes(user.country_code) && now >= policy.starts_at && now < policy.ends_at, 'expired_offer', 409);
      }
      const day = iso(now).slice(0,10);
      await tx.query('INSERT INTO reward_quota(user_id,policy_id,quota_day) VALUES($1,$2,$3) ON CONFLICT DO NOTHING', [userId,policy.id,day]);
      const quota = (await tx.query('SELECT * FROM reward_quota WHERE user_id=$1 AND policy_id=$2 AND quota_day=$3 FOR UPDATE', [userId,policy.id,day])).rows[0];
      const nextDay = new Date(new Date(`${day}T00:00:00Z`).getTime() + 86400000);
      let availability = 'eligible'; let notBefore = now;
      if (quota.issued >= policy.daily_limit) { availability = 'dailyLimit'; notBefore = nextDay; }
      else if (quota.last_issued_at && now.getTime() < new Date(quota.last_issued_at).getTime() + policy.cooldown_seconds * 1000) {
        availability = 'cooldown'; notBefore = new Date(new Date(quota.last_issued_at).getTime() + policy.cooldown_seconds * 1000);
      }
      let amount = money(input.source === 'promotionReward' ? policy.campaign_coins : policy.reward_coins);
      let providerHint: string | null = null;
      if (input.source === 'dailyReward') {
        const info = await this.dayInfo(tx,userId,policy.id,now);
        const step = (await tx.query('SELECT reward_coins FROM daily_reward_steps WHERE policy_id=$1 AND day=$2', [policy.id,info.day])).rows[0];
        ensure(step, 'unavailable', 503); amount = money(step.reward_coins); providerHint = `daily:${userId}:${day}`;
      }
      ensure(amount > 0n && amount <= this.env.maxReward, 'invalid_request');
      const id = randomUUID(); const eventId = randomUUID(); const eventKey = `claim:${randomUUID()}`;
      const expires = new Date(notBefore.getTime() + policy.session_seconds * 1000);
      let launchUrl: string | null = null;
      if (input.source === 'promotionReward') {
        const uri = new URL(policy.destination_url); ensure(this.env.trackingOrigins.has(uri.origin), 'unavailable', 503);
        uri.searchParams.set(provider.tracking_parameter, id); launchUrl = uri.toString();
      }
      const row = (await tx.query(`INSERT INTO reward_sessions(id,user_id,policy_id,policy_version,source,provider_id,target_id,quoted_coins,event_id,event_key,request_key,issued_at,expires_at,not_before,availability,quota_day,used_today,daily_limit,provider_event_hint,launch_url,ad_unit)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21) RETURNING *`,
        [id,userId,policy.id,policy.version,input.source,providerId,input.targetId,amount.toString(),eventId,eventKey,input.idempotencyKey,now,expires,notBefore,availability,day,quota.issued,policy.daily_limit,providerHint,launchUrl,policy.ad_unit])).rows[0];
      if (availability === 'eligible') {
        await tx.query('UPDATE reward_quota SET issued=issued+1,last_issued_at=$4 WHERE user_id=$1 AND policy_id=$2 AND quota_day=$3', [userId,policy.id,day,now]);
        if (input.source === 'promotionReward') await tx.query('INSERT INTO promotion_events(user_id,promotion_id,reward_session_id) VALUES($1,$2,$3)', [userId,input.targetId,id]);
      }
      await audit(tx,actor,userId,'reward.session','reward_session',id,'Server policy evaluated; session is not a credit.',{ source: input.source, availability });
      return sessionDto(row);
    }));
  }

  async sessionStatus(userId: string, reference: { sessionId?: string; requestKey?: string }) {
    const row = (await this.db.query('SELECT * FROM reward_sessions WHERE user_id=$1 AND (id::text=$2 OR request_key=$3)', [userId,reference.sessionId ?? null,reference.requestKey ?? null])).rows[0];
    ensure(row, 'not_found', 404); return sessionDto(row);
  }

  async submitClaim(userId: string, input: RewardClaim, actor: Actor) {
    ensure(input.userId === userId, 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx,this.env,`user:${userId}`,'reward.submit',input.idempotencyKey,input,async () => {
      await this.wallet.lockWallet(tx,userId);
      const session = (await tx.query('SELECT * FROM reward_sessions WHERE event_id=$1 AND user_id=$2 FOR UPDATE', [input.eventId,userId])).rows[0];
      ensure(session, 'not_found', 404);
      ensure(input.source === session.source && input.provider === session.provider_id && input.targetId === session.target_id &&
        input.idempotencyKey === session.event_key && money(input.requestedCoins) === money(session.quoted_coins) && input.metadata.trace === session.id, 'invalid_request');
      if (session.source === 'dailyReward') ensure(input.providerEventId === session.provider_event_hint, 'invalid_request');
      const existing = (await tx.query('SELECT * FROM reward_events WHERE id=$1 FOR UPDATE', [input.eventId])).rows[0];
      if (existing) {
        ensure(existing.provider_event_id === input.providerEventId, 'conflict', 409);
        return rewardDto(existing);
      }
      const now = await dbNow(tx); ensure(session.availability === 'eligible' && now >= session.not_before && now < session.expires_at, 'expired_offer', 409);
      const proof = (await tx.query('SELECT * FROM provider_events WHERE provider_id=$1 AND provider_event_id=$2 AND reward_session_id=$3 AND user_id=$4', [input.provider,input.providerEventId,session.id,userId])).rows[0];
      await tx.query(`INSERT INTO reward_events(id,user_id,source,provider_id,provider_event_id,provider_event_ref,target_id,quoted_coins,policy_id,policy_version,reward_session_id,status,idempotency_key,client_occurred_at,metadata)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'received',$12,$13,$14)`,
        [session.event_id,userId,session.source,session.provider_id,input.providerEventId,proof?.id ?? null,session.target_id,session.quoted_coins,session.policy_id,session.policy_version,session.id,session.event_key,input.occurredAt,{ trace: session.id }]);
      await tx.query("UPDATE reward_events SET status='validating' WHERE id=$1", [session.event_id]);
      await tx.query("UPDATE reward_events SET status='pending' WHERE id=$1", [session.event_id]);
      await audit(tx,actor,userId,'reward.received','reward_event',session.event_id,'Client action stored as a claim. Amount comes from the server session.');
      const policy = (await tx.query('SELECT * FROM reward_policies WHERE id=$1', [session.policy_id])).rows[0];
      if (session.source === 'dailyReward') return this.wallet.approveRewardIn(tx, session.event_id, { kind: 'system', id: 'daily-policy', requestId: actor.requestId }, 'Server daily policy and quota verified.');
      if (proof && policy.auto_approve) return this.wallet.approveRewardIn(tx, session.event_id, { kind: 'provider', id: session.provider_id, requestId: actor.requestId }, 'Verified provider evidence and configured automatic policy.');
      return rewardDto((await tx.query('SELECT * FROM reward_events WHERE id=$1', [session.event_id])).rows[0]);
    }));
  }

  async ingestEvidenceIn(tx: Tx, proof: QueryResultRow, actor: Actor) {
    await this.wallet.lockWallet(tx,proof.user_id);
    const session = proof.reward_session_id ? (await tx.query('SELECT * FROM reward_sessions WHERE id=$1 AND user_id=$2', [proof.reward_session_id,proof.user_id])).rows[0] : null;
    const start = proof.offer_start_id ? (await tx.query('SELECT * FROM offer_starts WHERE id=$1 AND user_id=$2', [proof.offer_start_id,proof.user_id])).rows[0] : null;
    ensure(session || start, 'invalid_request');
    const context = session ?? start;
    const id = context.event_id; const source = session ? session.source : 'offerReward';
    const target = session ? session.target_id : start.offer_id;
    const key = session ? session.event_key : start.claim_key;
    let event = (await tx.query('SELECT * FROM reward_events WHERE id=$1 FOR UPDATE', [id])).rows[0];
    if (event) {
      ensure(event.provider_event_id === proof.provider_event_id && event.user_id === proof.user_id, 'duplicate_event', 409);
      if (!event.provider_event_ref) await tx.query('UPDATE reward_events SET provider_event_ref=$2 WHERE id=$1', [id,proof.id]);
    } else {
      await tx.query(`INSERT INTO reward_events(id,user_id,source,provider_id,provider_event_id,provider_event_ref,target_id,quoted_coins,policy_id,policy_version,reward_session_id,offer_start_id,status,idempotency_key,metadata)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'received',$13,$14)`,
        [id,proof.user_id,source,proof.provider_id,proof.provider_event_id,proof.id,target,context.quoted_coins,context.policy_id,context.policy_version,session?.id ?? null,start?.id ?? null,key,{ trace: context.id }]);
      await tx.query("UPDATE reward_events SET status='validating' WHERE id=$1", [id]);
      await tx.query("UPDATE reward_events SET status='pending' WHERE id=$1", [id]);
      if (start) await tx.query("UPDATE offer_starts SET status='pending',updated_at=now() WHERE id=$1", [start.id]);
    }
    await audit(tx,actor,proof.user_id,'provider.reward_verified','reward_event',id,'Authenticated provider evidence bound to an existing server action.');
    const policy = (await tx.query('SELECT * FROM reward_policies WHERE id=$1', [context.policy_id])).rows[0];
    event = (await tx.query('SELECT * FROM reward_events WHERE id=$1', [id])).rows[0];
    if (policy.auto_approve && event.status === 'pending') return this.wallet.approveRewardIn(tx,id,actor,'Provider signature, mapping and server eligibility verified.');
    return rewardDto(event);
  }

  async getEvent(userId: string, id: string) { const row = (await this.db.query('SELECT * FROM reward_events WHERE id=$1 AND user_id=$2', [id,userId])).rows[0]; ensure(row,'not_found',404); return rewardDto(row); }
  async listEvents(userId: string, query: PageQuery) {
    const total = number((await this.db.query('SELECT count(*)::text AS total FROM reward_events WHERE user_id=$1', [userId])).rows[0].total);
    const rows = (await this.db.query('SELECT * FROM reward_events WHERE user_id=$1 ORDER BY created_at DESC,id DESC LIMIT $2 OFFSET $3', [userId,query.pageSize,(query.page - 1) * query.pageSize])).rows;
    return { items: rows.map(rewardDto), total };
  }
  async reconcileEvent(userId: string, id: string, actor: Actor, key: string) {
    return this.db.transaction(tx => idempotent(tx,this.env,`user:${userId}`,'reward.reconcile',key,{ id },async () => {
      await this.wallet.lockWallet(tx,userId,false);
      const event = (await tx.query('SELECT * FROM reward_events WHERE id=$1 AND user_id=$2 FOR UPDATE', [id,userId])).rows[0]; ensure(event,'not_found',404);
      if (event.status === 'approved') {
        ensure((await tx.query('SELECT 1 FROM wallet_transactions WHERE id=$1 AND user_id=$2 AND reward_event_id=$3', [event.transaction_id,userId,id])).rowCount, 'unavailable',503);
        await tx.query("UPDATE reward_events SET status='reconciled' WHERE id=$1", [id]);
      }
      await audit(tx,actor,userId,'reward.reconcile','reward_event',id,'Existing ledger status acknowledged; no new credit created.');
      return rewardDto((await tx.query('SELECT * FROM reward_events WHERE id=$1', [id])).rows[0]);
    }));
  }
}
