import { randomUUID } from 'node:crypto';
import type { QueryResultRow } from 'pg';
import type { Environment } from '../config/env.js';
import { Database, type Tx, type Actor, audit, hash, idempotent } from '../db/database.js';
import { AppError, ensure } from '../domain/errors.js';
import { exactQuote, iso, money, number, type WithdrawalIntent, type PageQuery, MAX_COINS } from '../domain/validation.js';
import { rateDto, rewardDto, transactionDto, withdrawalDto } from '../domain/mobile_dto.js';

interface Posting {
  id?: string; userId: string; amount: bigint; direction: 'credit' | 'debit'; entryType: string; source: string;
  referenceId: string; referenceKey: string; description: string; rewardEventId?: string; withdrawalId?: string; reversalOf?: string;
}
export class WalletService {
  constructor(readonly db: Database, readonly env: Environment) {}

  async createWallet(tx: Tx, userId: string): Promise<void> {
    await tx.query('INSERT INTO wallets(user_id) VALUES($1) ON CONFLICT DO NOTHING', [userId]);
  }
  async lockWallet(tx: Tx, userId: string, requireActive = true): Promise<QueryResultRow> {
    const wallet = (await tx.query('SELECT w.*,u.status,u.country_code,u.country_verified_at,u.created_at AS account_created FROM wallets w JOIN users u ON u.id=w.user_id WHERE w.user_id=$1 FOR UPDATE OF w', [userId])).rows[0];
    ensure(wallet, 'not_found', 404);
    if (requireActive) {
      ensure(wallet.status === 'active', 'restricted', 403);
      const flags = await tx.query('SELECT 1 FROM risk_flags WHERE user_id=$1 AND active AND blocking LIMIT 1', [userId]);
      ensure(!flags.rowCount, 'restricted', 403);
    }
    const available = (await tx.query("SELECT COALESCE(SUM(CASE direction WHEN 'credit' THEN amount::numeric ELSE -amount::numeric END),0)::text AS amount,count(*)::text AS entries FROM wallet_transactions WHERE user_id=$1", [userId])).rows[0];
    ensure(BigInt(available.amount) === BigInt(wallet.cached_available) && BigInt(available.entries) === BigInt(wallet.ledger_count), 'unavailable', 503);
    return wallet;
  }

  async getWallet(userId: string) {
    return this.db.transaction(async tx => {
      const wallet = await this.lockWallet(tx, userId, false);
      const totals = (await tx.query(`SELECT
        COALESCE(SUM(CASE direction WHEN 'credit' THEN amount::numeric ELSE -amount::numeric END),0)::text AS available,
        COALESCE(SUM(amount::numeric) FILTER (WHERE direction='credit' AND entry_type IN ('reward','admin_adjustment')),0)::text AS earned,
        COALESCE(SUM(amount::numeric) FILTER (WHERE direction='debit' AND entry_type='admin_adjustment'),0)::text AS spent
        FROM wallet_transactions WHERE user_id=$1`, [userId])).rows[0];
      const pending = (await tx.query("SELECT COALESCE(SUM(quoted_coins::numeric),0)::text AS amount,max(updated_at) AS changed FROM reward_events WHERE user_id=$1 AND status IN ('received','validating','pending')", [userId])).rows[0];
      const withdrawn = (await tx.query("SELECT COALESCE(SUM(requested_coins::numeric),0)::text AS amount,max(updated_at) AS changed FROM withdrawal_requests WHERE user_id=$1 AND status='paid'", [userId])).rows[0];
      const updated = new Date(Math.max(new Date(wallet.updated_at).getTime(), pending.changed ? new Date(pending.changed).getTime() : 0, withdrawn.changed ? new Date(withdrawn.changed).getTime() : 0));
      ensure(money(totals.available) + money(pending.amount) <= MAX_COINS, 'unavailable', 503);
      return { userId, available: number(totals.available), pending: number(pending.amount), lifetimeEarned: number(totals.earned),
        lifetimeWithdrawn: number(withdrawn.amount), lifetimeSpent: number(totals.spent), updatedAt: iso(updated),
        version: `wallet-${wallet.revision}`, unit: 'ShareCoin' };
    });
  }

