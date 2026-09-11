# Part 7 — configured backend, authentication and reconciliation

## Verification boundary

This is implemented client architecture and a concrete HTTP adapter for the Part 5/6 contracts. No server is deployed by this code. No Google/Apple/email/phone SDK, provider credential, real ad SDK, advertiser postback or payout provider is bundled. Defaults remain disabled/unavailable. Tests use synthetic credentials and test-only provider/transport fixtures, plus explicit development loopback HTTP tests.

All file-sharing protocols, permissions, models/services and prior tests remain separate. The five original LAN transfer endpoints and certificate-pinned TLS behavior have not changed.

## Non-secret configuration

BackendConfig accepts an enabled flag, development/staging/production environment, a validated base URL, API version, stage/overall timeouts, request/response byte limits, concurrency bound, health/ad-configuration paths, optional analytics path and typed base/reward capabilities.

Environment keys read by BackendConfig.fromEnvironment:

- SHAREBONDHU_BACKEND_ENABLED — default false.
- SHAREBONDHU_API_BASE_URL — no default remote origin.
- SHAREBONDHU_API_ENV — default production.
- SHAREBONDHU_API_VERSION — default v1.
- SHAREBONDHU_ALLOW_LOOPBACK_HTTP — default false.

These are routing/configuration values, not secrets. Do not place tokens, passwords, API secrets or production ad credentials in dart-define values/source files. Missing/invalid environment configuration safely disables the backend.

The base URL is a canonical API prefix. For a base ending in `/api/`, version `v1` and route `wallet`, the client calls `/api/v1/wallet`. Production/staging require HTTPS. Development HTTP additionally requires explicit opt-in and a loopback host (localhost, 127.0.0.1 or ::1). Private LAN/public HTTP is rejected. No Android cleartext exception was added; real devices should use HTTPS with valid certificates.

URLs may not contain userinfo, query or fragment in the configured base. Malformed DNS labels and unsafe path segments are rejected. Per-request routes are relative validated segments, queries are encoded and credential-shaped query names are rejected. Requests stay under the configured version/prefix/origin. AuthSessionService and AuthenticatedApiClient must use matching configuration, preventing token forwarding to another configured origin.

Analytics configuration is only a validated optional path; no analytics events are sent in Part 7. Capability sets are explicit operator configuration, not proof that a remote server implements the endpoint.

## Authentication contract

AuthProviderAdapter implements configured, method, signIn, refresh and signOut. The method reuses AuthenticationMethod (Google, Apple, email/OTP, phone/OTP). Default registry/providers are unavailable. A real adapter must perform the SDK/backend exchange and validate issuer, audience, expiry, signature/nonce and identity; do not return a grant merely from decoding an unverified client JWT.

AuthGrant contains the existing ShareCoinUser, authentication method, backend session identity, opaque access/optional refresh tokens, serverTime and expiries. It is not serialized into app preferences. Tokens are memory-only SecretToken objects with an explicit adapter-use boundary and redacted string representations. Auth snapshots expose status, safe identity/correlation scope, expiry and generation—not credentials. Dart strings are not zeroizable secure storage; persistence/OS-keystore integration remains future work.

Each accepted login has a fresh AccountScope correlation key. The backend still authenticates the bearer and derives its subject; an AccountScope is not a credential. Token refresh preserves the same user/backend-session/method and correlation scope, but rotates token revision. A refresh returning another identity is rejected. Concurrent refresh calls coalesce; stale login/refresh futures cannot resurrect a logged-out or switched account.

States cover unauthenticated, authenticating, authenticated, refreshing, expired, signedOut, restricted and error. Access expiry uses an anchor from serverTime plus monotonic elapsed time; device date is not used to grant rewards or extend tokens. Expired access with a viable refresh token can refresh on the next authenticated request; no refresh loop runs on a timer.

Logout clears local grant/scope before best-effort provider revocation. API requests bound to the old generation are cancelled and repository account changes invalidate the existing ShareCoinService cache. Unrelated Documents/ShareBondhu/Received data is never deleted. Sign-out cannot undo a financial request already processed by the server.

Backgrounding blocks new API requests and cancels in-flight transport. A specifically initiated external-provider login may finish for its still-current attempt while backgrounded, but authenticated API dispatch remains blocked until resume. Resume does not invent a login or refresh a wallet locally. Real OAuth external-user-agent lifecycle behavior requires device testing.

## Authenticated HTTP behavior

AuthenticatedApiClient uses a BackendTransport; production default IoBackendTransport uses dart:io with normal certificate validation, direct connections, no redirect following and no certificate-accept override. It does not reuse LAN self-signed certificate acceptance for internet APIs.

Requests contain JSON with byte limits, a bearer header applied only by the transport, and an Idempotency-Key header for POST. Responses are bounded before decoding, must be JSON objects, and have a structural nesting limit. Request/stage deadlines and cancellation abort the individual HttpClient. Request/response/exception string representations redact bodies/credentials. Raw provider/server messages are not exposed as errors.

A GET returning 401 may perform one coalesced refresh and one retry under the same account generation. A second 401 invalidates only the current matching token revision. An old request cannot retry under a newly logged-in user. Financial POSTs are **not automatically replayed**, including after 401. Dispatched POST timeout/cancellation/redirect/server ambiguity is reported as uncertain, not proof of a refund or failed payout.

The HTTP request budget begins after token acquisition. Provider login/refresh has a separate bounded operation timeout. The default dashboard supplies an outer budget including HTTP and authentication-operation time. When injecting a service/client, size the outer ShareCoinService requestTimeout to cover the configured transport plus any token-acquisition budget; avoid independent layers timing out earlier than intended. A server may still process an already-sent write after the client times out.

