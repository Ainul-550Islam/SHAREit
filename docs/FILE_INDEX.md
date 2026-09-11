# ShareBondhu — permanent file index after Part 7

## Baseline and delivery rules

Part 7 extends ShareBondhu_Part_06.zip, version 0.6.0+6. All 140 archive entries matched the initial working project. Preserve earlier versioned ZIPs/full-code guides. Deliver complete source files, never abbreviated implementations or patch-only instructions. Preserve previous classes/functions/endpoints/validators/permissions/tests. Do not create another wallet or fabricate production authentication, ads or money.

## Permanent numbering

| File | Path | Part 7 |
|---|---|---|
| 1 | `pubspec.yaml` | UPDATED — version 0.7.0+7 only |
| 2 | `lib/main.dart` | Retained |
| 3 | `lib/models/share_file.dart` | Retained |
| 4 | `lib/screens/home_screen.dart` | Retained |
| 5 | `test/widget_test.dart` | Retained — 97 tests |
| 6 | `lib/models/transfer_models.dart` | Retained |
| 7 | `lib/services/local_transfer_service.dart` | Retained |
| 8 | `lib/screens/nearby_screen.dart` | Retained |
| 9 | `android/app/src/main/AndroidManifest.xml` | Retained |
| 10 | `ios/Runner/Info.plist` | Retained |
| 11 | `lib/models/saved_transfer.dart` | Retained |
| 12 | `lib/services/transfer_history_service.dart` | Retained |
| 13 | `lib/screens/history_screen.dart` | Retained |
| 14 | `lib/widgets/pairing_qr_card.dart` | Retained |
| 15 | `lib/screens/scan_pairing_screen.dart` | Retained |
| 16 | `lib/models/transfer_activity.dart` | Retained |
| 17 | `lib/services/transfer_progress_controller.dart` | Retained |
| 18 | `lib/widgets/transfer_progress_panel.dart` | Retained |
| 19 | `lib/widgets/transfer_result_panel.dart` | Retained |
| 20 | `test/transfer_progress_test.dart` | Retained — 107 tests |
| 21 | `lib/models/share_coin_models.dart` | Retained |
| 22 | `lib/models/user_models.dart` | Retained |
| 23 | `lib/services/share_coin_service.dart` | Retained — the single wallet service |
| 24 | `lib/services/connectivity_service.dart` | Retained |
| 25 | `lib/screens/share_coin_home_screen.dart` | UPDATED — optional auth/config/repository, account UI, withdrawal sync |
| 26 | `lib/models/offerwall_models.dart` | Retained |
| 27 | `lib/services/offerwall_service.dart` | UPDATED — fresh-wallet reconciliation for offer credit |
| 28 | `lib/screens/offerwall_screen.dart` | Retained |
| 29 | `lib/screens/reward_center_screen.dart` | UPDATED — reward/reversal reconciliation |
| 30 | `test/offerwall_rewards_test.dart` | Retained — 54 tests |
| 31 | `lib/config/backend_config.dart` | NEW — validated non-secret backend configuration |
| 32 | `lib/services/auth_session_service.dart` | NEW — provider/session/token abstraction and authenticated HTTP client |
| 33 | `lib/services/authenticated_backend_repository.dart` | NEW — concrete contract adapter and synchronization coordinator |
| 34 | `lib/services/rewarded_ad_provider.dart` | NEW — existing-adapter implementation over a real SDK driver boundary |
| 35 | `test/backend_auth_rewards_test.dart` | NEW — 57 Part 7 tests |

No dependency/native/plugin change. The lockfile and Android/iOS files are unchanged. Generated/source assets and all scaffold files are included in the ZIP inventory.

## Verification

Date 2026-09-09. Flutter 3.47.2 / Dart 3.13.2 on Linux. Analysis clean. **315 tests passed: 258 retained plus 57 new tests.** Previous three test files remain byte-identical. Existing classes/enums/functions in updated Files 25/27/29 remain. File 23, every original model, TLS/progress/history implementation and all native permissions remain byte-identical.

New tests cover config/HTTPS, auth transitions/expiry/refresh races/redaction, account/logout isolation, bounded HTTP/error/cancellation behavior, strict financial responses, reconciliation/withdrawals, ad evidence and sharing reachability. Two tests run real explicit development loopback HTTP with synthetic test credentials. Most new provider/backend tests use test-only adapters; this is not production HTTPS/backend, native login/ad/payment or device/store verification.