  async getTransaction(userId: string, id: string) {
    const row = (await this.db.query(`SELECT t.*,EXISTS(SELECT 1 FROM wallet_transactions r WHERE r.reversal_of=t.id) AS reversed,w.status AS withdrawal_status
      FROM wallet_transactions t LEFT JOIN withdrawal_requests w ON w.id=t.withdrawal_id WHERE t.user_id=$1 AND t.id=$2`, [userId, id])).rows[0];
    ensure(row, 'not_found', 404); return transactionDto(row);
  }
  async listTransactions(userId: string, query: PageQuery) {
    const total = number((await this.db.query('SELECT count(*)::text AS total FROM wallet_transactions WHERE user_id=$1', [userId])).rows[0].total);
    const rows = (await this.db.query(`SELECT t.*,EXISTS(SELECT 1 FROM wallet_transactions r WHERE r.reversal_of=t.id) AS reversed,w.status AS withdrawal_status
      FROM wallet_transactions t LEFT JOIN withdrawal_requests w ON w.id=t.withdrawal_id WHERE t.user_id=$1
      ORDER BY t.created_at DESC,t.id DESC LIMIT $2 OFFSET $3`, [userId, query.pageSize, (query.page - 1) * query.pageSize])).rows;
    return { items: rows.map(transactionDto), total };
  }

  private async post(tx: Tx, actor: Actor, entry: Posting, reason: string): Promise<QueryResultRow> {
    const amount = money(entry.amount); ensure(amount > 0n);
    const wallet = await this.lockWallet(tx, entry.userId, false);
    if (entry.direction === 'debit') ensure(money(wallet.cached_available) >= amount, 'insufficient_balance', 409);
    const id = entry.id ?? randomUUID();
    const auditId = await audit(tx, actor, entry.userId, 'wallet.post', 'wallet_transaction', id, reason,
      { amount: amount.toString(), direction: entry.direction, source: entry.source, referenceId: entry.referenceId, entryType: entry.entryType });
    const row = (await tx.query(`INSERT INTO wallet_transactions(id,user_id,amount,direction,entry_type,source,reference_id,reference_key,idempotency_key,
      description,reward_event_id,withdrawal_id,reversal_of,audit_id,metadata)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING *`,
      [id, entry.userId, amount.toString(), entry.direction, entry.entryType, entry.source, entry.referenceId, entry.referenceKey,
        hash(`${entry.entryType}:${entry.referenceKey}`), entry.description, entry.rewardEventId ?? null, entry.withdrawalId ?? null,
        entry.reversalOf ?? null, auditId, { trace: id }])).rows[0];
    return row;
  }