## Concrete client route mapping

All paths below are relative to configured base/version. These are implemented adapter mappings for the previous conceptual contracts, **not remotely deployed/verified production endpoints**.

| Method | Relative path | Existing operation |
|---|---|---|
| GET | health | Public minimal status: status=ok and matching apiVersion |
| GET | users/me | currentUser |
| GET | wallet | wallet |
| GET | wallet/transactions | transactions |
| GET | wallet/transactions/{transactionId} | reward extension transaction |
| POST | rewards/events | submitReward |
| GET | rewards/events | rewardHistory |
| GET | rewards/events/{eventId} | rewardStatus |
| GET | offers | offers |
| GET | offers/{offerId} | offer |
| POST | offers/{offerId}/start | startOffer |
| GET | offers/{offerId}/status | offerStatus |
| GET | offers/starts/{startId}/launch | offerLaunch; platform query |
| GET | promotions | promotions |
| POST | rewards/sessions | prepareReward |
| GET | rewards/sessions/status | sessionStatus; exactly one sessionId/requestKey |
| GET | withdrawals/policy | withdrawalPolicy |
| POST | withdrawals | requestWithdrawal |
| GET | withdrawals | withdrawals |
| GET | withdrawals/{withdrawalId} | withdrawalStatus |
| GET | withdrawals/by-key/{idempotencyKey} | withdrawalByKey |
| GET | users/me/referral | referral |
| GET | ads/configuration | adsConfiguration; configurable relative path |
| GET | rewards/daily/configuration | dailyConfiguration |

Configured capabilities gate the calls before dispatch. No previous ShareCoin operation was removed, and no new competing wallet API was created. The original five LAN endpoints are unchanged and are not served by this internet repository.

## Envelope and validation

Retain the Part 5/6 success envelope: userId, serverTime, version, data. Strict v1 response checking rejects unknown envelope/DTO fields, malformed JSON, missing required fields, invalid enums/IDs/UTC timestamps, negative/overflowing coin magnitudes, duplicate page transaction IDs, account mismatch and inconsistent reward/withdrawal identities/amounts.

Use exactly the existing DTO shapes in Files 21, 22 and 26. Optional known fields may be omitted when those parsers permit it. Unknown additions require a coordinated version/client update rather than being interpreted as local financial instructions. Paginated page/pageSize/cursor metadata must agree with the request; country/platform hints do not authorize eligibility.

Error responses can provide a recognized code under error.code. Map authentication, restriction, conflict, below_minimum, insufficient_balance, payout_unavailable, policy_changed, not_found, rate_limited, invalid_request, invalid_provider_signature, expired_offer, cooldown, daily_limit and duplicate_event safely. Unknown/private error content remains redacted. Auth middleware must reject unauthorized writes before financial processing.

## Reward and wallet reconciliation

ShareCoinReconciler wraps the **existing ShareCoinService**. It coalesces account-scoped checks and keeps bounded local synchronization markers—not another financial ledger or wallet.

Reward status → transaction ID → fresh owned transaction with matching source/reference/credit direction → fresh noncached owned wallet → show actual transaction amount → mark the local event check reconciled.

Pending/rejected/cancelled/reversed/unconfirmed remain distinct. Missing/invalid ledger linkage cannot create credit. If a completed ledger transaction exists but wallet refresh fails, the result remains unreconciled rather than inventing a balance. The backend must provide atomic, causally consistent ledger/wallet reads; the client does not derive available balance by adding a transaction to cached data.

Offer reconciliation follows fresh backend Offer status and its transaction reference. Opening/install detection remains irrelevant as financial proof. Reward Center and Offerwall retain their previous validators and now gate completed display on reconciliation. A local marker is only the result of the last successful check and is invalidated on account change; it is not permanent proof against later reversals.

## Withdrawals

Existing ShareCoinService validation stays authoritative on the client side: current active account, fresh policy/wallet, minimum/available balance, saved destination, unchanged quote and idempotency. Backend validation/reservation and payout remain decisive.

After request/status acknowledgment, the existing form synchronizes request status, transaction history and a fresh wallet via the same service. Rejected/failed records stay visible. A sync failure does not convert pending into paid or subtract/refund coins locally. Reconcile unknown results by the original key; do not replay with a new key.

## Ad provider boundary

RewardedAdProvider implements the existing RewardedAdAdapter with a RewardedAdSdkDriver. Default UnavailableRewardedAdSdkDriver cannot load/play/complete an ad. No ad SDK or production ID is added.

A real SDK driver receives an AdLoadContext binding the user, reward session, provider, unit and unique load attempt. It must attach correct server-side verification custom data. AdProviderEvidence contains provider/unit/session/event IDs, sequence, timestamp and result, **not a trusted coin amount**. Loaded/shown/completed ordering, attempt/session/unit/provider matching and duplicate completion are checked before converting evidence into the existing callback type. Late/disposed evidence is ignored. Backend/provider SSV/signature validation is still required; local timestamps/callbacks are not reward authority.

## Required production work

Deploy the mapped API/health contract; integrate real SDK/backend authentication and token rotation/revocation; enforce authorization and subject binding; implement secure refresh-token policies/storage where needed; provider SSV/postback/attribution validation; unique event/session/idempotency constraints; server-time quotas/country/referral/risk/rate rules; atomic ledger/balance/withdrawal processing; payment provider/admin/audit/reversal systems; privacy/legal/provider-term compliance; real Android/iPhone/native build/store validation.

No actual production backend, real Google/Apple/OTP auth, live ads/attribution, advertiser postback, bKash/Nagad/Rocket/PayPal/bank payout or app-store verification is claimed.
