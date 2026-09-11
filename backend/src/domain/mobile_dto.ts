import type { QueryResultRow } from 'pg';
import { iso, number } from './validation.js';

export function userDto(row: QueryResultRow) {
  return { userId: row.id, displayName: row.display_name, username: row.username, status: row.status,
    createdAt: iso(row.created_at), lastActiveAt: iso(row.last_active_at), version: `user-${row.version}`,
    referralCode: row.referral_code, avatarUrl: null, features: { rewards: row.status === 'active' }, linkedMethods: [] };
}
export function rewardDto(row: QueryResultRow) {
  const approved = ['approved','reconciled','reversed'].includes(row.status);
  return { eventId: row.id, userId: row.user_id, source: row.source, provider: row.provider_id,
    providerEventId: row.provider_event_id, targetId: row.target_id, requestedCoins: number(row.quoted_coins),
    occurredAt: iso(row.client_occurred_at ?? row.created_at), status: approved ? 'approved' : row.status === 'rejected' ? 'rejected' : 'pending',
    idempotencyKey: row.idempotency_key, transactionId: approved ? row.transaction_id : null, metadata: row.metadata ?? {} };
}
export function transactionDto(row: QueryResultRow) {
  const status = row.reversed ? 'reversed' : row.entry_type === 'withdrawal_hold' && ['requested','pending','approved','processing'].includes(row.withdrawal_status) ? 'pending' : 'completed';
  return { transactionId: row.id, userId: row.user_id, amount: number(row.amount), direction: row.direction, source: row.source,
    status, description: row.description, createdAt: iso(row.created_at), completedAt: status === 'completed' ? iso(row.processed_at) : null,
    referenceId: row.reference_id, idempotencyKey: row.idempotency_key, metadata: row.metadata ?? {} };
}
export function rateDto(row: QueryResultRow) { return { coinUnits: number(row.coin_units), minorUnits: number(row.minor_units), currency: row.currency, scale: row.scale }; }
export function withdrawalDto(row: QueryResultRow) {
  return { withdrawalId: row.id, userId: row.user_id, requestedCoins: number(row.requested_coins), rate: rateDto(row),
    feeMinor: number(row.fee_minor), finalPayoutMinor: number(row.final_payout_minor), method: row.method,
    maskedDestination: row.masked_destination, status: row.status, requestedAt: iso(row.requested_at), updatedAt: iso(row.updated_at),
    serverReference: row.server_reference ?? null, rejectionReason: row.rejection_reason ?? null, idempotencyKey: row.idempotency_key };
}
export function offerDto(row: QueryResultRow) {
  return { offerId: row.id, title: row.title, shortDescription: row.short_description, description: row.description, publisher: row.publisher,
    category: row.category, rewardCoins: number(row.reward_coins), estimatedMinutes: row.estimated_minutes, platforms: row.platforms,
    countries: row.countries, status: row.effective_status ?? row.status, startsAt: iso(row.starts_at), expiresAt: iso(row.expires_at),
    provider: row.provider_id, featured: row.featured, sortPriority: row.sort_priority, iconUrl: row.icon_url ?? null,
    installUrl: row.install_url ?? null, destinationUrl: row.destination_url ?? null, trackingUrl: row.tracking_url ?? null,
    instructions: row.instructions, terms: row.terms, trackingMetadata: row.tracking_metadata,
    rewardTransactionId: row.reward_transaction_id ?? null };
}
export function offerStartDto(row: QueryResultRow) {
  return { startId: row.id, offerId: row.offer_id, userId: row.user_id, idempotencyKey: row.idempotency_key,
    status: row.status === 'pending' ? 'pending' : 'started', updatedAt: iso(row.updated_at), trackingReference: row.id };
}
export function promotionDto(row: QueryResultRow) {
  return { campaignId: row.id, title: row.title, description: row.description, advertiser: row.advertiser, cta: row.cta,
    rewardCoins: number(row.reward_coins), startsAt: iso(row.starts_at), endsAt: iso(row.ends_at), status: row.effective_status ?? row.status,
    trackingId: row.id, imageUrl: row.image_url ?? null };
}
export function sessionDto(row: QueryResultRow) {
  return { sessionId: row.id, userId: row.user_id, eventId: row.event_id, idempotencyKey: row.event_key, requestKey: row.request_key,
    source: row.source, provider: row.provider_id, targetId: row.target_id, rewardCoins: number(row.quoted_coins), issuedAt: iso(row.issued_at),
    expiresAt: iso(row.expires_at), notBefore: iso(row.not_before), availability: row.availability, usedToday: row.used_today,
    dailyLimit: row.daily_limit, providerEventId: row.provider_event_hint ?? null, launchUrl: row.launch_url ?? null };
}
