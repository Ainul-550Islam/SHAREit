import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Environment, RateAction } from '../config/env.js';
import type { Database } from '../db/database.js';
import { ensure } from '../domain/errors.js';
import { id, uuid, text, coin, parse, parsePage, signup, rewardClaim, sessionRequest, withdrawalIntent, offerStartRequest, reason, checkBodyUser } from '../domain/validation.js';
import type { AuthService, Principal } from '../services/auth_service.js';
import type { WalletService } from '../services/wallet_service.js';
import type { RewardService } from '../services/reward_service.js';
import type { CatalogService } from '../services/catalog_service.js';
import type { ProviderService } from '../services/provider_service.js';
import type { ReferralService } from '../services/referral_service.js';
import type { AdminService } from '../services/admin_service.js';
import { RateLimiter, requestKey } from './security.js';

export interface Services { env:Environment; db:Database; auth:AuthService; wallet:WalletService; rewards:RewardService; catalog:CatalogService; providers:ProviderService; referrals:ReferralService; admin:AdminService; rates:RateLimiter }
function param(request:FastifyRequest,name:string):string{return parse(uuid,(request.params as Record<string,unknown>)[name]);}
export function registerRoutes(app:FastifyInstance,s:Services){
  const base=`/api/${s.env.apiVersion}`;
  const envelope=async(userId:string,data:unknown)=>({userId,serverTime:new Date().toISOString(),version:'api-v1',data});
  type Handler=(request:FastifyRequest,principal:Principal)=>Promise<unknown>;
  function route(method:'GET'|'POST',path:string,rate:RateAction,handler:Handler,admin=false,write=method==='POST'){
    app.route({method,url:base+path,handler:async(request)=>{
      const principal=await s.auth.authenticate(request.headers.authorization,request.id,request.ip,write);
      await s.rates.consume(`user:${principal.userId}`,rate);
      if(admin)ensure(principal.role==='admin'||principal.role==='reviewer','restricted',403);
      return envelope(principal.userId,await handler(request,principal));
    }});
  }
  app.get('/',async()=>({service:'ShareBondhu backend foundation',api:base,productionProviders:'not connected by this project'}));
  app.get(base+'/health',async()=>{await s.db.query('SELECT version FROM schema_migrations WHERE version=1');return {status:'ok',apiVersion:s.env.apiVersion};});
  app.post(base+'/auth/session',async(request)=>{
    await s.rates.consume(`ip:${request.ip}`,'auth');
    const identity=await s.auth.verify(request.headers.authorization);const input=parse(signup,request.body??{});
    const data=await s.auth.openSession(identity,input,{kind:'anonymous',requestId:request.id,ipHash:s.auth.signal(`ip:${request.ip}`)});
    return envelope(data.user.userId,data);
  });
  route('POST','/auth/logout','auth',async(_request,p)=>s.auth.logout(p),false,false);
  route('GET','/users/me','read',async(_request,p)=>s.auth.currentUser(p.userId));
  route('GET','/wallet','read',async(_request,p)=>s.wallet.getWallet(p.userId));
  route('GET','/wallet/transactions','read',async(request,p)=>{
    const query=parsePage(request.query);const data=await s.wallet.listTransactions(p.userId,query);return s.catalog.page(data.items,data.total,query,p.userId,'transactions');
  });
  route('GET','/wallet/transactions/:transactionId','read',async(request,p)=>s.wallet.getTransaction(p.userId,param(request,'transactionId')));
  route('POST','/rewards/events','reward',async(request,p)=>{const body=parse(rewardClaim,request.body);requestKey(request,body);checkBodyUser(p.userId,body.userId);return s.rewards.submitClaim(p.userId,body,p.actor);});
  route('GET','/rewards/events','read',async(request,p)=>{const query=parsePage(request.query);const data=await s.rewards.listEvents(p.userId,query);return s.catalog.page(data.items,data.total,query,p.userId,'reward-events');});
  route('GET','/rewards/events/:eventId','read',async(request,p)=>s.rewards.getEvent(p.userId,param(request,'eventId')));
  route('POST','/rewards/events/:eventId/reconcile','reward',async(request,p)=>{const body=parse(z.object({idempotencyKey:id}).strict(),request.body);requestKey(request,body);return s.rewards.reconcileEvent(p.userId,param(request,'eventId'),p.actor,body.idempotencyKey);});
  route('POST','/rewards/sessions','reward',async(request,p)=>{const body=parse(sessionRequest,request.body);requestKey(request,body);return s.rewards.createSession(p.userId,body,p.actor);});
  route('GET','/rewards/sessions/status','read',async(request,p)=>{
    const query=parse(z.object({sessionId:uuid.optional(),requestKey:id.optional()}).strict().refine(value=>Boolean(value.sessionId)!==Boolean(value.requestKey)),request.query);
    return s.rewards.sessionStatus(p.userId,query);
  });
  route('GET','/rewards/daily/configuration','read',async(_request,p)=>s.rewards.dailyConfiguration(p.userId));
  route('GET','/ads/configuration','read',async(_request,p)=>s.rewards.adConfiguration(p.userId));
  route('GET','/offers','read',async(request,p)=>s.catalog.offers(p.userId,parsePage(request.query)));
  route('GET','/offers/:offerId','read',async(request,p)=>s.catalog.offer(p.userId,param(request,'offerId')));
  route('GET','/offers/:offerId/status','read',async(request,p)=>s.catalog.offer(p.userId,param(request,'offerId')));
  route('POST','/offers/:offerId/start','offerStart',async(request,p)=>{const body=parse(offerStartRequest,request.body);requestKey(request,body);const offer=param(request,'offerId');ensure(body.offerId===offer);return s.catalog.startOffer(p.userId,offer,body.idempotencyKey,p.actor);});
  route('GET','/offers/starts/:startId/launch','read',async(request,p)=>{
    const query=parse(z.object({platform:z.enum(['android','ios'])}).strict(),request.query);return s.catalog.launchGrant(p.userId,param(request,'startId'),query.platform);
  });
  route('GET','/promotions','read',async(request,p)=>s.catalog.promotions(p.userId,parsePage(request.query)));
  route('POST','/promotions/:promotionId/events','reward',async(request,p)=>{
    const body=parse(z.object({idempotencyKey:id}).strict(),request.body);requestKey(request,body);
    return s.rewards.createSession(p.userId,{source:'promotionReward',targetId:param(request,'promotionId'),idempotencyKey:body.idempotencyKey},p.actor);
  });
  route('GET','/referrals','read',async(_request,p)=>s.referrals.summary(p.userId));
  route('GET','/users/me/referral','read',async(_request,p)=>s.referrals.summary(p.userId));
  route('GET','/withdrawals/policy','read',async(_request,p)=>s.wallet.withdrawalPolicy(p.userId));
  route('POST','/withdrawals','withdrawal',async(request,p)=>{const body=parse(withdrawalIntent,request.body);requestKey(request,body);checkBodyUser(p.userId,body.userId);return s.wallet.reserveWithdrawal(p.userId,body,p.actor);});
  route('GET','/withdrawals','read',async(request,p)=>{const query=parsePage(request.query);const data=await s.wallet.listWithdrawals(p.userId,query);return s.catalog.page(data.items,data.total,query,p.userId,'withdrawals');});
  route('GET','/withdrawals/by-key/:key','read',async(request,p)=>s.wallet.getWithdrawal(p.userId,{key:parse(id,(request.params as Record<string,unknown>).key)}));
  route('GET','/withdrawals/:withdrawalId','read',async(request,p)=>s.wallet.getWithdrawal(p.userId,{id:param(request,'withdrawalId')}));

  app.post(base+'/providers/:providerId/events',async(request)=>{
    const providerId=parse(id,(request.params as Record<string,unknown>).providerId);await s.rates.consume(`provider:${providerId}:${request.ip}`,'provider');
    const signature=request.headers['x-provider-signature'];const timestamp=request.headers['x-provider-timestamp'];
    ensure(typeof signature==='string'&&typeof timestamp==='string','invalid_provider_signature',403);
    const raw=(request as FastifyRequest & {rawBody?:Buffer}).rawBody;ensure(raw,'invalid_request');
    return {accepted:true,data:await s.providers.ingest(providerId,raw,timestamp,signature,request.id)};
  });
  route('GET','/admin/users/:userId','admin',async(request)=>s.auth.currentUser(param(request,'userId')),true);
  route('GET','/admin/users/:userId/ledger','admin',async(request)=>{const target=param(request,'userId');const query=parsePage(request.query);const data=await s.wallet.listTransactions(target,query);return s.catalog.page(data.items,data.total,query,target,'admin-ledger');},true);
  route('POST','/admin/users/:userId/restrict','admin',async(request,p)=>{const body=request.body as {idempotencyKey:string};requestKey(request,body);return s.admin.account(param(request,'userId'),request.body,p.actor);},true);
  route('POST','/admin/users/:userId/risk','admin',async(request,p)=>{const body=request.body as {idempotencyKey:string};requestKey(request,body);return s.admin.risk(param(request,'userId'),request.body,p.actor);},true);
  route('POST','/admin/users/:userId/adjustments','admin',async(request,p)=>{
    const body=parse(z.object({amount:coin.refine(value=>value>0),direction:z.enum(['credit','debit']),reason:text(1000),idempotencyKey:id}).strict(),request.body);requestKey(request,body);
    return s.wallet.adjust(param(request,'userId'),BigInt(body.amount),body.direction,p.actor,body.idempotencyKey,body.reason);
  },true);
  route('POST','/admin/users/:userId/reconcile','admin',async(request,p)=>{const body=parse(reason,request.body);requestKey(request,body);return s.wallet.reconcile(param(request,'userId'),p.actor);},true);
  route('POST','/admin/rewards/:eventId/approve','admin',async(request,p)=>{const body=parse(reason,request.body);requestKey(request,body);return s.wallet.approveReward(param(request,'eventId'),p.actor,body.idempotencyKey,body.reason);},true);
  route('POST','/admin/rewards/:eventId/reject','admin',async(request,p)=>{const body=parse(reason,request.body);requestKey(request,body);return s.wallet.rejectReward(param(request,'eventId'),p.actor,body.idempotencyKey,body.reason);},true);
  route('POST','/admin/transactions/:transactionId/reverse','admin',async(request,p)=>{const body=parse(reason,request.body);requestKey(request,body);return s.wallet.reverseTransaction(param(request,'transactionId'),p.actor,body.idempotencyKey,body.reason);},true);
  route('POST','/admin/withdrawals/:withdrawalId/status','admin',async(request,p)=>{
    const body=parse(z.object({status:z.enum(['pending','approved','processing','rejected','cancelled']),reason:text(1000),idempotencyKey:id}).strict(),request.body);requestKey(request,body);
    return s.wallet.changeWithdrawal(param(request,'withdrawalId'),body.status,p.actor,body.idempotencyKey,body.reason);
  },true);
  route('POST','/admin/referrals/:referralId/qualify','admin',async(request,p)=>{const body=parse(reason,request.body);requestKey(request,body);return s.referrals.qualify(param(request,'referralId'),p.actor,body.idempotencyKey,body.reason);},true);
  for(const [path,action] of [
    ['/admin/providers',(body:unknown,p:Principal)=>s.admin.provider(body,p.actor)],
    ['/admin/reward-policies',(body:unknown,p:Principal)=>s.admin.policy(body,p.actor)],
    ['/admin/offers',(body:unknown,p:Principal)=>s.admin.offer(body,p.actor)],
    ['/admin/promotions',(body:unknown,p:Principal)=>s.admin.promotion(body,p.actor)],
    ['/admin/withdrawal-policies',(body:unknown,p:Principal)=>s.admin.withdrawalPolicy(body,p.actor)],
    ['/admin/payout-destinations',(body:unknown,p:Principal)=>s.admin.destination(body,p.actor)]
  ] as const){
    route('POST',path,'admin',async(request,p)=>{const body=request.body as {idempotencyKey:string};requestKey(request,body);return action(request.body,p);},true);
  }
  route('GET','/admin/audit','admin',async(request)=>{
    const query=parse(z.object({page:z.coerce.number().int().min(1).default(1),pageSize:z.coerce.number().int().min(1).max(100).default(20)}).strict(),request.query);
    return {items:(await s.db.query('SELECT * FROM audit_logs ORDER BY created_at DESC,id DESC LIMIT $1 OFFSET $2',[query.pageSize,(query.page-1)*query.pageSize])).rows};
  },true);
}
