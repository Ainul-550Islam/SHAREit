# Part 3 — QR and received-file history

## Compatibility boundary

Files 2, 3, 6 and 7 are byte-identical to Part 2. The five v1 endpoints, 98-character SB1 encoding, TLS identity/pin, invitation/upload-token distinction, explicit approval, byte/hash validation, atomic commit and cancel/cleanup behavior are unchanged. Part 3 adds no new network endpoint and does not migrate old received files.

The immutable Part 2 wire specification remains in PROTOCOL_V1.md. Its old statement that no QR/history UI exists describes that earlier part, not the current UI.

## QR encoder and scanner

File 14 encodes PairingCode.encode() directly through qr_flutter. The image uses black modules on white, medium error correction, no center logo, and 24 logical pixels of quiet padding. The UI removes expired QR images, while the receiver engine remains the authoritative validator of session lifetime. A code contains no expiry field; a stale code can be scanned but fail to connect.

File 15 owns an optional camera adapter. The production adapter wraps mobile_scanner 7.4.0 with autoStart false, QR-only detection and returnImage false. The camera starts after an explicit Start camera action. It is stopped for background/interruption, after a valid capture and on screen disposal, including a startup/permission result that completes late. Resuming the app does not automatically restart capture. Start/stop/dispose coordination waits for pending startup before releasing the native controller.

Capture validates the existing SB1 format and private-address policy. It never opens arbitrary links, launches a browser, changes Wi-Fi, sends files or approves a receiver request. Duplicate events are gated once a candidate exists. Use this code returns the full canonical code to the sender form; Ask to send remains a separate action. Manual entry is preserved, including its existing value when scanning is canceled.

Camera denial/unavailability produces a fallback message. Android camera permission/hardware features are optional; iOS has a camera usage description. No microphone/gallery permission was added. The default bundled Android scanner model remains configured. Dependency/platform privacy declarations still need release review.

## Read-only history storage

Files 11 and 12 read Documents/ShareBondhu/Received. A valid batch folder is `received-` plus 32 lowercase hex characters. Its folder name, not the sender-controlled wire batch ID, is the history row identity. This prevents repeated wire IDs from collapsing separate received batches.

Receipts are bounded to 64 KiB and validated for v1 structure, UTC timestamp, unique file IDs, counts, sizes, digests and already-safe basenames. A path is derived from the checked directory, 1-based three-digit index, underscore and display filename. Serialized localPath/path fields are never used.

Root/batch/receipt/file node types and canonical paths are checked. Symbolic links and paths outside the expected immediate directory are rejected. Incomplete staging and unrelated directories are ignored. Invalid records are skipped with a visible count; files are not deleted or repaired. The scan inspects at most 2000 root entries and shows at most 250 valid batches by default, with a truncation notice if limits are reached. Within the bounded candidates, listing is sorted for recency. It is not an unlimited archive index.

Listing checks presence and current size only, not full content. The available state is therefore distinct from verified. Explicit verification reads file chunks using an owned StreamIterator and incremental SHA-256. Cancellation stops the iterator before hash cleanup. Size/modification/canonical-path checks run around hashing. The receipt digest must still match the snapshot before and after checking, or the user is asked to refresh.

History prepareShare rechecks the selected files before returning native file paths; a single intact copy can be prepared independently when another batch file is missing. Files known to be missing/changed/unsafe are not silently shared. The share sheet does not confirm the external destination saved the copies. The original Part 2 immediate receive-screen share function remains available.

No history delete/rename function, database migration, signature generation, receipt rewrite or at-rest encryption was added. A check is against the stored receipt, not proof that a locally edited receipt is authentic. These Dart-level checks are not a race-free defense against a hostile process with write access to the app filesystem. Verification is a point-in-time check and is not persisted as a permanent guarantee.

## UI and lifecycle

Home keeps its original three tabs and selection state; Saved files is an additional route. Its history-screen builder has an injectable default for testability. Nearby keeps both paste and scan; an injectable scanner route allows UI tests without native camera access. Receiver requests and active progress are prioritized ahead of the QR panel so approval is not hidden below a large QR.

History supports search, availability/attention filters, expandable batches, checksum details, verification, per-file or batch export, refresh and cancellation. Loading and check generations ignore stale results after refresh/disposal. Backgrounding cancels read/check work. App-document discovery and the native share action are injectable for tests; real defaults use path_provider and share_plus.

Each selectable checksum has a distinct PageStorageKey under its ExpansionTile. Do not remove these keys: an inner text scroll position otherwise shares the tile's boolean expansion-storage identifier, causing a bool-to-double restoration error.

## Verification and remaining work

97 tests pass: the retained 60, plus 3 history-model, 15 real filesystem/legacy-TLS compatibility, 3 QR-widget, 9 camera/QR-flow and 7 history-UI tests. Camera tests use a test adapter. Native phone permissions/cameras/share sheets and Android/iOS build artifacts are not verified in this Linux environment.

Separate QA rendered real Flutter QR images for two private IPv4 demo codes. A software decoder recovered the exact 98-character payload for both. This is a QR-generation check, not a phone-camera test. Screenshots show test metadata, camera-off UI and an explicitly labeled QR component demo with no live receiver.

Before store release, validate native builds, physical Android-to-Android and Android-to-iPhone transfers, camera permission states, QR distance/lighting, foreground interruption, large files/storage errors, SDK privacy disclosures, signing and final branding. No ad SDK, resumable/background transfer, automatic hotspot management or sent-history database has been added.
