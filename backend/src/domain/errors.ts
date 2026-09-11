export type ErrorCode = 'unauthenticated' | 'restricted' | 'conflict' | 'below_minimum' | 'insufficient_balance' | 'payout_unavailable' | 'policy_changed' | 'not_found' | 'rate_limited' | 'invalid_request' | 'invalid_provider_signature' | 'expired_offer' | 'cooldown' | 'daily_limit' | 'duplicate_event' | 'unavailable';

const messages: Record<ErrorCode, string> = {
  unauthenticated: 'A valid, non-revoked session is required.',
  restricted: 'This account or actor is not permitted to perform this action.',
  conflict: 'The request conflicts with an existing operation or expired request key.',
  below_minimum: 'The requested amount is below policy minimum.',
  insufficient_balance: 'Insufficient available ShareCoin.',
  payout_unavailable: 'The payout method or destination is not connected.',
  policy_changed: 'Policy or catalog changed. Refresh before continuing.',
  not_found: 'No authorized record was found.',
  rate_limited: 'Request rate limit reached.',
  invalid_request: 'The request is invalid for this operation.',
  invalid_provider_signature: 'Provider evidence could not be authenticated.',
  expired_offer: 'This offer is expired or unavailable.',
  cooldown: 'The backend cooldown has not elapsed.',
  daily_limit: 'The backend daily quota is exhausted.',
  duplicate_event: 'This provider event is already associated with another action.',
  unavailable: 'The service could not complete the operation safely.'
};

export class AppError extends Error {
  constructor(readonly code: ErrorCode, readonly status = 400) { super(messages[code]); this.name = 'AppError'; }
  toJSON() { return { code: this.code, message: this.message }; }
}
export function ensure(condition: unknown, code: ErrorCode = 'invalid_request', status = 400): asserts condition {
  if (!condition) throw new AppError(code, status);
}
export function databaseError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const code = (error as { code?: string })?.code;
  if (code === '23505' || code === '40001' || code === '40P01') return new AppError('conflict', 409);
  if (code === '23503' || code === '23514' || code === '22P02' || code === '22003') return new AppError('invalid_request');
  return new AppError('unavailable', 503);
}
