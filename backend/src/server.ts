import Fastify, { type FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv, type Environment } from './config/env.js';
import { Database } from './db/database.js';
import { AppError, databaseError } from './domain/errors.js';
import { boundedJson, RateLimiter } from './http/security.js';
import { registerRoutes, type Services } from './http/routes.js';
import { WalletService } from './services/wallet_service.js';
import { AuthService } from './services/auth_service.js';
import { RewardService } from './services/reward_service.js';
import { CatalogService } from './services/catalog_service.js';
import { ProviderService } from './services/provider_service.js';
import { ReferralService } from './services/referral_service.js';
import { AdminService } from './services/admin_service.js';

export interface BackendApplication { app: FastifyInstance; services: Services }
export function buildServer(env: Environment, database?: Database): BackendApplication {
  const db = database ?? new Database(env);
  const wallet = new WalletService(db,env);
  const rewards = new RewardService(db,env,wallet);
  const services: Services = { env,db,wallet,rewards,auth:new AuthService(db,env,wallet),catalog:new CatalogService(db,env,wallet),
    providers:new ProviderService(db,env,rewards,wallet),referrals:new ReferralService(db,env,wallet),admin:new AdminService(db,env),rates:new RateLimiter(db,env) };
  const app = Fastify({ logger: env.logRequests ? { level:'info', redact:['req.headers.authorization','req.headers.cookie','req.headers.x-provider-signature','body'] } : false,
    disableRequestLogging:true, genReqId:()=>randomUUID(), bodyLimit:65536, trustProxy:env.trustedProxies.length ? Array.from(env.trustedProxies) : false });
  app.removeContentTypeParser('application/json');
  app.addContentTypeParser('application/json',{parseAs:'buffer'},(request,body,done)=>{
    try {
      const raw=body as Buffer;
      (request as typeof request & {rawBody:Buffer}).rawBody=raw;
      done(null,boundedJson(raw));
    } catch(error){done(error as Error);}
  });
  app.addHook('onRequest',async(request,reply)=>{
    reply.header('X-Request-ID',request.id).header('Cache-Control','no-store').header('X-Content-Type-Options','nosniff');
    if(env.name==='production'&&request.protocol!=='https')throw new AppError('restricted',403);
    const origin=request.headers.origin;
    if(origin){
      if(!env.corsOrigins.has(origin))throw new AppError('restricted',403);
      reply.header('Access-Control-Allow-Origin',origin).header('Vary','Origin').header('Access-Control-Allow-Headers','Authorization,Content-Type,Idempotency-Key').header('Access-Control-Allow-Methods','GET,POST,OPTIONS');
    }
  });
  app.options('/*',async(_request,reply)=>reply.code(204).send());
  app.setErrorHandler((error,request,reply)=>{
    const safe=error instanceof AppError ? error : (error as {statusCode?:number}).statusCode===413 ? new AppError('invalid_request',413) : databaseError(error);
    request.log.warn({requestId:request.id,code:safe.code,status:safe.status},'Request rejected or failed; details redacted.');
    reply.code(safe.status).send({error:safe.toJSON(),requestId:request.id});
  });
  app.addHook('onResponse',async(request,reply)=>{
    if(env.logRequests)request.log.info({requestId:request.id,method:request.method,route:request.routeOptions.url??'unmatched',status:reply.statusCode},'Request complete.');
  });
  registerRoutes(app,services);
  app.addHook('onClose',async()=>{if(!database)await db.close();});
  return {app,services};
}

async function main(){
  const env=loadEnv();const {app}=buildServer(env);
  await app.listen({host:'0.0.0.0',port:env.port});
  const shutdown=async()=>{await app.close();process.exitCode=0;};
  process.once('SIGTERM',()=>{void shutdown();});process.once('SIGINT',()=>{void shutdown();});
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(()=>{console.error('Backend startup failed; credentials and connection details are redacted.');process.exitCode=1;});
}
