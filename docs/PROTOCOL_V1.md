# ShareBondhu wire protocol v1 — Part 2 baseline

This is an implemented development protocol, not a security certification. The Flutter app targets foreground Android/iOS operation on a private IPv4 LAN. The new code lives in permanent files 6–10. Preserve these endpoints and existing fields when adding later parts.

## Trust and transport

- The receiver generates a fresh RSA-2048 private key and a self-signed certificate for each receiving session, off the UI isolate. The certificate is signed using SHA-256. Keys are not embedded in source, persisted to disk, or sent to the sender.
- All app protocol requests use HTTPS. The sender uses an empty trust context and accepts a certificate only if its DER SHA-256 fingerprint, destination host, and port match the out-of-band pairing code.
- There is no unconditional certificate-accept callback, HTTP fallback, proxy use, or redirect following.
- The pairing code is a bearer capability and the certificate pin. Obtain the entire code directly from the intended receiver via a private, trustworthy channel. Someone who replaces the whole code can direct a sender to a different receiver. Self-reported device names are not identities.
- Public addresses, DNS names and IPv6 are not supported. Private RFC1918 IPv4 and IPv4 link-local addresses are accepted. Loopback is opt-in only in engine tests; the normal UI parser rejects it.
- The listener rejects browser Origin headers and has no CORS allowlist. There is no public directory listing or file-download endpoint.
- TLS protects the network path. Received files are ordinary app-document files, without added at-rest encryption. OS backup policy still applies. No independent security audit has been performed.

## Pairing code

Wire prefix: `SB1.`. The remaining text is unpadded base64url for exactly 70 bytes. The total code length is 98 characters.

| Byte range | Meaning |
|---|---|
| 0–3 | IPv4 address, one byte per octet |
| 4–5 | Listening port, unsigned 16-bit big-endian |
| 6–37 | 32 random bytes of invitation authentication |
| 38–69 | SHA-256 digest of the receiver's DER certificate |

The receiver advertises candidate local addresses and one random listening port. A code is generated for the selected address. New offers need the invitation token, represented as unpadded base64url, in the Authorization Bearer header. Do not log codes, tokens, PEM private keys, or local source URIs.

## Endpoints

| Method | Path pattern | Authorization | Purpose |
|---|---|---|---|
| POST | `/v1/offer` | Invitation token | Validate and ask the receiver to approve an entire batch |
| PUT | `/v1/files/{transferId}/{fileId}` | Accepted-batch upload token | Stream one approved file, stage bytes, return size and SHA-256 |
| POST | `/v1/commit/{transferId}` | Upload token | Verify the sender's complete digest map and atomically expose the saved batch |
| DELETE | `/v1/transfers/{transferId}` | Upload token | Cancel the active uncommitted batch and attempt temporary cleanup |
| GET | `/v1/status/{transferId}` | Upload token | Recover the most recent completed receipt for this live receiver session |

Braced path components are parameters, not literal strings. Transfer and file identifiers are 32 lowercase hexadecimal characters. The IDs have no filesystem-path semantics.

### Offer

JSON fields: `version`, `id`, `senderName`, and `files`. Each file has `id`, `name`, and integer `size`. Platform source URIs, paths, and file bytes are not part of the offer. Filenames are normalized into safe basenames before approval and storage. Names are not executable commands.

Only one pending offer or accepted batch is allowed. The receiver's UI returns an explicit boolean decision. An absent decision, exception, closed session or approval timeout defaults to rejection. No file stream is opened by the sender before acceptance.

Success response: matching `id` and a new `uploadToken`, distinct from the invitation token. The token authorizes only the active batch. Requests are not auto-approved based on sender names.

### Upload

Required content type is application/octet-stream, without Content-Encoding. Content-Length must equal the approved size. Uploads are sequential. Unknown IDs and repeat uploads are rejected.

The sender owns a StreamIterator, hashes each chunk, writes it to the request and awaits flushing. It cancels the iterator on abort before closing hash state. The receiver writes chunks through RandomAccessFile with awaited writes, incremental hashing, size checks and an idle timeout. Neither app path eagerly loads a whole file as one byte array; providers may still make their own temporary copies or cloud downloads.

