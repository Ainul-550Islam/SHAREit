import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { Environment } from '../config/env.js';
import { Database, type Actor, audit, idempotent } from '../db/database.js';
import { ensure } from '../domain/errors.js';
import { id, uuid, coin, positiveCoin, text, category, platform, method, utcTime, httpsUrl, parse } from '../domain/validation.js';

const countries = z.array(z.string().regex(/^[A-Z]{2}$/)).max(250).refine(list => new Set(list).size === list.length);
const platforms = z.array(platform).min(1).max(2).refine(list => new Set(list).size === list.length);
const approval = { reason: text(1000), idempotencyKey: id };
const providerSchema = z.object({ id, name: text(), kind: z.enum(['ad','offer','promotion','payout']), secretReference: id,
  enabled: z.boolean(), trackingParameter: z.string().regex(/^[A-Za-z][A-Za-z0-9_]{0,31}$/).default('sb_start'), developmentOnly: z.boolean().default(false),
  reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();
const policySchema = z.object({ id: uuid.optional(), policyKey: id, source: z.enum(['adReward','offerReward','promotionReward','referralReward','dailyReward']), providerId: id,
  rewardCoins: coin, enabled: z.boolean(), autoApprove: z.boolean(), dailyLimit: z.number().int().min(1).max(1000), cooldownSeconds: z.number().int().min(0).max(86400),
  sessionSeconds: z.number().int().min(30).max(86400).default(600), minimumAccountAgeSeconds: z.number().int().min(0).max(31536000).default(0),
  qualifyingEvents: z.number().int().min(1).max(100).default(1), blockSharedRisk: z.boolean().default(true), countries, platforms,
  adUnit: text(160).optional(), dayRewards: z.array(coin).length(7).optional(), reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();
const offerSchema = z.object({ id: uuid.optional(), title: text(), shortDescription: text(500), description: text(4000), publisher: text(), category,
  providerId: id, policyId: uuid, rewardCoins: positiveCoin, estimatedMinutes: z.number().int().min(0).max(525600), countries, platforms,
  status: z.enum(['available','unavailable']), featured: z.boolean(), sortPriority: z.number().int().min(0).max(1000000),
  iconUrl: text(2048).nullable(), installUrl: text(2048).nullable(), destinationUrl: text(2048).nullable(), trackingUrl: text(2048).nullable(),
  instructions: z.array(text(500)).max(20), terms: z.array(text(500)).max(20), startsAt: utcTime, expiresAt: utcTime,
  developmentOnly: z.boolean().default(false), reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();
const promotionSchema = z.object({ id: uuid.optional(), title: text(), description: text(4000), advertiser: text(), cta: text(80), providerId: id, policyId: uuid,
  rewardCoins: positiveCoin, imageUrl: text(2048).nullable(), destinationUrl: text(2048), countries, platforms,
  status: z.enum(['scheduled','active','paused','expired','completed','unavailable']), startsAt: utcTime, endsAt: utcTime,
  developmentOnly: z.boolean().default(false), reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();
const withdrawalPolicySchema = z.object({ id: uuid.optional(), active: z.boolean(), minimumCoins: positiveCoin, maximumCoins: positiveCoin,
  coinUnits: positiveCoin, minorUnits: positiveCoin, currency: z.string().regex(/^[A-Z]{3}$/), scale: z.number().int().min(0).max(6),
  methods: z.array(z.object({ method, providerId: id.nullable(), enabled: z.boolean(), feeMinor: coin }).strict()).max(5), reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();
const destinationSchema = z.object({ userId: uuid, method, providerId: id, providerRecipientReference: id,
  maskedDestination: text(100).refine(value => /\*{3}/.test(value) && !/[0-9]{5}/.test(value)), enabled: z.boolean(), reason: approval.reason, idempotencyKey: approval.idempotencyKey }).strict();

export class AdminService {
  constructor(readonly db: Database, readonly env: Environment) {}
  private admin(actor: Actor) { ensure(actor.role === 'admin', 'restricted',403); }
  async provider(input: unknown, actor: Actor) {
    this.admin(actor); const data = parse(providerSchema,input);
    ensure(!data.enabled || this.env.providerSecret(data.secretReference), 'invalid_request');
    ensure(this.env.name !== 'production' || !data.developmentOnly, 'restricted',403);
    return this.db.transaction(tx => idempotent(tx,this.env,`admin:${actor.id}`,'provider.configure',data.idempotencyKey,data,async () => {
      const old = (await tx.query('SELECT kind FROM providers WHERE id=$1 FOR UPDATE', [data.id])).rows[0]; ensure(!old || old.kind === data.kind, 'conflict',409);
      await tx.query(`INSERT INTO providers(id,name,kind,secret_ref,enabled,tracking_parameter,development_only) VALUES($1,$2,$3,$4,$5,$6,$7)
        ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,secret_ref=EXCLUDED.secret_ref,enabled=EXCLUDED.enabled,tracking_parameter=EXCLUDED.tracking_parameter,updated_at=now()`,
        [data.id,data.name,data.kind,data.secretReference,data.enabled,data.trackingParameter,data.developmentOnly]);
      await audit(tx,actor,null,'provider.configure','provider',data.id,data.reason,{ enabled:data.enabled,kind:data.kind });
      return { providerId:data.id,enabled:data.enabled,protocol:'sharebondhu-hmac-v1' };
    }));
  }
  async policy(input: unknown, actor: Actor) {
    this.admin(actor); const data = parse(policySchema,input);
    ensure(BigInt(data.rewardCoins) <= this.env.maxReward && (!data.dayRewards || data.dayRewards.every(amount => BigInt(amount) <= this.env.maxReward)));
    ensure(data.source !== 'dailyReward' || data.dayRewards?.length === 7);
    return this.db.transaction(tx => idempotent(tx,this.env,`admin:${actor.id}`,'policy.configure',data.idempotencyKey,data,async () => {
      const provider = (await tx.query('SELECT * FROM providers WHERE id=$1', [data.providerId])).rows[0]; ensure(provider);
      const expected = { adReward:'ad',offerReward:'offer',promotionReward:'promotion',referralReward:'internal',dailyReward:'internal' }[data.source]; ensure(provider.kind === expected);
      const policyId = data.id ?? randomUUID();
      const old = (await tx.query('SELECT * FROM reward_policies WHERE id=$1 FOR UPDATE', [policyId])).rows[0]; ensure(!old || old.source === data.source, 'conflict',409);
      const row = (await tx.query(`INSERT INTO reward_policies(id,policy_key,source,provider_id,reward_coins,enabled,auto_approve,daily_limit,cooldown_seconds,session_seconds,minimum_account_age_seconds,qualifying_events,block_shared_risk,countries,platforms,ad_unit)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
        ON CONFLICT(id) DO UPDATE SET reward_coins=EXCLUDED.reward_coins,enabled=EXCLUDED.enabled,auto_approve=EXCLUDED.auto_approve,daily_limit=EXCLUDED.daily_limit,
        cooldown_seconds=EXCLUDED.cooldown_seconds,session_seconds=EXCLUDED.session_seconds,minimum_account_age_seconds=EXCLUDED.minimum_account_age_seconds,
        qualifying_events=EXCLUDED.qualifying_events,block_shared_risk=EXCLUDED.block_shared_risk,countries=EXCLUDED.countries,platforms=EXCLUDED.platforms,ad_unit=EXCLUDED.ad_unit,version=reward_policies.version+1,updated_at=now() RETURNING id,version`,
        [policyId,data.policyKey,data.source,data.providerId,String(data.rewardCoins),data.enabled,data.autoApprove,data.dailyLimit,data.cooldownSeconds,data.sessionSeconds,
          data.minimumAccountAgeSeconds,data.qualifyingEvents,data.blockSharedRisk,data.countries,data.platforms,data.adUnit ?? null])).rows[0];
      if (data.dayRewards) {
        await tx.query('DELETE FROM daily_reward_steps WHERE policy_id=$1', [policyId]);
        for (let i=0;i<data.dayRewards.length;i+=1) await tx.query('INSERT INTO daily_reward_steps(policy_id,day,reward_coins) VALUES($1,$2,$3)', [policyId,i+1,String(data.dayRewards[i])]);
      }
      await audit(tx,actor,null,'policy.configure','reward_policy',policyId,data.reason,{ version:String(row.version),source:data.source,rewardCoins:String(data.rewardCoins),enabled:data.enabled });
      return { policyId,version:String(row.version) };
    }));
  }
  async offer(input: unknown, actor: Actor) {
    this.admin(actor); const data=parse(offerSchema,input); ensure(BigInt(data.rewardCoins)<=this.env.maxReward && new Date(data.expiresAt)>new Date(data.startsAt));
    for (const url of [data.iconUrl,data.installUrl,data.destinationUrl,data.trackingUrl]) httpsUrl(url);
    ensure(this.env.name!=='production'||!data.developmentOnly,'restricted',403);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'offer.configure',data.idempotencyKey,data,async()=>{
      const policy=(await tx.query("SELECT * FROM reward_policies WHERE id=$1 AND source='offerReward' AND provider_id=$2",[data.policyId,data.providerId])).rows[0]; ensure(policy);
      const id=data.id??randomUUID();
      await tx.query(`INSERT INTO offers(id,title,short_description,description,publisher,category,provider_id,policy_id,reward_coins,estimated_minutes,countries,platforms,status,featured,sort_priority,icon_url,install_url,destination_url,tracking_url,instructions,terms,starts_at,expires_at,development_only)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24)
        ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,short_description=EXCLUDED.short_description,description=EXCLUDED.description,publisher=EXCLUDED.publisher,category=EXCLUDED.category,reward_coins=EXCLUDED.reward_coins,estimated_minutes=EXCLUDED.estimated_minutes,countries=EXCLUDED.countries,platforms=EXCLUDED.platforms,status=EXCLUDED.status,featured=EXCLUDED.featured,sort_priority=EXCLUDED.sort_priority,icon_url=EXCLUDED.icon_url,install_url=EXCLUDED.install_url,destination_url=EXCLUDED.destination_url,tracking_url=EXCLUDED.tracking_url,instructions=EXCLUDED.instructions,terms=EXCLUDED.terms,starts_at=EXCLUDED.starts_at,expires_at=EXCLUDED.expires_at,updated_at=now()`,
        [id,data.title,data.shortDescription,data.description,data.publisher,data.category,data.providerId,data.policyId,String(data.rewardCoins),data.estimatedMinutes,data.countries,data.platforms,data.status,data.featured,data.sortPriority,data.iconUrl,data.installUrl,data.destinationUrl,data.trackingUrl,data.instructions,data.terms,data.startsAt,data.expiresAt,data.developmentOnly]);
      await audit(tx,actor,null,'offer.configure','offer',id,data.reason,{ rewardCoins:String(data.rewardCoins),status:data.status }); return { offerId:id };
    }));
  }
  async promotion(input: unknown, actor: Actor) {
    this.admin(actor);const data=parse(promotionSchema,input);ensure(BigInt(data.rewardCoins)<=this.env.maxReward&&new Date(data.endsAt)>new Date(data.startsAt));httpsUrl(data.imageUrl);httpsUrl(data.destinationUrl);
    ensure(this.env.name!=='production'||!data.developmentOnly,'restricted',403);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'promotion.configure',data.idempotencyKey,data,async()=>{
      const policy=(await tx.query("SELECT * FROM reward_policies WHERE id=$1 AND source='promotionReward' AND provider_id=$2",[data.policyId,data.providerId])).rows[0];ensure(policy);
      const id=data.id??randomUUID();
      await tx.query(`INSERT INTO promotions(id,title,description,advertiser,cta,provider_id,policy_id,reward_coins,image_url,destination_url,countries,platforms,status,starts_at,ends_at,development_only)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
        ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,description=EXCLUDED.description,advertiser=EXCLUDED.advertiser,cta=EXCLUDED.cta,reward_coins=EXCLUDED.reward_coins,image_url=EXCLUDED.image_url,destination_url=EXCLUDED.destination_url,countries=EXCLUDED.countries,platforms=EXCLUDED.platforms,status=EXCLUDED.status,starts_at=EXCLUDED.starts_at,ends_at=EXCLUDED.ends_at,updated_at=now()`,
        [id,data.title,data.description,data.advertiser,data.cta,data.providerId,data.policyId,String(data.rewardCoins),data.imageUrl,data.destinationUrl,data.countries,data.platforms,data.status,data.startsAt,data.endsAt,data.developmentOnly]);
      await audit(tx,actor,null,'promotion.configure','promotion',id,data.reason);return { campaignId:id };
    }));
  }
  async withdrawalPolicy(input:unknown,actor:Actor) {
    this.admin(actor);const data=parse(withdrawalPolicySchema,input);ensure(data.maximumCoins>=data.minimumCoins&&new Set(data.methods.map(m=>m.method)).size===data.methods.length);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'withdrawal.policy',data.idempotencyKey,data,async()=>{
      const id=data.id??randomUUID(); if(data.active) await tx.query('UPDATE withdrawal_policies SET active=false WHERE id<>$1',[id]);
      const row=(await tx.query(`INSERT INTO withdrawal_policies(id,active,minimum_coins,maximum_coins,coin_units,minor_units,currency,scale) VALUES($1,$2,$3,$4,$5,$6,$7,$8)
        ON CONFLICT(id) DO UPDATE SET active=EXCLUDED.active,minimum_coins=EXCLUDED.minimum_coins,maximum_coins=EXCLUDED.maximum_coins,coin_units=EXCLUDED.coin_units,minor_units=EXCLUDED.minor_units,currency=EXCLUDED.currency,scale=EXCLUDED.scale,version=withdrawal_policies.version+1,updated_at=now() RETURNING version`,
        [id,data.active,String(data.minimumCoins),String(data.maximumCoins),String(data.coinUnits),String(data.minorUnits),data.currency,data.scale])).rows[0];
      await tx.query('DELETE FROM payout_methods WHERE policy_id=$1',[id]);
      for(const method of data.methods){
        if(method.enabled){const provider=(await tx.query("SELECT * FROM providers WHERE id=$1 AND kind='payout' AND enabled",[method.providerId])).rows[0];ensure(provider&&this.env.providerSecret(provider.secret_ref));}
        await tx.query('INSERT INTO payout_methods(policy_id,method,provider_id,enabled,fee_minor) VALUES($1,$2,$3,$4,$5)',[id,method.method,method.providerId,method.enabled,String(method.feeMinor)]);
      }
      await audit(tx,actor,null,'withdrawal.policy','withdrawal_policy',id,data.reason,{version:String(row.version),minimumCoins:String(data.minimumCoins),active:data.active});return { policyId:id,version:`policy:${id}:${row.version}` };
    }));
  }
  async destination(input:unknown,actor:Actor){
    this.admin(actor);const data=parse(destinationSchema,input);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'payout.destination',data.idempotencyKey,data,async()=>{
      const provider=(await tx.query("SELECT * FROM providers WHERE id=$1 AND kind='payout'",[data.providerId])).rows[0];ensure(provider);
      const row=(await tx.query(`INSERT INTO payout_destinations(user_id,method,provider_id,provider_recipient_ref,masked_destination,enabled) VALUES($1,$2,$3,$4,$5,$6)
        ON CONFLICT(user_id,method,provider_id) DO UPDATE SET provider_recipient_ref=EXCLUDED.provider_recipient_ref,masked_destination=EXCLUDED.masked_destination,enabled=EXCLUDED.enabled RETURNING id`,
        [data.userId,data.method,data.providerId,data.providerRecipientReference,data.maskedDestination,data.enabled])).rows[0];
      await audit(tx,actor,data.userId,'payout.destination','payout_destination',row.id,data.reason,{method:data.method,enabled:data.enabled});return {destinationId:row.id};
    }));
  }
  async account(userId:string,input:unknown,actor:Actor){
    this.admin(actor);const data=parse(z.object({status:z.enum(['active','restricted','suspended','deleted','pendingVerification']),country:z.string().regex(/^[A-Z]{2}$/).nullable(),reason:approval.reason,idempotencyKey:approval.idempotencyKey}).strict(),input);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'account.review',data.idempotencyKey,{userId,change:data},async()=>{
      const row=await tx.query('UPDATE users SET status=$2,country_code=$3,country_verified_at=CASE WHEN $3::text IS NULL THEN NULL ELSE now() END,version=version+1 WHERE id=$1 RETURNING id',[userId,data.status,data.country]);ensure(row.rowCount,'not_found',404);
      if(['suspended','deleted'].includes(data.status))await tx.query('UPDATE user_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE user_id=$1',[userId]);
      await audit(tx,actor,userId,'account.review','user',userId,data.reason,{status:data.status,country:data.country});return {userId,status:data.status};
    }));
  }
  async risk(userId:string,input:unknown,actor:Actor){
    this.admin(actor);const data=parse(z.object({code:id,blocking:z.boolean(),active:z.boolean(),reason:approval.reason,idempotencyKey:approval.idempotencyKey}).strict(),input);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'risk.review',data.idempotencyKey,{userId,change:data},async()=>{
      await tx.query('INSERT INTO risk_flags(user_id,code,blocking,active) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,code) DO UPDATE SET blocking=EXCLUDED.blocking,active=EXCLUDED.active,resolved_at=CASE WHEN EXCLUDED.active THEN NULL ELSE now() END',[userId,data.code,data.blocking,data.active]);
      await audit(tx,actor,userId,'risk.review','user',userId,data.reason,{code:data.code,blocking:data.blocking,active:data.active});return {userId,code:data.code,active:data.active};
    }));
  }
}
