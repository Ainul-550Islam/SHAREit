import type { Database, Tx } from '../db/database.js';
import type { Environment } from '../config/env.js';

// Configuration only: no users, funded wallets, completed offers or payouts.
export async function installDisabledPolicies(db:Database,env:Environment):Promise<void>{
  await db.transaction(async(tx:Tx)=>{
    const existing=(await tx.query('SELECT id FROM withdrawal_policies LIMIT 1')).rows[0];
    if(!existing){
      const row=(await tx.query(`INSERT INTO withdrawal_policies(active,minimum_coins,maximum_coins,coin_units,minor_units,currency,scale)
        VALUES(false,$1,$2,1000,100,'BDT',2) RETURNING id`,[env.minimumWithdrawal.toString(),'1000000000'])).rows[0];
      for(const method of ['bkash','nagad','rocket','paypal','bank'])await tx.query('INSERT INTO payout_methods(policy_id,method,enabled,fee_minor) VALUES($1,$2,false,$3)',[row.id,method,env.withdrawalFeeMinor.toString()]);
    }
    const daily=(await tx.query(`INSERT INTO reward_policies(source,policy_key,provider_id,reward_coins,enabled,auto_approve,daily_limit,countries)
      VALUES('dailyReward','daily','server-daily',0,false,false,1,'{}') ON CONFLICT(policy_key) DO NOTHING RETURNING id`)).rows[0];
    if(daily)for(let day=1;day<=7;day+=1)await tx.query('INSERT INTO daily_reward_steps(policy_id,day,reward_coins) VALUES($1,$2,0)',[daily.id,day]);
    await tx.query(`INSERT INTO reward_policies(source,policy_key,provider_id,reward_coins,enabled,auto_approve,daily_limit,countries)
      VALUES('referralReward','referral','server-referral',0,false,false,1,'{}') ON CONFLICT(policy_key) DO NOTHING`);
  });
}
