# ShareBondhu — Part 7 (File 31–35)

Version **0.7.0+7**, extending the Part 6 baseline. Adds validated backend configuration, provider-neutral authentication/session management, a concrete authenticated HTTP repository for the existing ShareCoin contracts, reconciliation, and a real-ad-SDK evidence boundary.

**No production service is automatically configured.** The default backend is disabled, authentication providers are unavailable, tokens are not seeded, and the default ad driver cannot play or complete an ad. No real login, advertiser attribution or cash payout is claimed.

## Existing source inspected

All **140 entries** in ShareBondhu_Part_06.zip matched the initial working project. Existing Dart types/APIs, all tests, Parts 5/6 backend contracts, pubspec/lockfile and Android/iOS permissions/configuration were reviewed. The prior documented baseline was 258 passing tests.

## Files added

| File | Path |
|---|---|
| 31 | `lib/config/backend_config.dart` |
| 32 | `lib/services/auth_session_service.dart` |
| 33 | `lib/services/authenticated_backend_repository.dart` |
| 34 | `lib/services/rewarded_ad_provider.dart` |
| 35 | `test/backend_auth_rewards_test.dart` |

## Files updated

- **File 1:** version only, 0.7.0+7.
- **File 25:** configurable auth/backend construction, account-session UI/logout, and withdrawal wallet/ledger synchronization. Existing methods and file-sharing shortcuts remain.
- **File 27:** Offerwall completion display uses fresh wallet reconciliation after its existing status/ledger checks.
- **File 29:** Reward Center completion uses reconciliation; reversed/rejected ledger paths refresh through the same service.
- Documentation/index/inventory/reports updated. Earlier ZIPs and full-code guides remain immutable.

The existing **ShareCoinService (File 23) is unchanged**, and remains the only wallet service. Existing models, test files, TLS/pairing/transfer/history services, permissions, lockfile and all other original source files remain byte-identical. No previous function/class was removed from the updated screens/controllers.

## Dependencies

**None added.** HTTP uses dart:io; reactive state uses Flutter's existing classes. No authentication, secure-storage, HTTP or ad SDK package was installed into the application. Native/plugin configuration did not change.

## Backend configuration

BackendConfig validates enabled/disabled state, environment, API prefix/version, timeouts, JSON limits, concurrency and supported existing capabilities. Non-secret dart-define keys are documented in `docs/PART_07_BACKEND_AUTH_CONTRACT.md`.

Production/staging require HTTPS. Development HTTP requires explicit opt-in and a loopback host; no general LAN/public HTTP exception is provided. No native cleartext exception was added. Invalid/missing environment configuration safely disables the backend. No analytics traffic is sent.

The concrete repository maps the existing user/wallet/offer/reward/promotion/referral/withdrawal operations and Part 6 reward capabilities to relative API paths under the configured base/version. No remote production host or server deployment is included.

## Authentication flow

**Configured provider login → validated backend AuthGrant → API session/token → authenticated request/user scope → logout/cache invalidation.**

Provider interfaces reuse Google, Apple, email/OTP and phone/OTP method metadata, but actual SDK/exchange implementations are not bundled. A provider must verify identity with the backend; decoding an untrusted client JWT is not authentication.

Opaque tokens are memory-only and redacted from snapshots, request/response diagnostics and exceptions. No passwords or tokens are placed in app preferences, logs, source or environment configuration. Secure persistence and real SDK/token-revocation integration remain future work.

Session generation and token revision distinguish identity changes from same-user refresh. Refresh is single-flight; late login/refresh results cannot restore a logged-out account. Device wall-clock changes do not extend token eligibility. Backgrounding blocks/cancels API traffic without deleting local received files.

Authenticated GET may refresh and retry once under the same account. POST is not automatically replayed. Dispatched write timeout/cancellation/server ambiguity stays uncertain and must be reconciled by its original idempotency key.

## Reward and wallet reconciliation

**Action → provider evidence → existing RewardEvent → backend verification → owned ledger transaction → fresh wallet → reconciled display.**

ShareCoinReconciler wraps the unchanged ShareCoinService. It never calculates balance plus reward. It validates event/offer identity, transaction source/reference/credit direction, obtains a noncached owned wallet, and then records a bounded local synchronization marker. A marker is not another ledger and is cleared on account change.

Pending/rejected/reversed/unknown states remain visible. A completed ledger entry without a successful wallet refresh is not shown as a fully reconciled reward. The backend must implement atomic, causally consistent wallet/ledger operations.

## Withdrawal flow

