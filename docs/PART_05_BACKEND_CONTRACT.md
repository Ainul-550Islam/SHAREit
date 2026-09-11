# Part 5 — ShareCoin backend contract and trust boundary

**Status: client contract only. No production reward backend, authentication SDK, ad SDK, attribution service or payout provider is connected by this part.**

The production default is UnconfiguredShareCoinBackend. It returns a typed notConfigured error, no account and an unconfigured health state. It never returns seeded coins. TestShareCoinBackend lives only in the existing test file and is not referenced by production code.

## Identity and transport

Implement ShareCoinBackend using the application's future authenticated REST/GraphQL client. Its AccountScope is only a user/session correlation key, not a credential or proof of authentication. A real auth adapter must create a fresh session identifier when the user logs in/out/changes account, update scope and emit accountChanges. Tokens/passwords do not belong in these domain models.

The adapter must validate HTTPS certificates normally, authenticate every protected operation, verify token issuer/audience/expiry/subject, map the authenticated subject to the backend user, and reject unauthorized resources. Do not reuse the LAN transfer certificate-pin exception for internet APIs. Do not trust a submitted userId, sessionId, requestedCoins, providerEventId, local timestamp, account status or feature flag as authority.

No hard-coded remote origin or live endpoint is shipped. The operation mapping below is a proposed adapter contract; an implementation may map it to compatible GraphQL operations or differently named REST routes.

## Response envelope

Successful execute calls return an object with:

| Field | Requirement |
|---|---|
| userId | Backend-authenticated user ID, matching the request scope |
| serverTime | Strict UTC ISO-8601 timestamp |
| version | Opaque safe revision identifier, not an unprocessed HTTP ETag header |
| data | An object parsed by the operation's domain model |

The gateway should reject oversized input before JSON allocation: recommended maximum 64 KiB request, 512 KiB response, bounded timeouts and depth. The current service applies DTO/list/text limits after the gateway returns an object; it is not itself a byte-level HTTP implementation.

All coin amounts and currency minor units are whole JSON integers from 0 to 9,007,199,254,740,991. Claims/transactions/withdrawal requests require positive amounts. Debit/credit is a separate direction, not a negative magnitude. Rational conversion uses coinUnits/minorUnits/currency/scale and BigInt intermediates; gross payout rounds down to a whole minor unit. Backend financial policy remains authoritative and should impose tighter business limits.

Timestamps accept UTC dates in 2000–2199 and reject invalid calendar components. Created/completed/updated and campaign start/end relationships are checked. These structural bounds are not reward eligibility: only server time/policy can determine eligibility.

## Operations and suggested mappings

| ShareCoinOperation | Suggested REST mapping | Data model |
|---|---|---|
| currentUser | GET /users/me | ShareCoinUser |
| wallet | GET /wallet | ShareCoinBalance |
| transactions | GET /wallet/transactions | CoinPage of ShareCoinTransaction |
| submitReward | POST /rewards/events | RewardEvent with backend status |
| rewardStatus | GET /rewards/events/{eventId} | RewardEvent |
| rewardHistory | GET /rewards/events | CoinPage of RewardEvent |
| offers | GET /offers | CoinPage of Offer |
| offer | GET /offers/{offerId} | Offer; operation reserved for a detail adapter |
| startOffer | POST /offers/{offerId}/start | OfferStart, not a credited reward |
| offerStatus | GET /offers/{offerId}/status | Offer |
| promotions | GET /promotions | CoinPage of Promotion |
| withdrawalPolicy | GET /withdrawals/policy | WithdrawalPolicy for this user |
| requestWithdrawal | POST /withdrawals | WithdrawalRequest |
| withdrawals | GET /withdrawals | CoinPage of WithdrawalRequest |
| withdrawalStatus | GET /withdrawals/{withdrawalId} | WithdrawalRequest |
| withdrawalByKey | GET /withdrawals/by-key/{idempotencyKey} | WithdrawalRequest for reconciliation |
| referral | GET /users/me/referral | ReferralSummary |
| adsConfiguration | GET /ads/configuration | AdConfiguration |
| dailyConfiguration | GET /rewards/daily/configuration | DailyRewardConfiguration |

These are **contracts, not deployed working endpoints**. Braced values are path parameters. Encode parameters appropriately in a real adapter. Use safe typed ShareCoinException codes instead of exposing raw provider/server error text.

Queries include page, pageSize and cursor. Catalog queries also carry search/category/sort/platform/country hints. History adapters may ignore catalog-only fields. Page size is 1–100; total is not capped at 300. Responses contain items and page metadata: page, pageSize, total, hasNext, nextCursor and previousCursor. Page/query sizes must agree; duplicate IDs in a page and a repeated next cursor are rejected. Feed snapshots and cross-page de-duplication belong in the Part 6 Offerwall implementation.

