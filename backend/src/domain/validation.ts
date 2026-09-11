import { z } from 'zod';
import { AppError, ensure } from './errors.js';

export const MAX_COINS = 9007199254740991n;
export const id = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/);
export const uuid = z.uuid();
export const coin = z.number().refine(Number.isSafeInteger).min(0).max(Number(MAX_COINS));
export const positiveCoin = coin.refine(value => value > 0);
export const text = (max = 240) => z.string().min(1).refine(value => value === value.trim() && Buffer.byteLength(value) <= max && !/[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]/.test(value));
export const utcTime = z.string().datetime({ offset: false }).refine(value => { const year = new Date(value).getUTCFullYear(); return year >= 2000 && year <= 2199; });
export const metadata = z.record(z.enum(['placement','campaign','offer','providerReference','variant','platform','country','trace']), id).default({});
export const source = z.enum(['adReward','offerReward','promotionReward','referralReward','dailyReward','bonus','withdrawal','reversal','administrativeAdjustment']);
export const category = z.enum(['installApps','games','registerAndEarn','surveys','shopping','finance','education','entertainment','featured','limitedTime']);
export const platform = z.enum(['android','ios']);
export const method = z.enum(['bkash','nagad','rocket','paypal','bank']);
export const rewardClaim = z.object({ eventId: uuid, userId: uuid, source, provider: id, providerEventId: id, targetId: id,
  requestedCoins: positiveCoin, occurredAt: utcTime, status: z.literal('created'), idempotencyKey: id,
  transactionId: z.null().optional(), metadata }).strict();
export const sessionRequest = z.object({ source: z.enum(['adReward','dailyReward','promotionReward']), targetId: id, idempotencyKey: id }).strict();
export const withdrawalIntent = z.object({ userId: uuid, coins: positiveCoin, method, destinationReference: uuid, policyVersion: id,
  expectedFeeMinor: coin, expectedFinalMinor: coin, idempotencyKey: id }).strict();
export const offerStartRequest = z.object({ offerId: uuid, idempotencyKey: id }).strict();
export const signup = z.object({ displayName: text(120).optional(), username: z.string().regex(/^[A-Za-z0-9_]{3,32}$/).optional(), referralCode: id.optional(), deviceHint: id.optional() }).strict();
export const reason = z.object({ reason: text(1000), idempotencyKey: id }).strict();
export const providerPayload = z.object({ eventId: id, type: z.enum(['adCompletion','offerCompletion','promotionConversion','payoutResult']),
  rewardSessionId: uuid.optional(), offerStartId: uuid.optional(), withdrawalId: uuid.optional(),
  status: z.enum(['paid','rejected']).optional(), reference: id.optional(), platform: platform.optional() }).strict()
  .refine(value => [value.rewardSessionId, value.offerStartId, value.withdrawalId].filter(Boolean).length === 1);
export type RewardClaim = z.infer<typeof rewardClaim>;
export type WithdrawalIntent = z.infer<typeof withdrawalIntent>;
export type ProviderPayload = z.infer<typeof providerPayload>;
export interface PageQuery { page: number; pageSize: number; cursor?: string; search: string; category?: string; sort: 'recommended' | 'rewardHigh' | 'rewardLow' | 'timeShort'; platform?: 'android' | 'ios'; country?: string; minimumReward?: bigint; maximumReward?: bigint }
const querySchema = z.object({ page: z.coerce.number().int().min(1).max(1000000).default(1), pageSize: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().max(512).optional(), search: z.string().max(120).default(''), category: category.optional(), sort: z.enum(['recommended','rewardHigh','rewardLow','timeShort']).default('recommended'),
  platform: platform.optional(), country: z.string().regex(/^[A-Z]{2}$/).optional(), minimumReward: z.coerce.number().refine(Number.isSafeInteger).min(0).max(Number(MAX_COINS)).optional(),
  maximumReward: z.coerce.number().refine(Number.isSafeInteger).min(0).max(Number(MAX_COINS)).optional() }).strict();
export function parsePage(input: unknown): PageQuery {
  const raw = parse(querySchema, input);
  ensure(Buffer.byteLength(raw.search) <= 120);
  ensure(raw.minimumReward === undefined || raw.maximumReward === undefined || raw.minimumReward <= raw.maximumReward);
  return { page: raw.page, pageSize: raw.pageSize, cursor: raw.cursor, search: raw.search.trim(), category: raw.category, sort: raw.sort,
    platform: raw.platform, country: raw.country, minimumReward: raw.minimumReward === undefined ? undefined : BigInt(raw.minimumReward),
    maximumReward: raw.maximumReward === undefined ? undefined : BigInt(raw.maximumReward) };
}
export function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input); if (!result.success) throw new AppError('invalid_request'); return result.data;
}
export function money(value: string | number | bigint): bigint {
  if (typeof value === 'number') ensure(Number.isSafeInteger(value));
  let result: bigint; try { result = BigInt(value); } catch { throw new AppError('invalid_request'); }
  ensure(result >= 0n && result <= MAX_COINS); return result;
}
export function number(value: string | number | bigint): number { return Number(money(value)); }
export function iso(value: Date | string): string { return new Date(value).toISOString(); }
export function exactQuote(coins: bigint, coinUnits: bigint, minorUnits: bigint, fee: bigint): bigint {
  ensure(coinUnits > 0n && minorUnits > 0n && fee >= 0n); const gross = coins * minorUnits / coinUnits;
  ensure(gross <= MAX_COINS && gross >= fee); return gross - fee;
}
export function httpsUrl(value: string | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  ensure(value.length <= 2048);
  let uri: URL; try { uri = new URL(value); } catch { throw new AppError('invalid_request'); }
  ensure(uri.protocol === 'https:' && !uri.username && !uri.password && !uri.hash && (!uri.port || uri.port === '443') && uri.hostname.includes('.') && !uri.hostname.endsWith('.local'));
  return uri.toString();
}
export function checkBodyUser(authenticated: string, supplied: string): void { ensure(authenticated === supplied, 'restricted', 403); }