**Fresh wallet/policy → stable idempotent request → backend validation/reservation → processing → backend paid/rejected status → ledger/wallet refresh.**

The existing minimum, balance, quote, destination, conflict and idempotency checks remain. Request/status responses are synchronized through the same service. The client does not turn pending into paid or locally subtract/refund coins. bKash/Nagad/Rocket/PayPal/bank remain configuration choices until real providers are connected.

## Ad provider boundary

RewardedAdProvider implements the existing RewardedAdAdapter using an injectable RewardedAdSdkDriver. Its default driver is unavailable. A real driver must emit matching load-attempt/session/provider/unit evidence in the proper loaded/shown/completed order and bind provider SSV custom data.

Evidence contains identity, timestamp and outcome—not a trusted coin amount. Duplicate, stale or premature completion is ignored. Provider/backend signature/attribution verification remains mandatory. No ad SDK or production unit is added simply to make tests pass.

## API validation and security

Normal HTTPS validation, no redirect following, same configured API origin/prefix, bounded JSON bytes/depth and safe error-code mapping. Tokens are applied only to authorized requests, never URL queries. Unknown unsafe schema fields, malformed IDs/status/timestamps, invalid coin amounts, duplicate transaction IDs and cross-account responses are rejected.

The backend still must authenticate/authorize every request, verify token issuer/audience/signature/revocation, provider evidence, unique event/idempotency constraints, server-time eligibility, quotas/country/referral/risk rules, atomic ledger/withdrawal processing, admin/audit/reversal flows and privacy/payment/provider compliance. Client code cannot provide these server guarantees.

## Automated verification

Actually run with Flutter **3.47.2 / Dart 3.13.2**, Linux:

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded --timeout 30s`: **315 tests passed**.
- Previous tests: **258**, preserved byte-for-byte.
- New Part 7 tests: **57**.

Tests include config/HTTPS rules, auth state/expiry/refresh races, logout/account isolation, token redaction, HTTP parsing/error/cancellation, ledger/wallet reconciliation, withdrawal idempotency/status, ad evidence and original sharing navigation. Two new tests run actual development loopback HTTP with synthetic tokens, including socket cancellation. Most new backend/provider responses are explicit test fixtures, not production services.

No real Google/Apple/OTP authentication, production HTTPS deployment, actual ad/offer attribution/postback, payout, native build/signing/store or physical Android/iPhone/two-phone test is claimed.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Use a hot restart after changing these Dart classes. No new native full rebuild is required solely for Part 7; no plugin/permission changed. Earlier native packages still need a rebuild if they were never installed into the app. Android requires the existing compatible JDK/SDK; iPhone builds require Mac/Xcode/signing.

## Manual verification — required, not performed here

1. Confirm original Home/Send/Receive/QR/manual/Saved Files/history actions remain reachable while backend is disabled or offline.
2. Open ShareCoin → account icon. Default provider buttons must be unavailable; no fake user/balance/login should appear.
3. With a real staging auth adapter/API, test login, expiry, concurrent requests during refresh, logout mid-request, account switching, app background/resume and invalid/revoked tokens. Inspect redacted diagnostics only.
4. Validate actual server envelopes/HTTP error codes, capability settings, JSON limits, HTTPS certificates and rejection of redirects/malformed/cross-account financial data.
5. Complete staging offer/ad/promotion/referral actions using legitimate provider evidence. Confirm pending/approved/rejected/reversed status, matching ledger transaction, fresh wallet and reconciliation; no client balance arithmetic.
6. Test existing withdrawal minimum/balance/conflict/quote/idempotency, pending/rejected states and original-key reconciliation with actual provider/admin processing. Do not treat staging test responses as real payouts.
7. Integrate a compliant real ad SDK with development units, then test load/show/evidence ordering, duplicate/stale callbacks, SSV and lifecycle on Android and iPhone. Default unavailable driver is not playback verification.
8. On two real phones, test original TLS transfer, approval, progress/cancel/retry, final receipt, saved history and SHA-256 while rewards internet is unavailable. Reward logout must not remove received files.

## Known limitations

No production backend deployment or auth/ad/payout SDK integration is connected. Tokens and reconciliation markers are memory-only; secure persistent sessions and real backend revocation need implementation. SDK/provider proof and financial authority remain server responsibilities. External auth/ad/native lifecycle, actual HTTPS deployment, stores and real devices are unverified. Existing private-IPv4/foreground/no-resume sharing limitations remain unchanged.

# ▶ Next — Part 8 (File 36–40)
# SHAREit