Country and platform hints do not prove eligibility. Filter by actual backend/provider policy. Empty country/platform availability is not a claim of global availability. DTO URLs must be HTTPS and have no userinfo, nonstandard port, IP host or fragment. Part 5 neither launches offers nor loads provider images; a future image/link adapter also needs explicit trusted-origin allowlists, redirect controls and user consent.

## Reward flow

User action → provider/tracking evidence → RewardEvent claim → backend validation → pending/approved/rejected → backend transaction → wallet refresh.

submitRewardEvent accepts only a created claim with no transaction ID. A response approving a reward must reference a backend transaction. Requested reward amounts are untrusted hints; calculate the actual approved amount from the provider/campaign rules. The client never adds a claim amount to a wallet.

Client idempotency uses logical provider-action identity, event ID and idempotency-key aliases. Concurrent duplicate calls share a result. Conflicting aliases/payloads are rejected. The ledger is bounded and in-memory; settled responses can be evicted, and it resets with an account/session. It cannot prevent multi-device or post-restart double credit. The backend must atomically enforce uniqueness of user/provider/action/event identifiers and idempotency keys with payload hashes.

Network loss or malformed write confirmation is uncertain. The client retains the original request identity instead of automatically posting a new claim. Query status to reconcile. No offline event queue or local credit is created. Daily/referral eligibility is not based on the device date or the number of locally created accounts.

## Withdrawal flow

Backend wallet + policy → WithdrawalIntent → backend validation/reservation → admin/payment provider processing → backend paid/rejected/cancelled status → wallet refresh.

The client checks authenticated scope, fresh active user, fresh balance/policy, minimum, available balance, active-request conflict, configured provider/destination, exact policy revision and the reviewed fee/final amount. It sends a stable idempotency key. It verifies user/key/amount/method/masked destination/rate/fee/final payout in the returned record.

Only an opaque saved destination reference is submitted. The DTO stores a masked destination, not raw payment credentials. bKash, Nagad, Rocket, PayPal and Bank are configuration choices, not connected providers. A backend reports which methods/destinations it supports; that flag is not evidence of provider testing in this delivery.

The backend must atomically reserve/debit eligible funds, prevent concurrent conflicting withdrawals across devices, bind idempotency to the original payload, reject changed policies/quotes, and protect destination registration/change. Provider/admin actions update the status with authenticated references. Paid requires a server/provider reference; rejected requires a reason. Polling may skip forward states but may not reverse a terminal request. Reversals belong in the ledger.

An uncertain request keeps its original key and blocks another local withdrawal. The UI offers Check request status using withdrawalByKey. Not-found after an uncertain write is not automatically a safe retry signal. The backend must define authoritative reconciliation and idempotent replay semantics. No client arithmetic is treated as a debit, refund or completed payout.

## Cache, lifecycle and account safety

- Read cache: at most 24 account-scoped entries/pages by default; memory only. Cache is used on offline/unavailable reads only when allowed, and is explicitly labelled.
- Fresh-only financial checks do not coalesce with cache-permitted requests. Old account/session responses are rejected. A pre-mutation wallet reply cannot overwrite a post-mutation wallet view.
- Mutations: at most 256 retained local records with bounded alias sets. In-flight/uncertain entries are not evicted merely to make room. Server enforcement remains required after eviction/restart.
- Mutations invalidate wallet display/cache; they do not alter available/pending/lifetime coin amounts locally.
- Suspension blocks new submissions. An already-dispatched request may still complete on the server; do not claim cancellation of a backend financial operation from a local lifecycle change.
- Connectivity performs coalesced bounded probes, ignores stale generations, and has no automatic reconnect loop. The default local probe reuses the existing private-IPv4 helper. Internet remains unknown unless an explicit probe is supplied. Reachable backend status is direct endpoint evidence, not proof that all internet services work.
- File sharing does not depend on ShareCoin connectivity. A private IP is only a candidate interface, not proof of Wi-Fi type or peer reachability. Existing TLS pairing/approval is still authoritative for file transfer.

## Production requirements still outstanding

Secure authentication and account lifecycle; server wallet/transaction storage; row/transaction-level consistency; signed provider webhooks or server-to-server verification; provider event uniqueness; daily/campaign/referral caps; device/account risk controls with lawful privacy safeguards; rate limiting; country/platform eligibility; chargeback/reversal handling; fraud/admin review and audit trails; secure payout providers/destination vault; cash-conversion/legal/tax/KYC requirements where applicable; provider terms and incentive-policy review; privacy disclosures and native/store/device testing.

No ad completion, app installation, promotion click or referral account creation in the Flutter client is proof of earning. No real advertiser payouts, attribution verification, login provider or cash withdrawal is implemented or verified here.
