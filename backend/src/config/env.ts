import { z } from 'zod';

export type EnvironmentName = 'development' | 'test' | 'production';
export type RateAction = 'auth' | 'read' | 'reward' | 'offerStart' | 'withdrawal' | 'referral' | 'provider' | 'admin';
export interface RateRule { limit: number; seconds: number }

const rules: Record<RateAction, RateRule> = {
  auth: { limit: 10, seconds: 60 }, read: { limit: 240, seconds: 60 }, reward: { limit: 30, seconds: 60 },
  offerStart: { limit: 15, seconds: 60 }, withdrawal: { limit: 3, seconds: 900 }, referral: { limit: 5, seconds: 3600 },
  provider: { limit: 240, seconds: 60 }, admin: { limit: 60, seconds: 60 }
};
const text = z.string().min(1).max(4096);
const bool = z.enum(['true', 'false']).transform(value => value === 'true');
const integer = (min: number, max: number) => z.coerce.number().int().min(min).max(max);
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_URL: text,
  MIGRATION_DATABASE_URL: text.optional(),
  DB_SCHEMA: z.string().regex(/^[a-z][a-z0-9_]{0,40}$/).default('public'),
  DB_SSL: bool.default(false),
  PORT: integer(1, 65535).default(8080),
  API_VERSION: z.string().regex(/^v[1-9][0-9]{0,3}$/).default('v1'),
  JWT_MODE: z.enum(['jwks', 'development_hmac']).default('jwks'),
  JWT_ISSUER: text,
  JWT_AUDIENCE: text,
  JWT_JWKS_URL: text.optional(),
  JWT_DEV_SECRET: z.string().optional(),
  JWT_MAX_TTL_SECONDS: integer(60, 604800).default(86400),
  RISK_HASH_KEY: text,
  PROVIDER_HMAC_KEYS_JSON: z.string().default('{}'),
  PROVIDER_REPLAY_SECONDS: integer(30, 600).default(300),
  ALLOW_ACCOUNT_REGISTRATION: bool.default(false),
  REWARDS_ENABLED: bool.default(false),
  CORS_ORIGINS: z.string().default(''),
  TRUST_PROXY_CIDRS: z.string().default(''),
  TRACKING_ORIGINS: z.string().default(''),
  RATE_LIMITS_JSON: z.string().default('{}'),
  IDEMPOTENCY_TTL_HOURS: integer(1, 8760).default(720),
  MAX_REWARD_COINS: z.string().regex(/^[1-9][0-9]{0,15}$/).default('1000000'),
  DEFAULT_MIN_WITHDRAWAL: z.string().regex(/^[1-9][0-9]{0,15}$/).default('1000'),
  DEFAULT_WITHDRAWAL_FEE_MINOR: z.string().regex(/^(0|[1-9][0-9]{0,15})$/).default('0'),
  LOG_REQUESTS: bool.default(true)
});
function secret(value: string | undefined): string {
  if (!value || Buffer.byteLength(value) < 32 || new Set(value).size < 8) throw new Error('Required secret is missing or weak.');
  return value;
}
function originList(value: string, production: boolean): ReadonlySet<string> {
  const entries = value.split(',').map(item => item.trim()).filter(Boolean);
  const result = new Set<string>();
  for (const entry of entries) {
    const uri = new URL(entry);
    if (uri.username || uri.password || uri.search || uri.hash || uri.pathname !== '/' ||
        (uri.protocol !== 'https:' && !(uri.protocol === 'http:' && !production && ['localhost', '127.0.0.1'].includes(uri.hostname)))) throw new Error('Invalid origin configuration.');
    result.add(uri.origin);
  }
  return result;
}

export class Environment {
  readonly name: EnvironmentName;
  readonly port: number;
  readonly apiVersion: string;
  readonly schema: string;
  readonly databaseSsl: boolean;
  readonly jwtMode: 'jwks' | 'development_hmac';
  readonly jwtIssuer: string;
  readonly jwtAudience: string;
  readonly jwksUrl?: URL;
  readonly maxTokenTtl: number;
  readonly replaySeconds: number;
  readonly registrationEnabled: boolean;
  readonly rewardsEnabled: boolean;
  readonly corsOrigins: ReadonlySet<string>;
  readonly trackingOrigins: ReadonlySet<string>;
  readonly trustedProxies: readonly string[];
  readonly rates: Readonly<Record<RateAction, RateRule>>;
  readonly idempotencyHours: number;
  readonly maxReward: bigint;
  readonly minimumWithdrawal: bigint;
  readonly withdrawalFeeMinor: bigint;
  readonly logRequests: boolean;
  #databaseUrl: string;
  #migrationUrl: string;
  #jwtSecret?: string;
  #riskSecret: string;
  #providerSecrets: ReadonlyMap<string, string>;

