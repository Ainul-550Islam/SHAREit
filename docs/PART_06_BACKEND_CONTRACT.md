# Part 6 — optional reward/launch capabilities

This extends the Part 5 contract on the **same ShareCoinBackend instance and authentication scope**. It is not another wallet, a deployed REST server, or a client-side payout system. Unconfigured defaults remain unconfigured.

## Retained operations

The existing ShareCoinOperation enum, wallet/transactions/events/offers/promotions/withdrawal/referral/configuration methods and response envelope remain. Existing default payloads retain their fields. getOffers accepts optional minimumReward and maximumReward arguments only when supplied; the backend must apply these together with the existing query. getAdConfiguration/getDailyRewardConfiguration accept an optional allowCached flag, retaining their previous default.

Pagination uses the existing OfferQuery and CoinPage/PageInfo. Define stable ordering: recommended is featured first, then ascending sortPriority and offerId; rewardHigh/rewardLow compare rewardCoins then offerId; timeShort compares estimatedMinutes then offerId. Search is a case-insensitive substring over title/description/publisher. Platform/country query values are hints, not authorization or geographic evidence.

The UI retains at most 500 offers per window by default, then requests subsequent windows. It retains a bounded recent ID/cursor history to reject duplicates/cycles. It is not an unlimited local index. The backend must maintain stable, unique paginated snapshots and accurate totals/cursors. No exact 300-item assumption exists in production code.

## Optional capability interface

Implement ShareCoinRewardBackend alongside the existing ShareCoinBackend. Its executeRewardExtension takes a ShareCoinRewardOperation, the same AccountScope and bounded arguments. It must use the same authenticated/authorized HTTPS transport and return the existing envelope:

- userId matching authenticated scope;
- serverTime as strict UTC;
- version as a safe revision identifier;
- data as a model object.

| Extension | Suggested adapter mapping | Request / response |
|---|---|---|
| transaction | GET /wallet/transactions/{transactionId} | ID → ShareCoinTransaction |
| prepareReward | POST /rewards/sessions | source, targetId, idempotencyKey → RewardSession |
| sessionStatus | GET /rewards/sessions/status | exactly one of sessionId or requestKey → RewardSession |
| offerLaunch | GET /offers/starts/{startId}/launch | startId, platform → OfferLaunchGrant |

Paths are proposed adapter contracts, not hard-coded working endpoints. A GraphQL adapter may map the same concepts differently. Braced terms are path parameters. Unsupported optional capability returns notConfigured; do not fabricate success.

## Offer start and launch

Use the existing fresh getOfferStatus and idempotent startOffer flow. An OfferStart is only a backend start acknowledgment. The new OfferLaunchGrant contains startId, offerId, userId, platform, a full HTTPS launchUrl, issuedAt and expiresAt. Validate ownership, eligible country/platform/account, offer state and expiry before issuing it. The complete provider attribution URL comes from the backend; the client does not append invented tracking parameters or infer completion from package installation.

The app validates grant identity/platform/expiry and an operator-supplied exact HTTPS origin allowlist. After the user consents to leaving the app it rechecks grant/offer expiry using elapsed monotonic time. A cancelled consent leaves a recorded start, not a reward. Opening failure permits reopening that start without reposting it. Provider URL opening is an OS-launch acknowledgment, never attribution or payout proof.

The initial launch/image origins default to an empty allowlist. Configure only reviewed provider/store/CDN origins. No arbitrary client destination is trusted. External browser/store redirects are outside the client's full visibility; approve and verify the provider redirect chain on the backend/operator side. Do not put authentication secrets in image URLs or log personalized attribution URLs.

## RewardSession contract

Fields: sessionId, userId, eventId, idempotencyKey, requestKey, source, provider, targetId, rewardCoins, issuedAt, expiresAt, notBefore, availability, usedToday, dailyLimit, optional providerEventId and launchUrl.