## Existing contracts to retain

- Keep one main app/file-sharing home, picker/selection/theme and existing routes. Original files are never deleted by reward logout.
- Preserve SB1 QR/manual pairing, explicit sender action/receiver approval, five LAN v1 endpoints, certificate pinning/tokens/local request checks, exact lengths/streamed SHA-256/atomic commit/receipt/recovery.
- Keep 50-file, 2 GiB/file, 4 GiB/batch, 10-minute invitation and 60-second receiver-approval limits and other existing deadlines.
- Preserve owned iterator cancellation/hash disposal, real progress counters, attempt/generation/sequence checks, receipt-only completion and no blind retry after uncertain commit.
- Keep read-only received history, canonical-path/link checks, bounded scans, explicit rechecking/export/iPad anchors and distinct selectable-text PageStorageKeys.
- Preserve all native/camera/foreground/startup/disposal guards. Reward/backend internet availability is never a prerequisite for the existing local transfer path.
- Keep Files 21–23 as the single economy/account/backend contract. Integer/rational financial math, account-scoped cache, no local reward/debit authority, idempotency and safe withdrawal status-by-key remain.
- Keep bounded lazy Offerwall/windowing/filter/search/image/link policies, server launch grants, no install/click credit and real provider evidence followed by backend ledger validation. Test catalogs/providers must not seed production.

## Part 7 contracts

- BackendConfig reads only non-secret routing flags. Defaults disabled. Production/staging HTTPS is mandatory; only explicit development loopback HTTP is allowed. No global native cleartext exception or certificate bypass.
- API base/version/origin, relative paths, timeouts, JSON byte/depth and concurrency bounds are enforced. Client/auth configuration must match. Analytics path is configuration only; no analytics transmission was added.
- AuthProviderAdapter must perform verified SDK/backend identity exchange. Default providers unavailable; no hard-coded tokens or locally fabricated login.
- SecretToken/AuthGrant/lease/request/response/error diagnostics are redacted. No passwords/token persistence is implemented. Tokens are memory-only; OS secure storage and real SDK rotation/revocation remain future integration.
- Identity generation/correlation scope is separate from token revision. Refresh is single-flight and preserves user/backend session/provider. Late login/refresh results cannot resurrect old accounts. Expiry uses server-time plus monotonic elapsed time.
- Logout invalidates scope/cache immediately, cancels authenticated requests and then attempts provider revocation. It does not delete unrelated file-sharing history. Background cancels API traffic, but does not invent financial rollback.
- GET 401 may refresh/retry once under the same account; POST is never automatically replayed. Dispatched write ambiguity stays uncertain and requires original-key reconciliation.
- AuthenticatedShareCoinBackend implements the existing base/reward capability interfaces, with concrete mappings of the previous conceptual contracts. All calls remain on the same wallet service/backend identity. No remote server is deployed by this repository.
- Strict v1 envelope/DTO checking rejects unsafe unknown fields, malformed/duplicate/negative/overflow/account-mismatched financial data. Real backend authorization/atomicity/provider validation remains required.
- ShareCoinReconciler coalesces scoped status → ledger → fresh wallet checks and keeps bounded local synchronization markers, not another wallet/ledger. Completed display waits for a fresh noncached owned wallet; no balance delta is computed locally.
- Reward Center and Offerwall retain their previous status/linkage checks, adding reconciliation. Reversed/rejected outcomes remain visible. Withdrawal form/status checks refresh request/ledger/wallet through the same service, never locally mark paid.
- RewardedAdProvider implements the existing RewardedAdAdapter through RewardedAdSdkDriver. Default driver unavailable. SDK loaded/shown/completed evidence must match provider/unit/session/load attempt and sequence. Duplicate/stale/premature completions are ignored; evidence has no trusted coin amount.
- Default ShareCoinHomeScreen constructs the disabled/configured repository and auth service. Existing injected ShareCoinService remains supported. Account dialog exposes safe status and only configured provider buttons. No second app entry point.

Read PART_07_BACKEND_AUTH_CONTRACT.md before connecting a server/auth/ad provider. Prior Part 5/6 contracts remain historical references, and existing endpoint meanings must be preserved.

## Next

Next is **Part 8 — File 36–40**. No Part 8 code is included. Real backend deployment, Google/Apple/OTP SDK exchange, provider SSV/attribution, payout integration, persistent secure sessions, native builds/real devices/two-phone tests and store compliance remain explicitly unverified.