  async approveReward(eventId: string, actor: Actor, key: string, reason: string) {
    ensure(actor.role === 'admin' || actor.role === 'reviewer', 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx, this.env, `admin:${actor.id}`, 'reward.approve', key, { eventId, reason }, () => this.approveRewardIn(tx, eventId, actor, reason)));
  }
  async approveRewardIn(tx: Tx, eventId: string, actor: Actor, reason: string) {
    const reference = (await tx.query('SELECT user_id FROM reward_events WHERE id=$1', [eventId])).rows[0]; ensure(reference, 'not_found', 404);
    const wallet = await this.lockWallet(tx, reference.user_id);
    const event = (await tx.query('SELECT * FROM reward_events WHERE id=$1 FOR UPDATE', [eventId])).rows[0];
    if (['approved','reconciled','reversed'].includes(event.status)) return rewardDto(event);
    ensure(event.status === 'pending' || event.status === 'validating', 'conflict', 409);
    ensure(this.env.rewardsEnabled, 'unavailable', 503);
    const policy = (await tx.query('SELECT * FROM reward_policies WHERE id=$1', [event.policy_id])).rows[0];
    ensure(policy?.enabled && String(policy.version) === String(event.policy_version), 'policy_changed', 409);
    ensure(wallet.country_verified_at && policy.countries.includes(wallet.country_code), 'restricted', 403);
    if (['adReward','offerReward','promotionReward'].includes(event.source)) {
      const evidence = (await tx.query('SELECT * FROM provider_events WHERE id=$1 AND user_id=$2 AND provider_id=$3', [event.provider_event_ref, event.user_id, event.provider_id])).rows[0];
      ensure(evidence && evidence.provider_event_id === event.provider_event_id, 'invalid_provider_signature', 403);
      ensure((event.reward_session_id && evidence.reward_session_id === event.reward_session_id) || (event.offer_start_id && evidence.offer_start_id === event.offer_start_id), 'invalid_request');
      ensure(actor.role === 'admin' || actor.role === 'reviewer' || actor.kind === 'provider' && actor.id === event.provider_id && policy.auto_approve, 'restricted', 403);
    } else if (event.source === 'dailyReward') {
      ensure(actor.kind === 'system' || actor.role === 'admin', 'restricted', 403);
      const session = (await tx.query("SELECT * FROM reward_sessions WHERE id=$1 AND user_id=$2 AND source='dailyReward'", [event.reward_session_id,event.user_id])).rows[0];
      ensure(session?.availability === 'eligible', 'invalid_request');
    } else if (event.source === 'referralReward') {
      ensure(actor.kind === 'system' || actor.role === 'admin', 'restricted', 403);
      const referral = (await tx.query("SELECT * FROM referrals WHERE id=$1 AND inviter_id=$2 AND status IN ('qualified','rewarded')", [event.referral_id,event.user_id])).rows[0];
      ensure(referral, 'invalid_request');
    } else { throw new AppError('invalid_request'); }
    const ledgerId = randomUUID();
    await tx.query("UPDATE reward_events SET status='approved',transaction_id=$2,reason=$3 WHERE id=$1", [eventId, ledgerId, reason]);
    await this.post(tx, actor, { id: ledgerId, userId: event.user_id, amount: money(event.quoted_coins), direction: 'credit', entryType: 'reward', source: event.source,
      referenceId: event.target_id, referenceKey: event.id, description: 'Backend-validated reward credit.', rewardEventId: event.id }, reason);
    if (event.offer_start_id) await tx.query("UPDATE offer_starts SET status='completed',updated_at=now() WHERE id=$1", [event.offer_start_id]);
    if (event.referral_id) await tx.query("UPDATE referrals SET status='rewarded',updated_at=now() WHERE id=$1", [event.referral_id]);
    await audit(tx, actor, event.user_id, 'reward.approve', 'reward_event', event.id, reason, { transactionId: ledgerId });
    return rewardDto((await tx.query('SELECT * FROM reward_events WHERE id=$1', [eventId])).rows[0]);
  }

  async rejectReward(eventId: string, actor: Actor, key: string, reason: string) {
    ensure(actor.role === 'admin' || actor.role === 'reviewer', 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx, this.env, `admin:${actor.id}`, 'reward.reject', key, { eventId, reason }, async () => {
      const ref = (await tx.query('SELECT user_id FROM reward_events WHERE id=$1', [eventId])).rows[0]; ensure(ref, 'not_found', 404);
      await this.lockWallet(tx, ref.user_id, false);
      const row = (await tx.query('SELECT * FROM reward_events WHERE id=$1 FOR UPDATE', [eventId])).rows[0];
      ensure(['received','validating','pending','rejected'].includes(row.status), 'conflict', 409);
      if (row.status !== 'rejected') {
        await tx.query("UPDATE reward_events SET status='rejected',reason=$2 WHERE id=$1", [eventId, reason]);
        if (row.offer_start_id) await tx.query("UPDATE offer_starts SET status='rejected',updated_at=now() WHERE id=$1", [row.offer_start_id]);
        await audit(tx, actor, ref.user_id, 'reward.reject', 'reward_event', eventId, reason);
      }
      return rewardDto((await tx.query('SELECT * FROM reward_events WHERE id=$1', [eventId])).rows[0]);
    }));
  }

  async reverseTransaction(transactionId: string, actor: Actor, key: string, reason: string) {
    ensure(actor.role === 'admin', 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx, this.env, `admin:${actor.id}`, 'wallet.reverse', key, { transactionId, reason }, async () => {
      const ref = (await tx.query('SELECT user_id FROM wallet_transactions WHERE id=$1', [transactionId])).rows[0]; ensure(ref, 'not_found', 404);
      await this.lockWallet(tx, ref.user_id, false);
      const original = (await tx.query('SELECT * FROM wallet_transactions WHERE id=$1', [transactionId])).rows[0];
      ensure(['reward','admin_adjustment'].includes(original.entry_type) && !original.reversal_of, 'invalid_request');
      const previous = (await tx.query('SELECT * FROM wallet_transactions WHERE reversal_of=$1', [transactionId])).rows[0];
      if (previous) return transactionDto(previous);
      const reversal = await this.post(tx, actor, { userId: original.user_id, amount: money(original.amount), direction: original.direction === 'credit' ? 'debit' : 'credit',
        entryType: 'reward_reversal', source: 'reversal', referenceId: original.id, referenceKey: original.id, description: 'Full reversal of an earlier ledger entry.', reversalOf: original.id }, reason);
      if (original.reward_event_id) await tx.query("UPDATE reward_events SET status='reversed',reason=$2 WHERE id=$1", [original.reward_event_id, reason]);
      await audit(tx, actor, original.user_id, 'reward.reverse', 'wallet_transaction', original.id, reason, { reversalId: reversal.id });
      return transactionDto(reversal);
    }));
  }

  async adjust(userId: string, amount: bigint, direction: 'credit' | 'debit', actor: Actor, key: string, reason: string) {
    ensure(actor.role === 'admin', 'restricted', 403); ensure(amount > 0n && amount <= this.env.maxReward);
    return this.db.transaction(tx => idempotent(tx, this.env, `admin:${actor.id}`, 'wallet.adjust', key, { userId, amount, direction, reason }, async () => {
      await this.lockWallet(tx, userId, false);
      const entry = await this.post(tx, actor, { userId, amount, direction, entryType: 'admin_adjustment', source: 'administrativeAdjustment',
        referenceId: key, referenceKey: `${actor.id}:${key}`, description: 'Audited administrative adjustment.' }, reason);
      return transactionDto(entry);
    }));
  }

  async withdrawalPolicy(userId: string) {
    return this.db.transaction(async tx => {
      const policy = (await tx.query('SELECT * FROM withdrawal_policies ORDER BY active DESC,created_at DESC LIMIT 1')).rows[0];
      ensure(policy, 'payout_unavailable', 409);
      const methods = (await tx.query(`SELECT m.*,p.enabled AS provider_enabled,p.secret_ref,d.id AS destination_id,d.masked_destination
        FROM payout_methods m LEFT JOIN providers p ON p.id=m.provider_id AND p.kind='payout'
        LEFT JOIN payout_destinations d ON d.user_id=$2 AND d.method=m.method AND d.provider_id=m.provider_id AND d.enabled
        WHERE m.policy_id=$1 ORDER BY m.method`, [policy.id,userId])).rows;
      const active = (await tx.query("SELECT id FROM withdrawal_requests WHERE user_id=$1 AND status IN ('requested','pending','approved','processing') ORDER BY requested_at", [userId])).rows;
      return { userId, version: `policy:${policy.id}:${policy.version}`, minimumCoins: number(policy.minimum_coins), rate: rateDto(policy),
        methods: methods.map(row => ({ method: row.method, enabled: policy.active && row.enabled,
          providerConnected: Boolean(policy.active && row.provider_enabled && this.env.providerSecret(row.secret_ref ?? '')),
          feeMinor: number(row.fee_minor), destinationReference: row.destination_id ?? null, maskedDestination: row.masked_destination ?? null })), activeRequestIds: active.map(row => row.id) };
    });
  }

  async reserveWithdrawal(userId: string, intent: WithdrawalIntent, actor: Actor) {
    ensure(intent.userId === userId, 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx, this.env, `user:${userId}`, 'withdrawal.request', intent.idempotencyKey, intent, async () => {
      const wallet = await this.lockWallet(tx, userId);
      const amount = money(intent.coins);
      const policy = (await tx.query('SELECT * FROM withdrawal_policies WHERE active=true FOR SHARE')).rows[0]; ensure(policy, 'payout_unavailable', 409);
      ensure(intent.policyVersion === `policy:${policy.id}:${policy.version}`, 'policy_changed', 409);
      ensure(amount >= money(policy.minimum_coins), 'below_minimum'); ensure(amount <= money(policy.maximum_coins), 'invalid_request');
      ensure(amount <= money(wallet.cached_available), 'insufficient_balance', 409);
      const active = await tx.query("SELECT 1 FROM withdrawal_requests WHERE user_id=$1 AND status IN ('requested','pending','approved','processing')", [userId]); ensure(!active.rowCount, 'conflict', 409);
      const destination = (await tx.query(`SELECT d.*,m.fee_minor,p.secret_ref,p.enabled AS provider_enabled,m.enabled AS method_enabled
        FROM payout_destinations d JOIN payout_methods m ON m.provider_id=d.provider_id AND m.method=d.method AND m.policy_id=$3
        JOIN providers p ON p.id=d.provider_id AND p.kind='payout' WHERE d.id=$1 AND d.user_id=$2 AND d.enabled`, [intent.destinationReference,userId,policy.id])).rows[0];
      ensure(destination && destination.method === intent.method && destination.method_enabled && destination.provider_enabled && this.env.providerSecret(destination.secret_ref), 'payout_unavailable', 409);
      const fee = money(destination.fee_minor); const final = exactQuote(amount, money(policy.coin_units), money(policy.minor_units), fee);
      ensure(fee === money(intent.expectedFeeMinor) && final === money(intent.expectedFinalMinor), 'policy_changed', 409);
      const id = randomUUID();
      const row = (await tx.query(`INSERT INTO withdrawal_requests(id,user_id,destination_id,policy_id,policy_version,provider_id,method,requested_coins,coin_units,minor_units,currency,scale,fee_minor,final_payout_minor,masked_destination,idempotency_key)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) RETURNING *`,
        [id,userId,destination.id,policy.id,policy.version,destination.provider_id,destination.method,amount.toString(),policy.coin_units,policy.minor_units,policy.currency,policy.scale,fee.toString(),final.toString(),destination.masked_destination,intent.idempotencyKey])).rows[0];
      await this.post(tx, actor, { userId, amount, direction: 'debit', entryType: 'withdrawal_hold', source: 'withdrawal', referenceId: id, referenceKey: id,
        description: 'Withdrawal reservation; not proof of payout.', withdrawalId: id }, 'Reserve available coins for an idempotent withdrawal.');
      await audit(tx, actor, userId, 'withdrawal.request', 'withdrawal', id, 'Withdrawal reserved; provider processing has not occurred.');
      return withdrawalDto(row);
    }));
  }

  async changeWithdrawal(id: string, status: 'pending' | 'approved' | 'processing' | 'rejected' | 'cancelled', actor: Actor, key: string, reason: string) {
    ensure(actor.role === 'admin' || actor.role === 'reviewer', 'restricted', 403);
    return this.db.transaction(tx => idempotent(tx, this.env, `admin:${actor.id}`, 'withdrawal.review', key, { id, status, reason }, () => this.transitionWithdrawalIn(tx,id,status,actor,reason)));
  }
  async transitionWithdrawalIn(tx: Tx, id: string, status: string, actor: Actor, reason: string, providerEventId?: string) {
    const ref = (await tx.query('SELECT user_id FROM withdrawal_requests WHERE id=$1', [id])).rows[0]; ensure(ref, 'not_found', 404);
    await this.lockWallet(tx, ref.user_id, false);
    const request = (await tx.query('SELECT * FROM withdrawal_requests WHERE id=$1 FOR UPDATE', [id])).rows[0];
    if (request.status === status) return withdrawalDto(request);
    ensure(!['paid','rejected','cancelled'].includes(request.status), 'conflict', 409);
    if (status === 'paid') {
      ensure(actor.kind === 'provider' && providerEventId && actor.id === request.provider_id && request.status === 'processing', 'restricted', 403);
      const proof = (await tx.query("SELECT * FROM provider_events WHERE id=$1 AND withdrawal_id=$2 AND provider_id=$3 AND outcome='paid' AND event_type='payoutResult'", [providerEventId,id,request.provider_id])).rows[0];
      ensure(proof && proof.external_reference, 'invalid_provider_signature', 403);
      await tx.query("UPDATE withdrawal_requests SET status='paid',paid_provider_event_id=$2,server_reference=$3 WHERE id=$1", [id,providerEventId,proof.external_reference]);
    } else {
      await tx.query('UPDATE withdrawal_requests SET status=$2,rejection_reason=$3 WHERE id=$1', [id,status,status === 'rejected' || status === 'cancelled' ? reason : null]);
      if (status === 'rejected' || status === 'cancelled') {
        const hold = (await tx.query("SELECT * FROM wallet_transactions WHERE withdrawal_id=$1 AND entry_type='withdrawal_hold'", [id])).rows[0]; ensure(hold, 'unavailable', 503);
        await this.post(tx, actor, { userId: request.user_id, amount: money(request.requested_coins), direction: 'credit', entryType: 'withdrawal_release',
          source: 'reversal', referenceId: id, referenceKey: id, description: 'Release of rejected/cancelled withdrawal reservation.', withdrawalId: id, reversalOf: hold.id }, reason);
      }
    }
    await audit(tx, actor, request.user_id, `withdrawal.${status}`, 'withdrawal', id, reason);
    return withdrawalDto((await tx.query('SELECT * FROM withdrawal_requests WHERE id=$1', [id])).rows[0]);
  }

  async getWithdrawal(userId: string, reference: { id?: string; key?: string }) {
    const row = (await this.db.query('SELECT * FROM withdrawal_requests WHERE user_id=$1 AND (id::text=$2 OR idempotency_key=$3)', [userId,reference.id ?? null,reference.key ?? null])).rows[0];
    ensure(row, 'not_found', 404); return withdrawalDto(row);
  }
  async listWithdrawals(userId: string, query: PageQuery) {
    const total = number((await this.db.query('SELECT count(*)::text AS total FROM withdrawal_requests WHERE user_id=$1', [userId])).rows[0].total);
    const rows = (await this.db.query('SELECT * FROM withdrawal_requests WHERE user_id=$1 ORDER BY requested_at DESC,id DESC LIMIT $2 OFFSET $3', [userId,query.pageSize,(query.page - 1) * query.pageSize])).rows;
    return { items: rows.map(withdrawalDto), total };
  }

  async reconcile(userId: string, actor: Actor) {
    ensure(actor.role === 'admin' || actor.role === 'reviewer' || actor.userId === userId, 'restricted', 403);
    return this.db.transaction(async tx => {
      const wallet = (await tx.query('SELECT * FROM wallets WHERE user_id=$1 FOR UPDATE', [userId])).rows[0]; ensure(wallet, 'not_found', 404);
      const stats = (await tx.query("SELECT COALESCE(SUM(CASE direction WHEN 'credit' THEN amount::numeric ELSE -amount::numeric END),0)::text AS available,count(*)::text AS entries FROM wallet_transactions WHERE user_id=$1", [userId])).rows[0];
      const missing = number((await tx.query("SELECT count(*)::text AS total FROM reward_events e LEFT JOIN wallet_transactions t ON t.id=e.transaction_id WHERE e.user_id=$1 AND e.status IN ('approved','reconciled','reversed') AND t.id IS NULL", [userId])).rows[0].total);
      const holds = number((await tx.query("SELECT count(*)::text AS total FROM withdrawal_requests w LEFT JOIN wallet_transactions t ON t.withdrawal_id=w.id AND t.entry_type='withdrawal_hold' WHERE w.user_id=$1 AND t.id IS NULL", [userId])).rows[0].total);
      const issues: string[] = [];
      if (BigInt(stats.available) < 0n || BigInt(stats.available) > MAX_COINS) issues.push('balance_range');
      if (BigInt(stats.available) !== BigInt(wallet.cached_available)) issues.push('wallet_ledger_mismatch');
      if (BigInt(stats.entries) !== BigInt(wallet.ledger_count)) issues.push('ledger_count_mismatch');
      if (missing) issues.push('missing_reward_transaction'); if (holds) issues.push('missing_withdrawal_hold');
      if (issues.length) await tx.query("INSERT INTO risk_flags(user_id,code,blocking,context) VALUES($1,'ledger_integrity',true,$2) ON CONFLICT(user_id,code) DO UPDATE SET active=true,blocking=true,context=EXCLUDED.context", [userId,{ issues }]);
      await audit(tx, actor, userId, 'wallet.reconcile', 'wallet', userId, issues.length ? 'Integrity discrepancy flagged; no history rewritten.' : 'Ledger and projection consistent.', { issues });
      return { userId, consistent: issues.length === 0, ledgerBalance: stats.available, cachedBalance: String(wallet.cached_available), ledgerEntries: stats.entries, issues };
    });
  }
}