- requestKey echoes the idempotency key for preparing the session; session event idempotencyKey is the stable key for the later RewardEvent claim.
- source is adReward, dailyReward or promotionReward. targetId is an approved ad placement, daily policy version or campaign ID.
- IDs bind the session, authenticated user, provider, action and final event. They are not bearer authentication credentials.
- availability is eligible/cooldown/dailyLimit/expired/unavailable/restricted. A positive reward and remaining quota are required for eligible sessions.
- usedToday counts previous consumed/reserved attempts, excluding this particular issued session. Reserve eligibility atomically so concurrent sessions cannot bypass quotas.
- notBefore is at least issuedAt; expiresAt is later. The backend decides current eligibility; a client countdown cannot grant it.
- A daily eligible session includes a backend-issued providerEventId/claim reference. Its reward must match the fresh daily policy version/day the client reviewed.
- A promotion session may include its validated launchUrl. A promotion click creates tracking only; the client does not submit an earning event merely for opening it.

Preparing a session is not credit. Apply source-specific cooldowns, daily limits, account restrictions, referral/country risk rules, anti-replay and one-day claim uniqueness on the backend. Device date and user-supplied reward amounts are not authority.

## Provider completion and credit

A real RewardedAdAdapter must wrap a compliant native SDK, load actual development/production units as configured, bind server-side verification custom data to the issued session, and emit the correct sessionId with events. Its load future succeeds only when the SDK is ready; show requests actual presentation. Completion must include the provider event reference. Do not emit success from a timer or client button alone.

The default adapter intentionally returns unavailable. No Google/AppLovin/other ad SDK or production unit is bundled. Provider choice, policies and real native integration are outstanding. Incentive/redemption rules must permit the intended ShareCoin ecosystem before enabling cash-related rewards.

Client completion → existing RewardEvent (created claim, session in safe metadata.trace) → provider signature/SSV/attribution verification → backend pending/approved/rejected → durable ledger transaction → wallet refresh.

Reject duplicate provider events, wrong signatures, wrong user/source/target/session, expired or replayed sessions, impossible amounts and restricted accounts. Calculate approved amounts from server policy, not requestedCoins. Use unique constraints and atomic posting to prevent double credit across users/devices/restarts. Client duplicate suppression is only bounded assistance.

An approved RewardEvent references a transaction. The client fetches that transaction fresh and requires matching ID/user/source/referenceId and credit direction. In Part 6 referenceId is the offerId for offer credit and the session targetId for ad/daily/promotion credit. Only status completed produces a current credited UI. Reversed/rejected/cancelled statuses remain visible and are not represented as approved earnings. Offer nominal reward and actual transaction amount can differ; the UI displays the verified ledger amount.

A lost response never triggers blind creation of another claim. Reconcile by original request/session/event IDs. Backend SSV may finish while the app is backgrounded or absent; status/history remain the authority. No local state change is a refund, withdrawal or credit.

## Images and performance

Only operator-allowlisted HTTPS image origins are fetched, with normal certificate validation and no credential headers or redirects. Download, static-image dimensions, decoding size, request concurrency, queue and memory cache are bounded. Error/unsupported/missing images use a fallback icon. Do not send arbitrary large or active SVG resources as icons; use compact PNG/JPEG/WebP thumbnails.

Lazy rendering creates only nearby offer cards. Feature strip is capped. Catalog controls debounce and invalidate stale generation/account responses; offline reads are explicitly cached. Interface presence is not proof of internet or peer connectivity, and reward availability never gates local sharing.

## Withdrawal/referral/ledger

The Part 5 withdrawal policy/intent/request/idempotency/status-by-key validation and form remain. bKash/Nagad/Rocket/PayPal/Bank are configuration options, not connected methods. Existing referral summaries are backend-qualified. New ledger/withdrawal feeds are paginated and do not hide rejected/reversed records. All payout provider processing, financial consistency, AML/KYC/legal/privacy obligations where applicable, admin review and audit/reconciliation remain backend/operator work.

## Verification boundary

File 30 contains the 300-offer fixture and a 1,020-offer traversal fixture, test ad adapter and test backend. No production file imports them. Tests verify client protocol/state/validation behavior, not real provider signatures or advertiser payouts. Native launch, physical phones, real ad playback/attribution, login/payout connections, production build/signing and store compliance remain unverified.
