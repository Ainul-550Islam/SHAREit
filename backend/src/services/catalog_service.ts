import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Environment } from '../config/env.js';
import { Database, type Actor, audit, canonical, hash, idempotent, dbNow } from '../db/database.js';
import { ensure, AppError } from '../domain/errors.js';
import { iso, money, number, type PageQuery } from '../domain/validation.js';
import { offerDto, offerStartDto, promotionDto } from '../domain/mobile_dto.js';
import type { WalletService } from './wallet_service.js';

export class CatalogService {
  constructor(readonly db: Database, readonly env: Environment, readonly wallet: WalletService) {}
  private fingerprint(query: PageQuery, userId: string, domain: string): string {
    return hash(canonical({ userId,domain,pageSize:query.pageSize,search:query.search,category:query.category ?? null,sort:query.sort,
      platform:query.platform ?? null,country:query.country ?? null,minimumReward:query.minimumReward ?? null,maximumReward:query.maximumReward ?? null }));
  }
  private cursor(page: number, fingerprint: string, revision: string): string {
    const body = Buffer.from(JSON.stringify({ page, fingerprint, revision })).toString('base64url');
    return `${body}.${createHmac('sha256',this.env.riskSecret()).update(body).digest('base64url')}`;
  }
  private validateCursor(value: string | undefined, page: number, fingerprint: string, revision: string) {
    if (!value) return;
    try {
      const [body, signature, extra] = value.split('.'); ensure(body && signature && !extra);
      const expected = createHmac('sha256',this.env.riskSecret()).update(body).digest(); const actual = Buffer.from(signature,'base64url');
      ensure(actual.length === expected.length && timingSafeEqual(actual,expected));
      const parsed = JSON.parse(Buffer.from(body,'base64url').toString('utf8'));
      ensure(parsed.page === page && parsed.fingerprint === fingerprint);
      ensure(parsed.revision === revision, 'policy_changed',409);
    } catch (error) { if (error instanceof AppError) throw error; throw new AppError('invalid_request'); }
  }
  page<T>(items: T[], total: number, query: PageQuery, userId: string, domain: string, revision = 'stable') {
    const fingerprint = this.fingerprint(query,userId,domain); this.validateCursor(query.cursor,query.page,fingerprint,revision);
    const more = query.page * query.pageSize < total;
    return { items, page: { page: query.page, pageSize: query.pageSize, total, hasNext: more,
      nextCursor: more ? this.cursor(query.page+1,fingerprint,revision) : null,
      previousCursor: query.page > 1 ? this.cursor(query.page-1,fingerprint,revision) : null } };
  }

  async offers(userId: string, query: PageQuery) {
    return this.db.transaction(async tx => {
      const user = (await tx.query('SELECT * FROM users WHERE id=$1', [userId])).rows[0]; ensure(user, 'not_found',404);
      const revision = String((await tx.query('SELECT revision FROM system_revision WHERE id=true')).rows[0].revision);
      const params: unknown[] = [userId,user.country_code,this.env.name === 'production'];
      const clauses = ["($2::text IS NOT NULL AND $2=ANY(o.countries))", "(NOT $3::boolean OR NOT o.development_only)"];
      if (query.country) { params.push(query.country); clauses.push(`$${params.length}=$2`); }
      if (query.category) { params.push(query.category); clauses.push(`o.category=$${params.length}`); }
      if (query.platform) { params.push(query.platform); clauses.push(`$${params.length}=ANY(o.platforms)`); }
      if (query.minimumReward !== undefined) { params.push(query.minimumReward.toString()); clauses.push(`o.reward_coins >= $${params.length}::bigint`); }
      if (query.maximumReward !== undefined) { params.push(query.maximumReward.toString()); clauses.push(`o.reward_coins <= $${params.length}::bigint`); }
      if (query.search) { params.push(query.search); clauses.push(`strpos(lower(o.title || ' ' || o.description || ' ' || o.publisher),lower($${params.length})) > 0`); }
      const where = clauses.join(' AND ');
      const total = number((await tx.query(`SELECT count(*)::text AS total FROM offers o WHERE ${where}`,params)).rows[0].total);
      const order = { recommended: 'o.featured DESC,o.sort_priority,o.id', rewardHigh: 'o.reward_coins DESC,o.id', rewardLow: 'o.reward_coins,o.id', timeShort: 'o.estimated_minutes,o.id' }[query.sort];
      params.push(query.pageSize,(query.page-1)*query.pageSize);
      const rows = (await tx.query(`SELECT o.*,e.transaction_id AS reward_transaction_id,
        CASE WHEN e.status IN ('approved','reconciled','reversed') THEN 'completed' WHEN e.status='rejected' THEN 'rejected'
        WHEN o.expires_at<=now() THEN 'expired' WHEN NOT p.enabled OR NOT rp.enabled OR o.starts_at>now() OR o.status<>'available' THEN 'unavailable'
        WHEN e.id IS NOT NULL THEN 'pending' WHEN s.id IS NOT NULL THEN 'started' ELSE 'available' END AS effective_status
        FROM offers o JOIN providers p ON p.id=o.provider_id JOIN reward_policies rp ON rp.id=o.policy_id
        LEFT JOIN offer_starts s ON s.offer_id=o.id AND s.user_id=$1 LEFT JOIN reward_events e ON e.offer_start_id=s.id
        WHERE ${where} ORDER BY ${order} LIMIT $${params.length-1} OFFSET $${params.length}`,params)).rows;
      return this.page(rows.map(offerDto),total,query,userId,'offers',revision);
    });
  }
  async offer(userId: string, id: string) {
    const row = (await this.db.query(`SELECT o.*,e.transaction_id AS reward_transaction_id,
      CASE WHEN e.status IN ('approved','reconciled','reversed') THEN 'completed' WHEN e.status='rejected' THEN 'rejected'
      WHEN o.expires_at<=now() THEN 'expired' WHEN o.status<>'available' OR NOT p.enabled OR NOT rp.enabled OR o.starts_at>now() THEN 'unavailable'
      WHEN e.id IS NOT NULL THEN 'pending' WHEN s.id IS NOT NULL THEN 'started' ELSE 'available' END AS effective_status
      FROM offers o JOIN users u ON u.id=$1 JOIN providers p ON p.id=o.provider_id JOIN reward_policies rp ON rp.id=o.policy_id
      LEFT JOIN offer_starts s ON s.offer_id=o.id AND s.user_id=$1 LEFT JOIN reward_events e ON e.offer_start_id=s.id
      WHERE o.id=$2 AND u.country_code=ANY(o.countries) AND (NOT $3::boolean OR NOT o.development_only)`, [userId,id,this.env.name === 'production'])).rows[0];
    ensure(row, 'not_found',404); return offerDto(row);
  }

