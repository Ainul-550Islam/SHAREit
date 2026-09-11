import { randomUUID } from 'node:crypto';
import type { Environment } from '../config/env.js';
import { Database, type Actor, audit, idempotent, dbNow } from '../db/database.js';
import { ensure } from '../domain/errors.js';
import { number, iso } from '../domain/validation.js';
import type { WalletService } from './wallet_service.js';

export class ReferralService {
  constructor(readonly db: Database, readonly env: Environment, readonly wallet: WalletService) {}
  async summary(userId: string) {
    const user = (await this.db.query('SELECT * FROM users WHERE id=$1', [userId])).rows[0]; ensure(user,'not_found',404);
    const counts = (await this.db.query("SELECT count(*)::text AS invited,count(*) FILTER(WHERE status='pending')::text AS pending,count(*) FILTER(WHERE status IN ('qualified','rewarded'))::text AS qualified FROM referrals WHERE inviter_id=$1",[userId])).rows[0];
    const amount = (await this.db.query("SELECT COALESCE(SUM(t.amount::numeric),0)::text AS earned FROM wallet_transactions t WHERE t.user_id=$1 AND t.source='referralReward' AND t.entry_type='reward' AND NOT EXISTS(SELECT 1 FROM wallet_transactions r WHERE r.reversal_of=t.id)",[userId])).rows[0];
    const policy = (await this.db.query("SELECT enabled FROM reward_policies WHERE source='referralReward' ORDER BY updated_at DESC LIMIT 1")).rows[0];
    return { userId, referralCode:user.referral_code, invitedCount:number(counts.invited),pendingCount:number(counts.pending),qualifiedCount:number(counts.qualified),
      earnedCoins:number(amount.earned),status:this.env.rewardsEnabled&&policy?.enabled&&user.status==='active'?'active':'unavailable',referralUrl:null,updatedAt:iso(new Date()) };
  }
  async qualify(referralId:string, actor:Actor, key:string, reason:string){
    ensure(actor.role==='admin'||actor.role==='reviewer','restricted',403);
    return this.db.transaction(tx=>idempotent(tx,this.env,`admin:${actor.id}`,'referral.qualify',key,{referralId,reason},async()=>{
      const ref=(await tx.query('SELECT * FROM referrals WHERE id=$1',[referralId])).rows[0];ensure(ref,'not_found',404);
      await tx.query('SELECT user_id FROM wallets WHERE user_id=ANY($1::uuid[]) ORDER BY user_id FOR UPDATE',[[ref.inviter_id,ref.invitee_id]]);
      const referral=(await tx.query('SELECT * FROM referrals WHERE id=$1 FOR UPDATE',[referralId])).rows[0];
      if(referral.status==='rewarded')return {referralId,status:'rewarded'};
      ensure(referral.status==='pending'||referral.status==='qualified','conflict',409);
      const policy=(await tx.query("SELECT * FROM reward_policies WHERE source='referralReward' AND enabled ORDER BY updated_at DESC LIMIT 1")).rows[0];ensure(policy&&this.env.rewardsEnabled,'unavailable',503);
      const invitee=(await tx.query('SELECT * FROM users WHERE id=$1',[referral.invitee_id])).rows[0];
      ensure(invitee.status==='active'&&invitee.country_verified_at&&policy.countries.includes(invitee.country_code),'restricted',403);
      const now=await dbNow(tx);
      ensure(now.getTime()-new Date(invitee.created_at).getTime()>=policy.minimum_account_age_seconds*1000,'restricted',403);
      const eligible=(await tx.query("SELECT count(*)::int AS total FROM reward_events e WHERE e.user_id=$1 AND e.source IN ('adReward','offerReward','promotionReward') AND e.status IN ('approved','reconciled') AND e.provider_event_ref IS NOT NULL",[invitee.id])).rows[0].total;
      ensure(eligible>=policy.qualifying_events,'restricted',403);
      const risk=await tx.query("SELECT 1 FROM risk_flags WHERE user_id=ANY($1::uuid[]) AND active AND (blocking OR (code='shared_signal' AND $2)) LIMIT 1",[[referral.invitee_id,referral.inviter_id],policy.block_shared_risk]);
      ensure(!risk.rowCount,'restricted',403);
      await tx.query("UPDATE referrals SET status='qualified',qualification_reason=$2,qualified_at=now(),updated_at=now() WHERE id=$1",[referralId,reason]);
      let event=(await tx.query('SELECT id FROM reward_events WHERE referral_id=$1',[referralId])).rows[0];
      if(!event){
        event={id:randomUUID()};
        await tx.query(`INSERT INTO reward_events(id,user_id,source,provider_id,provider_event_id,target_id,quoted_coins,policy_id,policy_version,referral_id,status,idempotency_key,metadata)
          VALUES($1,$2,'referralReward','server-referral',$3,$4,$5,$6,$7,$8,'received',$9,$10)`,
          [event.id,referral.inviter_id,`referral:${referral.id}`,referral.id,policy.reward_coins,policy.id,policy.version,referral.id,`referral:${referral.id}`,{trace:referral.id}]);
        await tx.query("UPDATE reward_events SET status='validating' WHERE id=$1",[event.id]);
        await tx.query("UPDATE reward_events SET status='pending' WHERE id=$1",[event.id]);
      }
      await audit(tx,actor,referral.inviter_id,'referral.qualify','referral',referral.id,reason,{inviteeId:referral.invitee_id,verifiedEvents:eligible});
      const reward=await this.wallet.approveRewardIn(tx,event.id,{kind:'system',id:'referral-policy',requestId:actor.requestId},'Server qualification policy satisfied.');
      return {referralId,status:'rewarded',reward};
    }));
  }
}
