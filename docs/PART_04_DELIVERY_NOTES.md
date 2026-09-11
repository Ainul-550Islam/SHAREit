# Part 4 delivery notes

## 1. Changed Files

**NEW:** Files 16–20, in the order shown above.

**UPDATED:** File 1 (`pubspec.yaml`, version only), File 6 (`lib/models/transfer_models.dart`, additive local telemetry), File 7 (`lib/services/local_transfer_service.dart`, real-event instrumentation), File 8 (`lib/screens/nearby_screen.dart`, progress/result integration).

Files 2–5, 9–15 and `pubspec.lock` are byte-identical to Part 3. The original 97-test file has not been edited. All preexisting functions/classes in the updated files are retained. Documentation, inventory and test reports describe the current version.

## 2. Dependencies

**No new package.** All existing exact versions and the dependency lockfile are retained. Flutter 3.47.2 / Dart 3.13.2 was used here; minimum constraints remain Flutter 3.47.0 / Dart 3.13.0.

## 3. Existing Logic Preserved

The existing TLS engine remains the transfer authority. Its five v1 endpoints, SB1 manual/QR code, certificate pinning, invitation/upload tokens, receiver approval, exact sizes, streamed SHA-256, file acknowledgments, atomic batch commit, receipt verification/recovery and cleanup remain.

The additions to `TransferProgress` are **local only**; no wire fields or endpoints are replaced. The commit boundary is marked conservatively before its body is queued, so a cancellation race cannot be treated as a safe automatic retry merely because confirmation was lost.

QR still only fills the pairing code. Sender still presses Ask to send, and receiver still accepts. Selection/originals, history, explicit history verification, native share/export, platform permissions and lifecycle handling are retained. The prior receipt/export panel is embedded in the result panel. Receiver history actions open the existing HistoryScreen, not a second database.

Limits remain **50 files, 2 GiB/file, 4 GiB/batch, 10-minute invitation, 60-second receiver approval**. Existing other engine deadlines remain.

## 4. Tests Added

**Automated verification actually performed:**

- Previous tests: **97**, retained.
- New tests: **46**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **143 tests passed**.

Coverage includes idle/connecting/approval/approved/preparing/sending/receiving/verifying/completed/failed/cancelled states; zero/single/multiple files; 100% bytes without delivery; bounds, file and byte counts; cancellation and late receipts; failure and safe retry; speed, ETA and stalls; verification/receipt consistency; sender and receiver integration; existing saved history; small-screen layout; disposal/backgrounding; duplicate/stale events; malformed metadata, high sequence values and regressing counters.

Five new integration tests use real TLS sockets and disk output on one computer. Widget tests use test-controlled dependencies where appropriate. These are **not real phone/camera, native build, two-phone Wi-Fi or store tests**. Full output is in `docs/PART_04_TEST_RESULTS.txt`.

## 5. Build Commands

Run inside the extracted `sharebondhu` directory:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Stop active transfers and use a hot restart when updating code. **No newly required native full rebuild solely for Part 4:** no plugin or permission changed. If the installed app never included Part 3's camera/native packages, a full stop/rebuild is still needed for those earlier additions.

Android needs the Android SDK and compatible JDK 17+. iPhone compilation requires Mac/Xcode and signing setup. No APK/IPA is included or claimed verified.

## 6. Manual Two-Phone Test

**Manual/device verification required — not performed here.**

1. Install on two real Android phones on the same trusted private IPv4 Wi-Fi/hotspot. Keep both apps open; avoid guest/client-isolated networks.
2. Receiver: Receive files → Start receiving. Sender: choose a small local file → Send selected. Pair manually, and repeat another run using Scan receiver QR → Start camera → Use this code.
3. Confirm QR scanning alone transfers nothing. Press Ask to send; verify the waiting-for-approval state. Decline once and confirm no saved batch; retry with explicit receiver acceptance.
4. Accept and transfer the small file. Check current filename, file number, bytes and final receipt. Do not infer delivery at 100% bytes. Inspect Saved files and explicitly verify checksums.
5. Send multiple files, a zero-byte file and same-named files from different sources. Check per-file byte resets, cumulative totals, staged counts and the complete-batch receipt.
6. Use a larger local file within the existing limits to observe payload rate/ETA. Those estimates exclude approval, final verification/save and receipt recovery.
7. Cancel midway, then wait for settlement. Originals must remain; an uncommitted batch must not appear as delivered. Use Retry uncommitted batch only when offered and confirm new receiver approval is required.
8. Repeat cancellation from the receiver and near completion. A commit may already have won. If confirmation is unknown, check receiver history before retrying; do not assume it failed.
9. Background/lock one phone during activity. Confirm the work stops rather than silently resuming, then create a fresh session.
10. On a confirmed receiver result, choose View Saved Files, accept the stop-session prompt where shown, verify the files and export through the existing share sheet. Check the chosen destination yourself.

Perform a separate iPhone interoperability/permission pass before claiming iOS device support has been verified.

## 7. Known Limitations

- Foreground private IPv4 transfer only; no resume, background service, automatic hotspot/discovery or IPv6-only transfer.
- Rate measures recent local payload writes/flushes, not durable delivery. Tiny transfers may finish before a stable estimate appears. ETA is for remaining bytes only.
- The engine commits an atomic batch. Retry starts the entire known-uncommitted batch; no unsupported partial-upload resume is invented. Unsuccessful counts include unattempted/rolled-back files. Ambiguous outcomes show unknown counts.
- Cancellation cannot retract committed files. Missing confirmation may require manual receiver/history inspection.
- Progress is in-memory, not a persistent resumable queue. Existing read-only received history remains unchanged.
- Real Android/iPhone/camera, native/production builds, two-phone networking, signing and store verification remain outstanding. No new at-rest encryption, signed-history receipt, ad SDK or audited-security claim is made.

# ▶ Next — Part 5 (File 21–25)