  constructor(input: NodeJS.ProcessEnv) {
    const value = schema.parse(input);
    const production = value.NODE_ENV === 'production';
    const database = new URL(value.DATABASE_URL);
    if (!['postgres:', 'postgresql:'].includes(database.protocol)) throw new Error('Invalid database configuration.');
    if (production && (!value.DB_SSL || value.JWT_MODE !== 'jwks')) throw new Error('Production requires database TLS and asymmetric JWT verification.');
    if (database.searchParams.has('sslmode') || database.searchParams.has('sslcert') || database.searchParams.has('sslkey')) throw new Error('Configure database TLS explicitly, not by URL overrides.');
    if (production && database.searchParams.has('host')) throw new Error('Production database host overrides are disabled.');
    const issuer = new URL(value.JWT_ISSUER);
    if (issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.search || issuer.hash) throw new Error('Invalid JWT issuer.');
    let jwks: URL | undefined;
    if (value.JWT_MODE === 'jwks') {
      if (!value.JWT_JWKS_URL) throw new Error('A trusted JWKS endpoint is required.');
      jwks = new URL(value.JWT_JWKS_URL);
      if (jwks.protocol !== 'https:' || jwks.username || jwks.password || jwks.hash) throw new Error('JWKS must use HTTPS.');
    }
    const providerInput = z.record(z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/), z.string()).parse(JSON.parse(value.PROVIDER_HMAC_KEYS_JSON));
    const providerSecrets = new Map<string, string>();
    for (const [key, token] of Object.entries(providerInput)) providerSecrets.set(key, secret(token));
    const rateInput = z.record(z.enum(['auth', 'read', 'reward', 'offerStart', 'withdrawal', 'referral', 'provider', 'admin']),
      z.object({ limit: z.number().int().min(1).max(100000), seconds: z.number().int().min(1).max(86400) }).strict()).parse(JSON.parse(value.RATE_LIMITS_JSON));
    const proxies = value.TRUST_PROXY_CIDRS.split(',').map(item => item.trim()).filter(Boolean);
    if (proxies.some(item => !/^[0-9a-fA-F:.]+(?:\/[0-9]{1,3})?$/.test(item))) throw new Error('Trusted proxies must be explicit addresses/CIDRs.');
    this.name = value.NODE_ENV; this.port = value.PORT; this.apiVersion = value.API_VERSION; this.schema = value.DB_SCHEMA;
    this.databaseSsl = value.DB_SSL; this.jwtMode = value.JWT_MODE; this.jwtIssuer = value.JWT_ISSUER; this.jwtAudience = value.JWT_AUDIENCE;
    this.jwksUrl = jwks; this.maxTokenTtl = value.JWT_MAX_TTL_SECONDS; this.replaySeconds = value.PROVIDER_REPLAY_SECONDS;
    this.registrationEnabled = value.ALLOW_ACCOUNT_REGISTRATION; this.rewardsEnabled = value.REWARDS_ENABLED;
    this.corsOrigins = originList(value.CORS_ORIGINS, production); this.trackingOrigins = originList(value.TRACKING_ORIGINS, true);
    this.trustedProxies = Object.freeze(proxies); this.rates = Object.freeze(Object.assign({}, rules, rateInput));
    this.idempotencyHours = value.IDEMPOTENCY_TTL_HOURS; this.maxReward = BigInt(value.MAX_REWARD_COINS);
    this.minimumWithdrawal = BigInt(value.DEFAULT_MIN_WITHDRAWAL); this.withdrawalFeeMinor = BigInt(value.DEFAULT_WITHDRAWAL_FEE_MINOR);
    if ([this.maxReward, this.minimumWithdrawal, this.withdrawalFeeMinor].some(amount => amount > 9007199254740991n)) throw new Error('Policy exceeds integer safety limits.');
    this.logRequests = value.LOG_REQUESTS;
    this.#databaseUrl = value.DATABASE_URL; this.#migrationUrl = value.MIGRATION_DATABASE_URL ?? value.DATABASE_URL;
    this.#jwtSecret = value.JWT_MODE === 'development_hmac' ? secret(value.JWT_DEV_SECRET) : undefined;
    this.#riskSecret = secret(value.RISK_HASH_KEY); this.#providerSecrets = providerSecrets;
  }
  databaseUrl(migration = false): string { return migration ? this.#migrationUrl : this.#databaseUrl; }
  jwtSecret(): Uint8Array { if (!this.#jwtSecret) throw new Error('Development signing is unavailable.'); return new TextEncoder().encode(this.#jwtSecret); }
  riskSecret(): string { return this.#riskSecret; }
  providerSecret(reference: string): string | undefined { return this.#providerSecrets.get(reference); }
  toJSON() { return { environment: this.name, apiVersion: this.apiVersion, port: this.port, rewardsEnabled: this.rewardsEnabled, credentials: 'redacted' }; }
}

export function loadEnv(input: NodeJS.ProcessEnv = process.env): Environment {
  try { return new Environment(input); } catch { throw new Error('Invalid backend environment; credentials have been redacted.'); }
}