  async startOffer(userId: string, offerId: string, key: string, actor: Actor) {
    return this.db.transaction(tx => idempotent(tx,this.env,`user:${userId}`,'offer.start',key,{ offerId },async () => {
      const user = await this.wallet.lockWallet(tx,userId);
      const previous = (await tx.query('SELECT * FROM offer_starts WHERE user_id=$1 AND offer_id=$2', [userId,offerId])).rows[0];
      if (previous) return offerStartDto(previous);
      const offer = (await tx.query('SELECT o.*,p.enabled AS provider_enabled,p.secret_ref,r.enabled AS policy_enabled,r.version AS policy_version FROM offers o JOIN providers p ON p.id=o.provider_id JOIN reward_policies r ON r.id=o.policy_id WHERE o.id=$1 FOR SHARE OF o', [offerId])).rows[0];
      ensure(offer, 'not_found',404); const now = await dbNow(tx);
      ensure(this.env.rewardsEnabled && offer.status === 'available' && offer.provider_enabled && offer.policy_enabled && this.env.providerSecret(offer.secret_ref ?? '') && now>=offer.starts_at && now<offer.expires_at, 'expired_offer',409);
      ensure(user.country_verified_at && offer.countries.includes(user.country_code) && (this.env.name !== 'production' || !offer.development_only), 'restricted',403);
      const row = (await tx.query(`INSERT INTO offer_starts(user_id,offer_id,provider_id,quoted_coins,policy_id,policy_version,claim_key,idempotency_key,expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`, [userId,offerId,offer.provider_id,offer.reward_coins,offer.policy_id,offer.policy_version,`claim:${crypto.randomUUID()}`,key,offer.expires_at])).rows[0];
      await audit(tx,actor,userId,'offer.start','offer_start',row.id,'Tracking start created. No installation or reward is inferred.');
      return offerStartDto(row);
    }));
  }
  async launchGrant(userId: string, startId: string, platform: string) {
    const row = (await this.db.query(`SELECT s.*,o.platforms,o.tracking_url,o.install_url,o.destination_url,p.tracking_parameter,p.enabled AS provider_enabled
      FROM offer_starts s JOIN offers o ON o.id=s.offer_id JOIN providers p ON p.id=s.provider_id WHERE s.id=$1 AND s.user_id=$2`, [startId,userId])).rows[0];
    ensure(row, 'not_found',404); ensure(row.platforms.includes(platform) && row.provider_enabled && new Date(row.expires_at)>new Date() && !['completed','rejected'].includes(row.status), 'expired_offer',409);
    const value = row.tracking_url ?? row.install_url ?? row.destination_url; ensure(value, 'unavailable',503);
    const url = new URL(value); ensure(this.env.trackingOrigins.has(url.origin), 'unavailable',503);
    url.searchParams.set(row.tracking_parameter,row.id);
    const now = new Date(); const expires = new Date(Math.min(now.getTime()+600000,new Date(row.expires_at).getTime()));
    return { startId: row.id, offerId: row.offer_id, userId, platform, launchUrl: url.toString(), issuedAt: iso(now), expiresAt: iso(expires) };
  }
  async promotions(userId: string, query: PageQuery) {
    return this.db.transaction(async tx => {
      const revision = String((await tx.query('SELECT revision FROM system_revision WHERE id=true')).rows[0].revision);
      const user = (await tx.query('SELECT country_code FROM users WHERE id=$1', [userId])).rows[0];
      const total = number((await tx.query('SELECT count(*)::text AS total FROM promotions WHERE $1=ANY(countries) AND (NOT $2::boolean OR NOT development_only)', [user.country_code,this.env.name==='production'])).rows[0].total);
      const rows = (await tx.query("SELECT *,CASE WHEN ends_at<=now() THEN 'expired' ELSE status END AS effective_status FROM promotions WHERE $1=ANY(countries) AND (NOT $2::boolean OR NOT development_only) ORDER BY starts_at DESC,id LIMIT $3 OFFSET $4",
        [user.country_code,this.env.name==='production',query.pageSize,(query.page-1)*query.pageSize])).rows;
      return this.page(rows.map(promotionDto),total,query,userId,'promotions',revision);
    });
  }
}