A successful PUT returns `id`, actual `size`, and `sha256`. This is only a staged-file acknowledgment, not a saved-batch receipt. The sender independently verifies all three values.

### Commit and storage

The JSON commit body contains a `sha256` map keyed by every approved file ID. All file uploads must be finished. Extra or missing digest entries, wrong hashes and incomplete batches cannot commit.

The receiver stages work in a unique receiver-owned directory with an `.incoming-sb1-` prefix. It assigns numbered, sanitized basenames so files with the same display name cannot overwrite each other. It writes `transfer.json`, then renames the staging directory to a unique `received-` directory on the same filesystem. A received event and successful receipt occur only after that rename succeeds.

The app storage root is Documents/ShareBondhu/Received. Wire receipts include version, batch ID, sender name, UTC completion time, and each file's ID/name/size/SHA-256. They never serialize local paths. The local receiver receipt adds in-memory paths for the native share sheet. The stored JSON and file ordering are a foundation for a future history browser.

This is an atomic logical batch publication within app storage, not a promise of recovery from every OS crash, disk failure or power loss. Important copies should be exported and backed up by the user.

### Cancel, errors and uncertain results

Cancel/connection failure before final commit discards the active staging batch, with visible cleanup-error feedback if the filesystem refuses deletion. Original selected files and previously committed batches are never deleted by cancellation.

Final commit can finish concurrently with a stop/cancel. Do not promise that cancellation can retract files already saved. After a lost final response, the sender attempts authenticated receipt recovery. If no definitive receipt is available, the UI reports an uncertain outcome and asks the user to check the receiver before retrying. It does not silently retry a whole batch.

Only the most recent completed receipt is recoverable through the live status endpoint. Stopping the session discards its authentication capability, not the received files. This is not a persistent network history service.

## Limits and timers

- 1–50 files; each up to 2 GiB; total up to 4 GiB.
- JSON bodies/responses limited to 64 KiB and bounded read time.
- Safe filenames limited to 180 UTF-8 bytes before the numeric storage prefix.
- New invitation lifetime: 10 minutes.
- Receiver approval window: 60 seconds; sender response allowance: 75 seconds.
- Transfer input/output idle deadline: 30 seconds. Waiting for the first upload, another upload or commit also has an idle lease.
- Accepted batch overall deadline: 30 minutes.
- Expired invitations do not cut off already accepted work, but no new offer is allowed.
- Staging directories created by this protocol and older than 24 hours are cleaned on receiver start, without following directory symlinks. Confirmed received directories are not purged.

The limits are safeguards for a prototype, not comprehensive denial-of-service resistance on hostile networks. Use a trusted LAN and keep the receiver off when it is not needed.

## Mobile lifecycle and platform configuration

No listener starts merely by opening Home or Receive nearby. Start receiving is explicit. The screen tracks background/hidden/detached state, including the asynchronous storage-lookup startup race, and stops active work when backgrounded. Inactive state alone is not treated as background because system permission dialogs can temporarily make an app inactive.

Android main manifest adds INTERNET and preserves its activity, Flutter metadata and PROCESS_TEXT query. The baseline generated Flutter configuration targets SDK 36. Reassess runtime local-network requirements before changing the target SDK.

iOS Info.plist preserves its existing runner/scene/orientation configuration and adds NSLocalNetworkUsageDescription, UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace. No broad ATS bypass is added. There is no Bonjour discovery, automatic hotspot control, camera scanner, or background service in Part 2.

## Verification boundary

60 automated tests: 28 retained Part 1 tests, 8 protocol-model tests, 19 real loopback TLS/network tests and 5 Part 2 UI/lifecycle tests. Network tests move actual bytes between client and server, read the saved output, test rejection/pinning/cancellation/checksum failures, and clean their temporary directories. Their explicit loopback allowance and approval callbacks are test harness settings, not defaults used by the app UI.

Still unverified in this environment: native Android/iOS compilation, cross-device Wi-Fi/hotspot behavior, mobile permission prompts, actual file-picker integrations, share sheets, large multi-GiB device stress, and release-store compliance.
