# ShareBondhu — Part 2 (File 6–10)

## Full Code + বাংলা ব্যবহার নির্দেশনা

নিজের ব্র্যান্ডের Flutter Android + iPhone file-sharing অ্যাপের দ্বিতীয় ধাপ। **নতুন File 6–10**, সঙ্গে আগের প্রয়োজনীয় ফাইলগুলোর সম্পূর্ণ আপডেট। Part 1-এর selection, duplicate-reference handling, clear confirmation, light/dark theme ও navigation রাখা হয়েছে।

## এবার যা যোগ হয়েছে

- একই private IPv4 Wi-Fi/হটস্পটে manual pairing code দিয়ে সংযোগ।
- প্রতিটি receiving session-এ নতুন RSA-2048 self-signed TLS identity; sender তার certificate fingerprint pin করে। কোনো shared, hardcoded private key নেই।
- Receiver প্রতিটি batch-এর নাম/size দেখে Accept বা Decline করতে পারেন। Device name নিজে লেখা যায়, তাই সেটি পরিচয়ের প্রমাণ নয়।
- পুরো ফাইল RAM-এ না তুলে stream করে পাঠানো ও app documents-এ লেখা। Sender stream cancellation ও output backpressure সামলায়।
- দুই পাশে SHA-256 এবং প্রকৃত byte count যাচাই; সব file যাচাইয়ের পরে batch commit। শুধু 100% upload দেখিয়ে সফল বলা হয় না।
- Cancel, connection failure, approval/idle timeout, incomplete-file cleanup এবং শেষ confirmation হারালে receipt recovery-এর ব্যবস্থা।
- মূল নির্বাচিত ফাইল অপরিবর্তিত থাকে। একই নামের received file-ও unique batch directory ও numbered basename দিয়ে আলাদা থাকে।
- Received copies-এর জন্য system **Share / save copies** button। এতে native share sheet খোলে; কোনো destination-এ save সফল হয়েছে বলে অ্যাপ নিজে দাবি করে না।
- Android INTERNET permission, iOS local-network description ও Files-app document sharing configuration। HTTPS ব্যবহারে broad cleartext/ATS bypass যোগ করা হয়নি।

## গুরুত্বপূর্ণ সীমা

এটি একটি development MVP, store-ready release নয়। এই পরিবেশে static analysis, ৬০টি automated test এবং সত্যিকারের loopback HTTPS/TLS file transfer পরীক্ষা হয়েছে। **Android/iPhone native build, দুই বাস্তব ফোনের Wi-Fi connection, OS file picker, local-network permission prompt ও native share sheet এখানে পরীক্ষা হয়নি। APK/IPA এই ZIP-এ নেই।**

প্রতি batch: ১–৫০টি file, প্রতিটি সর্বোচ্চ **2 GiB**, মোট **4 GiB**। Metadata সর্বোচ্চ 64 KiB। File-provider-এর reported size অনুযায়ী শুরু হয়; বাস্তব stream ভিন্ন হলে transfer ব্যর্থ হবে, ভুলভাবে সফল নয়। Cloud-only file আগে local করতে internet লাগতে পারে।

Pairing code নতুন request-এর জন্য ১০ মিনিট valid। Approval-এর সময় ৬০ সেকেন্ড। Idle transfer-এর সময়সীমা ৩০ সেকেন্ড এবং accepted batch-এর সর্বোচ্চ সময় ৩০ মিনিট। Code expire হলেও আগেই accepted batch তার নিজের সময়সীমার মধ্যে শেষ হতে পারে।

**দুই অ্যাপ সামনে খোলা রাখুন।** Background/lock/screen leave-এ সক্রিয় কাজ বন্ধ করা হয়। Final commit শুরু হয়ে গেলে cancel-এর সময়েও receiver-এ batch saved হয়ে যেতে পারে; অনিশ্চিত confirmation হলে receiver দেখে তারপর retry করুন।

এখনো নেই: QR scanner, automatic discovery/hotspot creation, IPv6-only/public-address support, resumable/background transfer, persistent history browser, advertising এবং production signing। TLS পরিবহনের সুরক্ষা; app documents-এ সংরক্ষিত file-এর জন্য আলাদা at-rest encryption যোগ করা হয়নি। স্বাধীন security audit-ও হয়নি। নিজের trusted LAN-এ আগে পরীক্ষা করুন।

## চালু করার নিয়ম

পরীক্ষিত toolchain: **Flutter 3.47.2 / Dart 3.13.2**। Minimum constraints: Flutter 3.47.0 / Dart 3.13.0। Direct dependencies pin করা আছে এবং `pubspec.lock` দেওয়া হয়েছে। Flutter SDK ও platform toolchain আলাদাভাবে install করতে হবে।

Flutter install: https://docs.flutter.dev/install

Android Studio: https://developer.android.com/studio

ZIP extract করে `sharebondhu` directory-তে terminal খুলুন:

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

আগের Part চলতে থাকলে **পুরো app stop করে rebuild করুন**। নতুন native plugins/permissions শুধু hot reload দিয়ে যোগ হবে না।

Android-এর জন্য Android Studio SDK/toolchain ও compatible Java 17+ JDK ব্যবহার করুন; Java 11 নয়। এই Flutter SDK-এর generated Android configuration target/compile SDK 36 এবং minimum SDK 24 ব্যবহার করছে। Target SDK ভবিষ্যতে বাড়ালে তখনকার local-network permission requirements আবার যাচাই করতে হবে।

নিজের PC-তে debug APK তৈরি করতে:

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`। Android release template এখনো debug signing ব্যবহার করে; সেটি store-এ প্রকাশ করবেন না।

iPhone-এর জন্য Mac ও compatible Xcode প্রয়োজন। Generated iOS deployment target 15.0। বাস্তব iPhone-এ Xcode signing team লাগবে। Windows/Linux থেকে স্থানীয় iOS build হবে না। Mac-এ Simulator খুলতে:

```bash
open -a Simulator
flutter devices
flutter run
```

## দুই ফোনে ব্যবহার: প্রথম পরীক্ষাটি ছোট file দিয়ে করুন

1. দুই ফোনে app install/run করুন এবং একই private IPv4 Wi-Fi-তে রাখুন। অথবা এমন hotspot ব্যবহার করুন যেখানে device-to-device traffic অনুমোদিত। Guest Wi-Fi/client isolation/VPN সংযোগে বাধা দিতে পারে।
2. **গ্রহণকারী ফোন:** Home → **Receive files → Start receiving**। iOS local-network permission চাইলে বুঝে অনুমতি দিন।
3. একাধিক address দেখালে অন্য ফোন থেকে পৌঁছানো যায় এমন Wi-Fi address বাছুন। **Copy code** চাপুন।
4. **Copy code শুধু সেই ফোনের clipboard-এ কপি করে; অন্য ফোনে নিজে থেকে পৌঁছায় না।** এই Part-এর ৯৮ অক্ষরের সম্পূর্ণ `SB1` code অন্য ফোনে নিজে লিখুন বা আপনার পছন্দের private মাধ্যম দিয়ে দিন। Code-এ authentication secret আছে; public post করবেন না। QR pairing পরের Part-এ যোগ হবে। Third-party মাধ্যমে code দেওয়ার জন্য internet লাগতে পারে; file-transfer channel নিজে local।
5. **পাঠানোর ফোন:** Select files → Files tab → **Send selected**। Device name লিখুন, receiver code paste করুন, **Ask to send** চাপুন।
6. **গ্রহণকারী ফোন:** নাম/size এবং sender যাচাই করে **Accept files** চাপুন। Device name self-reported। অচেনা request Decline করুন।
7. Sender-এ **Delivery confirmed** এবং receiver-এ **Saved and verified** দেখা পর্যন্ত অপেক্ষা করুন। Progress-এর byte count final delivery receipt নয়।
8. Receiver-এর **Share / save copies** দিয়ে system share sheet খুলুন। iPhone-এ Save to Files বেছে নেওয়া যায়। Android-এ available destination installed app-এর ওপর নির্ভর করে।

Received data থাকে app Documents-এর `ShareBondhu/Received` directory-তে। iOS-এ Files app-এ ShareBondhu document folder-ও দেখা যেতে পারে। Android-এ এগুলো app-specific documents; public Downloads-এ নিজে থেকে লেখা হয় না। Export গুরুত্বপূর্ণ file, বিশেষ করে uninstall/clear app data-এর আগে। এই Part-এ history browser নেই; receipt card বর্তমান screen/session-এর জন্য। Saved data disk-এ থাকে, কিন্তু app data মুছলে তা হারাতে পারেন। Device backup/cloud behavior OS settings-এর ওপর নির্ভর করে।

## Part 1 থেকে কী বদলেছে

| File | Path | অবস্থা |
|---|---|---|
| 1 | `pubspec.yaml` | UPDATED — version 0.2.0+2, TLS/storage/share dependencies যোগ |
| 2 | `lib/main.dart` | UNCHANGED — আগের সঙ্গে byte-for-byte একই |
| 3 | `lib/models/share_file.dart` | UNCHANGED — আগের সঙ্গে byte-for-byte একই |
| 4 | `lib/screens/home_screen.dart` | UPDATED — পুরোনো logic রেখে send/receive route ও guide যোগ |
| 5 | `test/widget_test.dart` | UPDATED — আগের ২৮টি test রেখে আরও ৩২টি test যোগ |
| 6 | `lib/models/transfer_models.dart` | NEW — pairing, limits, protocol models, receipts |
| 7 | `lib/services/local_transfer_service.dart` | NEW — TLS receiver/sender, streaming, consent, commit ও cleanup |
| 8 | `lib/screens/nearby_screen.dart` | NEW — send/receive interface ও foreground lifecycle |
| 9 | `android/app/src/main/AndroidManifest.xml` | FIRST CUSTOMIZATION — permission/name; আগের entries অক্ষুণ্ণ |
| 10 | `ios/Runner/Info.plist` | FIRST CUSTOMIZATION — local-network/Files support; আগের entries অক্ষুণ্ণ |

`pubspec.lock` ও plugin registrants tooling দিয়ে regenerate হয়েছে। এগুলো numbered authored source নয়। ZIP-এ standard Android/iOS scaffold, assets ও Gradle wrapper-ও আছে। SDK, package caches, compiled output ও machine-specific generated paths বাদ রাখা হয়েছে; Flutter tools সেগুলো পুনরায় তৈরি করবে।

## ফাইলগুলো

- `docs/PART_02_FULL_CODE.md`: নতুন File 6–10 এবং আগের File 1–5-এর সম্পূর্ণ বর্তমান কোড; কোনো implementation বাদ নেই।
- `docs/PROTOCOL_V1.md`: endpoint, trust model ও lifecycle।
- `docs/FILE_INDEX.md`: স্থায়ী file numbers ও পরের Part-এর compatibility notes।
- `docs/PART_02_TEST_RESULTS.txt`: বর্তমান analysis ও ৬০টি test-এর output।
- `docs/FILE_INVENTORY.txt`, `docs/SHA256SUMS.txt`: এই ZIP-এর inventory ও checksum।
- `docs/part02-preview.png`: test-rendered UI; ছবি/নাম/size test data, physical-phone screenshot নয়।
- Part 1 guide ও historical reports আলাদা নামে রাখা হয়েছে। Part 1 archive ও তার standalone full-code guide বদলানো হয়নি।

ShareBondhu নাম ও `com.sharebondhu.sharebondhu` ID এখনো অস্থায়ী। Publishing-এর আগে brand availability, application ID, launcher icons, signing ও privacy/compliance যাচাই বাকি।


## সম্পূর্ণ কোড — নতুন File 6–10

এই অংশের প্রতিটি code block সংশ্লিষ্ট ফাইলের পুরো content। এখানে কোনো সংক্ষিপ্ত implementation বা বাদ দেওয়া function নেই। পরের বিভাগে আগের File 1–5-এর পূর্ণ বর্তমান সংস্করণও আছে, তাই নতুন ZIP ছাড়াও সব numbered file এক জায়গায় পাবেন। নতুন ফাইলগুলো মূল project root-এর relative path অনুযায়ী তৈরি করুন।

### File 6 — `lib/models/transfer_models.dart` — NEW

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'share_file.dart';

abstract final class TransferLimits {
  static const int protocolVersion = 1;
  static const int maxFiles = 50;
  static const int maxFileBytes = 2 * 1024 * 1024 * 1024;
  static const int maxBatchBytes = 4 * 1024 * 1024 * 1024;
  static const int maxMetadataBytes = 64 * 1024;
  static const int maxNameBytes = 180;
}

class TransferException implements Exception {
  const TransferException(this.message, {this.outcomeUncertain = false});

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => message;
}

class TransferCancelled extends TransferException {
  const TransferCancelled()
    : super('Transfer canceled. Files already confirmed as saved are kept.');
}

String randomToken([int byteCount = 32]) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String randomTransferId() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool secretEquals(String first, String second) {
  if (first.length != second.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < first.length; i += 1) {
    difference |= first.codeUnitAt(i) ^ second.codeUnitAt(i);
  }
  return difference == 0;
}

bool isLocalIpv4(String host, {bool allowLoopback = false}) {
  final address = InternetAddress.tryParse(host);
  if (address == null ||
      address.type != InternetAddressType.IPv4 ||
      address.address != host) {
    return false;
  }
  final bytes = address.rawAddress;
  if (allowLoopback && bytes[0] == 127) {
    return true;
  }
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

String _boundedText(String value, int maxBytes) {
  final buffer = StringBuffer();
  var byteCount = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (byteCount + length > maxBytes) {
      break;
    }
    buffer.write(character);
    byteCount += length;
  }
  return buffer.toString();
}

String safeFileName(String input) {
  var name = input
      .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_')
      .replaceAll(RegExp('[\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]'), '')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  name = _boundedText(name, TransferLimits.maxNameBytes).trim();
  if (name.isEmpty) {
    name = 'file';
  }
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    name = '_$name';
  }
  return _boundedText(
    name,
    TransferLimits.maxNameBytes,
  ).replaceAll(RegExp(r'[. ]+$'), '');
}

String safeDeviceName(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp('[\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]'), '')
      .trim();
  final name = _boundedText(cleaned, 80);
  return name.isEmpty ? 'Nearby device' : name;
}

class PairingCode {
  PairingCode({
    required this.host,
    required this.port,
    required this.token,
    required this.fingerprint,
    bool allowLoopback = false,
  }) {
    if (!isLocalIpv4(host, allowLoopback: allowLoopback) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        base64Url.decode(base64Url.normalize(token)).length != 32 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const TransferException(
        'That pairing code is invalid. Copy it again.',
      );
    }
  }

  final String host;
  final int port;
  final String token;
  final String fingerprint;

  factory PairingCode.parse(String input, {bool allowLoopback = false}) {
    try {
      final value = input.trim();
      if (!value.startsWith('SB1.') || value.length != 98) {
        throw const FormatException();
      }
      final bytes = base64Url.decode(base64Url.normalize(value.substring(4)));
      if (bytes.length != 70) {
        throw const FormatException();
      }
      final data = ByteData.sublistView(bytes);
      return PairingCode(
        host: bytes.sublist(0, 4).join('.'),
        port: data.getUint16(4),
        token: base64Url.encode(bytes.sublist(6, 38)).replaceAll('=', ''),
        fingerprint: bytes
            .sublist(38)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
        allowLoopback: allowLoopback,
      );
    } catch (_) {
      throw const TransferException(
        'Use the complete SB1 pairing code from a nearby receiver. '
        'Only private IPv4 Wi-Fi or hotspot addresses are supported.',
      );
    }
  }

  String encode() {
    final bytes = Uint8List(70);
    bytes.setRange(0, 4, InternetAddress(host).rawAddress);
    ByteData.sublistView(bytes).setUint16(4, port);
    bytes.setRange(6, 38, base64Url.decode(base64Url.normalize(token)));
    for (var i = 0; i < 32; i += 1) {
      bytes[38 + i] = int.parse(
        fingerprint.substring(i * 2, i * 2 + 2),
        radix: 16,
      );
    }
    return 'SB1.${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  Uri endpoint(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  @override
  String toString() => 'PairingCode($host:$port, credentials redacted)';
}

class ReceiverSession {
  ReceiverSession({
    required Iterable<String> addresses,
    required this.port,
    required this.token,
    required this.fingerprint,
    required this.expiresAt,
    this.allowLoopback = false,
  }) : addresses = List<String>.unmodifiable(addresses);

  final List<String> addresses;
  final int port;
  final String token;
  final String fingerprint;
  final DateTime expiresAt;
  final bool allowLoopback;

  PairingCode codeFor(String host) {
    if (!addresses.contains(host)) {
      throw const TransferException('Choose an address from this device.');
    }
    return PairingCode(
      host: host,
      port: port,
      token: token,
      fingerprint: fingerprint,
      allowLoopback: allowLoopback,
    );
  }
}

class OfferedFile {
  OfferedFile({required this.id, required String name, required this.size})
    : name = safeFileName(name) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        name.trim().isEmpty ||
        utf8.encode(name).length > 1024 ||
        size < 0 ||
        size > TransferLimits.maxFileBytes) {
      throw const TransferException(
        'Invalid file metadata. Each file must be at most 2 GiB.',
      );
    }
  }

  final String id;
  final String name;
  final int size;

  factory OfferedFile.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['size'] is! int) {
      throw const TransferException('Invalid file metadata.');
    }
    return OfferedFile(
      id: value['id'] as String,
      name: value['name'] as String,
      size: value['size'] as int,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'size': size,
  };
}

class IncomingOffer {
  IncomingOffer({
    required this.id,
    required String senderName,
    required this.remoteAddress,
    required Iterable<OfferedFile> files,
  }) : senderName = safeDeviceName(senderName),
       files = List<OfferedFile>.unmodifiable(files) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        this.files.isEmpty ||
        this.files.length > TransferLimits.maxFiles ||
        this.files.map((file) => file.id).toSet().length != this.files.length ||
        totalBytes > TransferLimits.maxBatchBytes) {
      throw const TransferException(
        'Choose 1 to 50 files, at most 2 GiB each and 4 GiB in total.',
      );
    }
  }

  final String id;
  final String senderName;
  final String remoteAddress;
  final List<OfferedFile> files;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);

  factory IncomingOffer.fromJson(
    Map<String, dynamic> value, {
    required String remoteAddress,
  }) {
    if (value['version'] != TransferLimits.protocolVersion ||
        value['id'] is! String ||
        value['senderName'] is! String ||
        value['files'] is! List ||
        (value['files'] as List).length > TransferLimits.maxFiles) {
      throw const TransferException('Unsupported or invalid transfer request.');
    }
    return IncomingOffer(
      id: value['id'] as String,
      senderName: value['senderName'] as String,
      remoteAddress: remoteAddress,
      files: (value['files'] as List).map(OfferedFile.fromJson),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'version': TransferLimits.protocolVersion,
    'id': id,
    'senderName': senderName,
    'files': files.map((file) => file.toJson()).toList(),
  };
}

enum TransferPhase {
  waiting,
  connecting,
  awaitingApproval,
  sending,
  receiving,
  verifying,
  completed,
  rejected,
  canceled,
  failed,
}

class TransferProgress {
  const TransferProgress({
    required this.phase,
    required this.message,
    this.totalBytes = 0,
    this.processedBytes = 0,
    this.totalFiles = 0,
    this.completedFiles = 0,
    this.fileName,
  });

  final TransferPhase phase;
  final String message;
  final int totalBytes;
  final int processedBytes;
  final int totalFiles;
  final int completedFiles;
  final String? fileName;

  double get fraction {
    if (phase == TransferPhase.completed) {
      return 1;
    }
    return totalBytes == 0 ? 0 : (processedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get indeterminate =>
      phase == TransferPhase.connecting ||
      phase == TransferPhase.awaitingApproval ||
      phase == TransferPhase.verifying;
}

class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.digest,
    this.localPath,
  });

  final String id;
  final String name;
  final int size;
  final String digest;
  final String? localPath;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'size': size,
    'sha256': digest,
  };
}

class TransferReceipt {
  TransferReceipt({
    required this.id,
    required this.senderName,
    required this.completedAt,
    required Iterable<ReceivedFile> files,
  }) : files = List<ReceivedFile>.unmodifiable(files);

  final String id;
  final String senderName;
  final DateTime completedAt;
  final List<ReceivedFile> files;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);

  Map<String, Object> toJson() => <String, Object>{
    'version': TransferLimits.protocolVersion,
    'id': id,
    'senderName': senderName,
    'completedAt': completedAt.toUtc().toIso8601String(),
    'files': files.map((file) => file.toJson()).toList(),
  };

  factory TransferReceipt.fromJson(Map<String, dynamic> data) {
    final entries = data['files'];
    if (data['version'] != TransferLimits.protocolVersion ||
        data['id'] is! String ||
        data['senderName'] is! String ||
        data['completedAt'] is! String ||
        entries is! List ||
        entries.isEmpty ||
        entries.length > TransferLimits.maxFiles) {
      throw const TransferException(
        'The receiver returned an invalid receipt.',
      );
    }
    final files = <ReceivedFile>[];
    for (final entry in entries) {
      final descriptor = OfferedFile.fromJson(entry);
      if (entry is! Map<String, dynamic> ||
          entry['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['sha256'] as String)) {
        throw const TransferException(
          'The receiver returned an invalid checksum.',
        );
      }
      files.add(
        ReceivedFile(
          id: descriptor.id,
          name: descriptor.name,
          size: descriptor.size,
          digest: entry['sha256'] as String,
        ),
      );
    }
    return TransferReceipt(
      id: data['id'] as String,
      senderName: safeDeviceName(data['senderName'] as String),
      completedAt: DateTime.parse(data['completedAt'] as String),
      files: files,
    );
  }
}

IncomingOffer createOutgoingOffer(List<ShareFile> files, String senderName) {
  return IncomingOffer(
    id: randomTransferId(),
    senderName: senderName,
    remoteAddress: '',
    files: files.map(
      (file) =>
          OfferedFile(id: randomTransferId(), name: file.name, size: file.size),
    ),
  );
}
```

### File 7 — `lib/services/local_transfer_service.dart` — NEW

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart'
    show CryptoUtils, X509Utils, RSAPrivateKey, RSAPublicKey;
import 'package:crypto/crypto.dart';

import '../models/share_file.dart';
import '../models/transfer_models.dart';

class TlsIdentity {
  const TlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  static Future<TlsIdentity> generate() => Isolate.run(_generateTlsIdentity);
}

TlsIdentity _generateTlsIdentity() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    <String, String>{'CN': 'ShareBondhu local session'},
    privateKey,
    publicKey,
  );
  final certificate = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    1,
    cA: false,
    serialNumber: BigInt.parse(randomTransferId(), radix: 16).toString(),
    notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  );
  final der = CryptoUtils.getBytesFromPEMString(certificate);
  return TlsIdentity(
    certificatePem: certificate,
    privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    fingerprint: sha256.convert(der).toString(),
  );
}

Future<List<String>> localIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: true,
  );
  final addresses = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (isLocalIpv4(address.address)) {
        addresses.add(address.address);
      }
    }
  }
  return addresses.toList()..sort();
}

Future<Map<String, dynamic>> readBoundedJson(
  Stream<List<int>> source, {
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = TransferLimits.maxMetadataBytes,
}) async {
  final iterator = StreamIterator<List<int>>(source);
  final bytes = BytesBuilder(copy: false);
  final clock = Stopwatch()..start();
  try {
    while (true) {
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Metadata deadline exceeded.');
      }
      if (!await iterator.moveNext().timeout(remaining)) {
        break;
      }
      if (bytes.length + iterator.current.length > maxBytes) {
        throw const TransferException('The metadata message is too large.');
      }
      bytes.add(iterator.current);
    }
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map<String, dynamic>) {
      throw const TransferException('Expected a JSON object.');
    }
    return decoded;
  } finally {
    await iterator.cancel();
  }
}

HttpClient createPinnedClient(
  PairingCode code, {
  Duration connectionTimeout = const Duration(seconds: 10),
}) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = const Duration(seconds: 15);
  client.maxConnectionsPerHost = 2;
  client.autoUncompress = false;
  client.findProxy = (_) => 'DIRECT';
  client.badCertificateCallback = (certificate, host, port) {
    return host == code.host &&
        port == code.port &&
        secretEquals(
          sha256.convert(certificate.der).toString(),
          code.fingerprint,
        );
  };
  return client;
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _HttpFailure extends TransferException {
  const _HttpFailure(this.status, super.message);

  final int status;
}

class _ReceivingBatch {
  _ReceivingBatch({
    required this.offer,
    required this.token,
    required this.directory,
  });

  final IncomingOffer offer;
  final String token;
  final Directory directory;
  final Map<String, String> digests = <String, String>{};
  HttpRequest? uploadRequest;
  Future<void> ioDone = Future<void>.value();
  Future<void>? cleanup;
  Timer? timer;
  Timer? idleTimer;
  bool cleanupSucceeded = true;
  bool canceled = false;
  bool uploading = false;
  bool committing = false;
  bool committed = false;
  int bytesReceived = 0;
}

class LocalReceiver {
  LocalReceiver({
    required this.storageRoot,
    required this.onOffer,
    this.onProgress,
    this.onReceived,
    this.onStopped,
    this.identityFactory = TlsIdentity.generate,
    this.inviteLifetime = const Duration(minutes: 10),
    this.approvalTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(seconds: 30),
    this.batchTimeout = const Duration(minutes: 30),
    this.allowLoopback = false,
  }) {
    for (final duration in <Duration>[
      inviteLifetime,
      approvalTimeout,
      idleTimeout,
      batchTimeout,
    ]) {
      if (duration <= Duration.zero) {
        throw ArgumentError('Timeouts must be positive.');
      }
    }
  }

  final Directory storageRoot;
  final Future<bool> Function(IncomingOffer offer) onOffer;
  final void Function(TransferProgress progress)? onProgress;
  final void Function(TransferReceipt receipt)? onReceived;
  final void Function(String reason)? onStopped;
  final Future<TlsIdentity> Function() identityFactory;
  final Duration inviteLifetime;
  final Duration approvalTimeout;
  final Duration idleTimeout;
  final Duration batchTimeout;
  final bool allowLoopback;

  HttpServer? _server;
  ReceiverSession? _session;
  _ReceivingBatch? _batch;
  TransferReceipt? _lastReceipt;
  String? _lastReceiptToken;
  Timer? _inviteTimer;
  Completer<bool>? _approval;
  Future<void>? _stopFuture;
  final Set<HttpRequest> _requests = <HttpRequest>{};
  bool _starting = false;
  bool _closed = false;
  bool _offerBusy = false;

  bool get isRunning => _server != null && !_closed;
  ReceiverSession? get session => _session;
  bool get _invitationValid =>
      _session != null && DateTime.now().isBefore(_session!.expiresAt);

  Future<ReceiverSession> start({
    InternetAddress? bindAddress,
    List<String>? advertisedAddresses,
  }) async {
    if (_starting || _server != null || _closed) {
      throw const TransferException(
        'Create a new receiver to start another session.',
      );
    }
    _starting = true;
    try {
      final addresses = advertisedAddresses ?? await localIpv4Addresses();
      if (addresses.isEmpty ||
          addresses.any(
            (host) => !isLocalIpv4(host, allowLoopback: allowLoopback),
          )) {
        throw const TransferException(
          'No supported Wi-Fi address was found. Connect to a private IPv4 '
          'Wi-Fi or hotspot, then try again.',
        );
      }
      final identity = await identityFactory();
      if (_closed) {
        throw const TransferCancelled();
      }
      await storageRoot.create(recursive: true);
      await _removeOldStaging();
      final context = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
      final server = await HttpServer.bindSecure(
        bindAddress ?? InternetAddress.anyIPv4,
        0,
        context,
        backlog: 16,
      );
      if (_closed) {
        await server.close(force: true);
        throw const TransferCancelled();
      }
      server.autoCompress = false;
      server.idleTimeout = idleTimeout;
      _server = server;
      final session = ReceiverSession(
        addresses: addresses,
        port: server.port,
        token: randomToken(),
        fingerprint: identity.fingerprint,
        expiresAt: DateTime.now().add(inviteLifetime),
        allowLoopback: allowLoopback,
      );
      _session = session;
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error) {
          // A failed TLS connection must not terminate the whole listener.
        },
        cancelOnError: false,
      );
      _inviteTimer = Timer(inviteLifetime, () {
        if (_approval != null && !_approval!.isCompleted) {
          _approval!.complete(false);
        }
        _stopIfExpired();
      });
      _emit(
        const TransferProgress(
          phase: TransferPhase.waiting,
          message: 'Waiting for a sender. Every batch needs your approval.',
        ),
      );
      return session;
    } finally {
      _starting = false;
    }
  }

  Future<void> _removeOldStaging() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entity in storageRoot.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (entity is Directory &&
          RegExp(r'^\.incoming-sb1-[a-f0-9]{32}-[A-Za-z0-9]+$')
              .hasMatch(name)) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  void _emit(TransferProgress progress) => onProgress?.call(progress);

  void _stopIfExpired() {
    if (isRunning && !_invitationValid && _batch == null && !_offerBusy) {
      unawaited(stop(reason: 'The pairing code expired. Start a new session.'));
    }
  }

  bool _authorized(HttpRequest request, String token) => secretEquals(
    request.headers.value(HttpHeaders.authorizationHeader) ?? '',
    'Bearer $token',
  );

  Future<void> _handle(HttpRequest request) async {
    _requests.add(request);
    unawaited(
      request.response.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    try {
      if (!isRunning) {
        throw const _HttpFailure(503, 'The receiver has stopped.');
      }
      final remote = request.connectionInfo?.remoteAddress.address ?? '';
      if (!isLocalIpv4(remote, allowLoopback: allowLoopback) ||
          request.headers.value('origin') != null ||
          request.uri.hasQuery) {
        throw const _HttpFailure(
          403,
          'Only native local-network requests are accepted.',
        );
      }
      final parts = request.uri.pathSegments;
      if (request.method == 'POST' && request.uri.path == '/v1/offer') {
        await _handleOffer(request, remote);
        return;
      }
      if (parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'status' &&
          request.method == 'GET') {
        final receipt = _lastReceipt;
        if (receipt == null ||
            receipt.id != parts[2] ||
            !_authorized(request, _lastReceiptToken ?? '')) {
          throw const _HttpFailure(404, 'No completed receipt is available.');
        }
        await _reply(request, 200, receipt.toJson());
        return;
      }
      final isUpload =
          parts.length == 4 &&
          parts[0] == 'v1' &&
          parts[1] == 'files' &&
          request.method == 'PUT';
      final isCommit =
          parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'commit' &&
          request.method == 'POST';
      final isCancel =
          parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'transfers' &&
          request.method == 'DELETE';
      if (!isUpload && !isCommit && !isCancel) {
        throw const _HttpFailure(404, 'Unknown endpoint.');
      }
      final batch = _batch;
      if (batch == null ||
          batch.offer.id != parts[2] ||
          !_authorized(request, batch.token)) {
        throw const _HttpFailure(401, 'This transfer is not authorized.');
      }
      if (batch.canceled) {
        throw const _HttpFailure(410, 'This transfer has ended.');
      }
      if (isUpload) {
        await _handleUpload(request, batch, parts[3]);
      } else if (isCommit) {
        await _handleCommit(request, batch);
      } else {
        await _discardBatch(batch);
        _emit(
          TransferProgress(
            phase: TransferPhase.canceled,
            message: batch.cleanupSucceeded
                ? 'Sender canceled. Uncommitted files were discarded.'
                : 'Sender canceled, but temporary-file cleanup needs attention.',
          ),
        );
        await _reply(request, 200, <String, Object>{
          'canceled': true,
          'cleanupComplete': batch.cleanupSucceeded,
        });
      }
    } on _HttpFailure catch (error) {
      await _reply(request, error.status, <String, Object>{
        'error': error.message,
      });
    } on TransferException catch (error) {
      await _reply(request, 422, <String, Object>{'error': error.message});
    } on TimeoutException {
      await _reply(request, 408, <String, Object>{
        'error': 'The request timed out.',
      });
    } catch (_) {
      await _reply(request, 500, <String, Object>{
        'error': 'Transfer failed. Check the connection and available storage.',
      });
    } finally {
      _requests.remove(request);
    }
  }

  Future<void> _handleOffer(HttpRequest request, String remote) async {
    if (!_authorized(request, _session!.token)) {
      throw const _HttpFailure(
        401,
        'The pairing code is not valid for this receiver.',
      );
    }
    if (!_invitationValid) {
      throw const _HttpFailure(410, 'The pairing code has expired.');
    }
    if (_offerBusy || _batch != null) {
      throw const _HttpFailure(
        409,
        'The receiver is busy with another request.',
      );
    }
    if (request.headers.contentType?.mimeType != 'application/json' ||
        request.contentLength > TransferLimits.maxMetadataBytes) {
      throw const _HttpFailure(400, 'Invalid offer content.');
    }
    _offerBusy = true;
    try {
      final offer = IncomingOffer.fromJson(
        await readBoundedJson(request),
        remoteAddress: remote,
      );
      if (!isRunning || !_invitationValid) {
        throw const _HttpFailure(410, 'The receiving session has ended.');
      }
      _emit(
        TransferProgress(
          phase: TransferPhase.awaitingApproval,
          message: 'An incoming batch is waiting for your decision.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      final decision = Completer<bool>();
      _approval = decision;
      Future<bool>.sync(() => onOffer(offer)).then(
        (accepted) {
          if (!decision.isCompleted) {
            decision.complete(accepted);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!decision.isCompleted) {
            decision.complete(false);
          }
        },
      );
      final accepted = await decision.future.timeout(
        approvalTimeout,
        onTimeout: () {
          if (!decision.isCompleted) {
            decision.complete(false);
          }
          return false;
        },
      );
      _approval = null;
      if (!accepted || !isRunning || !_invitationValid) {
        _emit(
          const TransferProgress(
            phase: TransferPhase.rejected,
            message: 'The request was declined, expired, or closed.',
          ),
        );
        throw const _HttpFailure(
          403,
          'The receiver declined the request or it expired.',
        );
      }
      final directory = await storageRoot.createTemp(
        '.incoming-sb1-${randomTransferId()}-',
      );
      if (!isRunning) {
        await directory.delete(recursive: true);
        throw const _HttpFailure(410, 'The receiver has stopped.');
      }
      final batch = _ReceivingBatch(
        offer: offer,
        token: randomToken(),
        directory: directory,
      );
      _batch = batch;
      _armBatchIdleTimer(batch);
      batch.timer = Timer(batchTimeout, () {
        unawaited(
          _discardBatch(batch).then((_) {
            _emit(
              const TransferProgress(
                phase: TransferPhase.failed,
                message: 'Transfer deadline exceeded. Start again.',
              ),
            );
          }),
        );
      });
      _emit(
        TransferProgress(
          phase: TransferPhase.receiving,
          message: 'Approved. Waiting for file bytes.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      await _reply(request, 200, <String, Object>{
        'id': offer.id,
        'uploadToken': batch.token,
      });
    } finally {
      _offerBusy = false;
      _approval = null;
      _stopIfExpired();
    }
  }

  void _armBatchIdleTimer(_ReceivingBatch batch) {
    batch.idleTimer?.cancel();
    batch.idleTimer = Timer(idleTimeout, () {
      unawaited(
        _discardBatch(batch).then((_) {
          if (batch.cleanupSucceeded && !_closed) {
            _emit(
              const TransferProgress(
                phase: TransferPhase.failed,
                message: 'No transfer data arrived in time. Start again.',
              ),
            );
          }
        }),
      );
    });
  }

  Future<void> _handleUpload(
    HttpRequest request,
    _ReceivingBatch batch,
    String fileId,
  ) async {
    if (batch.uploading || batch.committing) {
      throw const _HttpFailure(409, 'Only one file can be uploaded at a time.');
    }
    final matches = batch.offer.files.where((file) => file.id == fileId);
    if (matches.isEmpty || batch.digests.containsKey(fileId)) {
      throw const _HttpFailure(
        409,
        'This file is unknown or already uploaded.',
      );
    }
    final file = matches.first;
    if (request.contentLength != file.size ||
        request.headers.contentType?.mimeType != 'application/octet-stream' ||
        request.headers.value(HttpHeaders.contentEncodingHeader) != null) {
      throw const _HttpFailure(
        400,
        'The upload length or content type is invalid.',
      );
    }
    batch.idleTimer?.cancel();
    batch.uploading = true;
    batch.uploadRequest = request;
    final io = Completer<void>();
    batch.ioDone = io.future;
    RandomAccessFile? output;
    final digestOutput = _DigestOutput();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    var failed = true;
    var digestClosed = false;
    var count = 0;
    try {
      output = await File('${batch.directory.path}/${file.id}.part')
          .open(mode: FileMode.write);
      await for (final chunk in request.timeout(idleTimeout)) {
        if (batch.canceled || !isRunning) {
          throw const TransferCancelled();
        }
        count += chunk.length;
        if (count > file.size) {
          throw const TransferException(
            'The sender exceeded the approved file size.',
          );
        }
        await output.writeFrom(chunk);
        digestInput.add(chunk);
        batch.bytesReceived += chunk.length;
        _emit(
          TransferProgress(
            phase: TransferPhase.receiving,
            message: 'Receiving encrypted file bytes.',
            totalBytes: batch.offer.totalBytes,
            processedBytes: batch.bytesReceived,
            totalFiles: batch.offer.files.length,
            completedFiles: batch.digests.length,
            fileName: file.name,
          ),
        );
      }
      if (batch.canceled || !isRunning || count != file.size) {
        throw const TransferException(
          'The file ended before all approved bytes arrived.',
        );
      }
      await output.flush();
      await output.close();
      output = null;
      digestInput.close();
      digestClosed = true;
      final digest = digestOutput.value!.toString();
      batch.digests[file.id] = digest;
      _armBatchIdleTimer(batch);
      failed = false;
      await _reply(request, 200, <String, Object>{
        'id': file.id,
        'size': count,
        'sha256': digest,
      });
    } finally {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
      if (!digestClosed) {
        digestInput.close();
      }
      batch.uploading = false;
      batch.uploadRequest = null;
      io.complete();
      if (failed) {
        await _discardBatch(batch);
        if (!_closed && batch.cleanupSucceeded) {
          _emit(
            const TransferProgress(
              phase: TransferPhase.failed,
              message: 'The upload stopped. Uncommitted files were discarded.',
            ),
          );
        }
      }
    }
  }

  Future<void> _handleCommit(HttpRequest request, _ReceivingBatch batch) async {
    if (batch.uploading ||
        batch.committing ||
        batch.digests.length != batch.offer.files.length) {
      throw const _HttpFailure(
        409,
        'All files must finish uploading before commit.',
      );
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const _HttpFailure(400, 'Invalid commit content.');
    }
    batch.idleTimer?.cancel();
    batch.committing = true;
    final io = Completer<void>();
    batch.ioDone = io.future;
    var success = false;
    try {
      final data = await readBoundedJson(request);
      final hashes = data['sha256'];
      if (hashes is! Map<String, dynamic> ||
          hashes.length != batch.digests.length) {
        throw const TransferException('The final checksum list is invalid.');
      }
      for (final file in batch.offer.files) {
        if (hashes[file.id] is! String ||
            !secretEquals(hashes[file.id] as String, batch.digests[file.id]!)) {
          throw const TransferException(
            'A file checksum did not match. Nothing was committed.',
          );
        }
      }
      if (batch.canceled || !isRunning) {
        throw const TransferCancelled();
      }
      _emit(
        TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Checksums match. Saving the complete batch.',
          totalBytes: batch.offer.totalBytes,
          processedBytes: batch.bytesReceived,
          totalFiles: batch.offer.files.length,
          completedFiles: batch.offer.files.length,
        ),
      );
      final destination = '${storageRoot.path}/received-${randomTransferId()}';
      if (await Directory(destination).exists()) {
        throw const TransferException(
          'Choose a new transfer session and try again.',
        );
      }
      final received = <ReceivedFile>[];
      for (var index = 0; index < batch.offer.files.length; index += 1) {
        final file = batch.offer.files[index];
        final savedName =
            '${(index + 1).toString().padLeft(3, '0')}_${file.name}';
        await File('${batch.directory.path}/${file.id}.part')
            .rename('${batch.directory.path}/$savedName');
        received.add(
          ReceivedFile(
            id: file.id,
            name: file.name,
            size: file.size,
            digest: batch.digests[file.id]!,
            localPath: '$destination/$savedName',
          ),
        );
      }
      final receipt = TransferReceipt(
        id: batch.offer.id,
        senderName: batch.offer.senderName,
        completedAt: DateTime.now().toUtc(),
        files: received,
      );
      await File('${batch.directory.path}/transfer.json')
          .writeAsString(jsonEncode(receipt.toJson()), flush: true);
      await batch.directory.rename(destination);
      batch.committed = true;
      success = true;
      _lastReceipt = receipt;
      _lastReceiptToken = batch.token;
      _emit(
        TransferProgress(
          phase: TransferPhase.completed,
          message: 'Files saved. SHA-256 checksums match the sender.',
          totalBytes: receipt.totalBytes,
          processedBytes: receipt.totalBytes,
          totalFiles: receipt.files.length,
          completedFiles: receipt.files.length,
        ),
      );
      onReceived?.call(receipt);
      await _reply(request, 200, receipt.toJson());
    } finally {
      batch.committing = false;
      io.complete();
      if (!success) {
        await _discardBatch(batch);
        if (!_closed && batch.cleanupSucceeded) {
          _emit(
            const TransferProgress(
              phase: TransferPhase.failed,
              message:
                  'Verification or saving failed. The batch was not committed.',
            ),
          );
        }
      } else {
        batch.timer?.cancel();
        batch.idleTimer?.cancel();
        if (identical(_batch, batch)) {
          _batch = null;
        }
        _stopIfExpired();
      }
    }
  }

  Future<void> _discardBatch(_ReceivingBatch batch) {
    return batch.cleanup ??= _cleanBatch(batch);
  }

  Future<void> _cleanBatch(_ReceivingBatch batch) async {
    batch.canceled = true;
    batch.timer?.cancel();
    batch.idleTimer?.cancel();
    final request = batch.uploadRequest;
    if (request != null) {
      await _destroyRequest(request);
    }
    await batch.ioDone;
    if (!batch.committed) {
      try {
        if (await batch.directory.exists()) {
          await batch.directory.delete(recursive: true);
        }
      } on FileSystemException {
        batch.cleanupSucceeded = false;
        _emit(
          const TransferProgress(
            phase: TransferPhase.failed,
            message: 'Some temporary files could not be removed. Check device storage.',
          ),
        );
      }
    }
    if (identical(_batch, batch)) {
      _batch = null;
    }
    _stopIfExpired();
  }

  Future<void> stop({
    String reason = 'Receiving stopped. Start again for a new code.',
  }) {
    return _stopFuture ??= _stop(reason);
  }

  Future<void> _stop(String reason) async {
    _closed = true;
    _inviteTimer?.cancel();
    if (_approval != null && !_approval!.isCompleted) {
      _approval!.complete(false);
    }
    final server = _server;
    _server = null;
    final closing = server?.close(force: true);
    for (final request in _requests.toList()) {
      await _destroyRequest(request);
    }
    final batch = _batch;
    if (batch != null) {
      await _discardBatch(batch);
    }
    if (closing != null) {
      await closing;
    }
    _lastReceiptToken = null;
    onStopped?.call(reason);
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, Object> data,
  ) async {
    try {
      final bytes = utf8.encode(jsonEncode(data));
      final response = request.response;
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('x-content-type-options', 'nosniff');
      if (status >= 400) {
        response.persistentConnection = false;
      }
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
    } catch (_) {
      await _destroyRequest(request);
    }
  }

  Future<void> _destroyRequest(HttpRequest request) async {
    try {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } catch (_) {
      // The socket may already have been closed by the peer or server.
    }
  }
}

class LocalSender {
  LocalSender({
    this.connectionTimeout = const Duration(seconds: 10),
    this.approvalTimeout = const Duration(seconds: 75),
    this.idleTimeout = const Duration(seconds: 30),
    this.batchTimeout = const Duration(minutes: 30),
  });

  final Duration connectionTimeout;
  final Duration approvalTimeout;
  final Duration idleTimeout;
  final Duration batchTimeout;

  HttpClient? _client;
  bool _sending = false;
  bool _canceled = false;
  HttpClientRequest? _activeRequest;
  StreamIterator<List<int>>? _sourceIterator;

  void cancel() {
    _canceled = true;
    try {
      _activeRequest?.abort(const TransferCancelled());
    } catch (_) {}
    _client?.close(force: true);
    final source = _sourceIterator;
    if (source != null) {
      unawaited(
        source.cancel().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
    }
  }

  void _checkCanceled() {
    if (_canceled) {
      throw const TransferCancelled();
    }
  }

  Future<TransferReceipt> send({
    required PairingCode code,
    required List<ShareFile> files,
    required String senderName,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    if (_sending) {
      throw const TransferException('This sender is already busy.');
    }
    final selected = List<ShareFile>.unmodifiable(files);
    final offer = createOutgoingOffer(selected, senderName);
    _sending = true;
    _canceled = false;
    final client = createPinnedClient(
      code,
      connectionTimeout: connectionTimeout,
    );
    _client = client;
    String? uploadToken;
    var commitStarted = false;
    final digests = <String, String>{};
    final deadline = Timer(batchTimeout, cancel);
    var sentBytes = 0;
    try {
      onProgress?.call(
        TransferProgress(
          phase: TransferPhase.connecting,
          message: 'Checking the receiver certificate.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      final request = await _open(
        client,
        code,
        'POST',
        '/v1/offer',
        code.token,
      );
      request.headers.contentType = ContentType.json;
      final metadata = utf8.encode(jsonEncode(offer.toJson()));
      if (metadata.length > TransferLimits.maxMetadataBytes) {
        throw const TransferException(
          'Choose fewer files; the metadata is too large.',
        );
      }
      request.contentLength = metadata.length;
      request.add(metadata);
      onProgress?.call(
        TransferProgress(
          phase: TransferPhase.awaitingApproval,
          message: 'Ask the receiver to approve this batch within 60 seconds.',
          totalBytes: offer.totalBytes,
          totalFiles: offer.files.length,
        ),
      );
      final accepted = await _response(request, approvalTimeout);
      if (accepted['id'] != offer.id ||
          accepted['uploadToken'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$')
              .hasMatch(accepted['uploadToken'] as String)) {
        throw const TransferException(
          'The receiver returned an invalid approval.',
        );
      }
      uploadToken = accepted['uploadToken'] as String;
      _checkCanceled();
      for (var index = 0; index < selected.length; index += 1) {
        final source = selected[index];
        final descriptor = offer.files[index];
        final upload = await _open(
          client,
          code,
          'PUT',
          '/v1/files/${offer.id}/${descriptor.id}',
          uploadToken,
        );
        upload.headers.contentType = ContentType.binary;
        upload.contentLength = descriptor.size;
        final digestOutput = _DigestOutput();
        final digestInput = sha256.startChunkedConversion(digestOutput);
        var digestClosed = false;
        var fileBytes = 0;
        final iterator = StreamIterator<List<int>>(
          source.openRead().timeout(idleTimeout),
        );
        _sourceIterator = iterator;
        upload.bufferOutput = false;
        try {
          while (await iterator.moveNext()) {
            _checkCanceled();
            final chunk = iterator.current;
            fileBytes += chunk.length;
            if (fileBytes > descriptor.size) {
              throw const TransferException(
                'A selected file changed size. Select it again.',
              );
            }
            digestInput.add(chunk);
            upload.add(chunk);
            await upload.flush().timeout(idleTimeout);
            _checkCanceled();
            sentBytes += chunk.length;
            onProgress?.call(
              TransferProgress(
                phase: TransferPhase.sending,
                message: 'Streaming encrypted bytes. Waiting for final confirmation.',
                totalBytes: offer.totalBytes,
                processedBytes: sentBytes,
                totalFiles: offer.files.length,
                completedFiles: index,
                fileName: descriptor.name,
              ),
            );
          }
          _checkCanceled();
          if (fileBytes != descriptor.size) {
            throw const TransferException(
              'A selected file could not be read completely. Select it again.',
            );
          }
          digestInput.close();
          digestClosed = true;
          final digest = digestOutput.value!.toString();
          final result = await _response(upload, idleTimeout);
          if (result['id'] != descriptor.id ||
              result['size'] != descriptor.size ||
              result['sha256'] is! String ||
              !secretEquals(result['sha256'] as String, digest)) {
            throw const TransferException(
              'The receiver checksum did not match. The batch was not committed.',
            );
          }
          digests[descriptor.id] = digest;
        } finally {
          try {
            await iterator.cancel().timeout(idleTimeout);
          } catch (_) {}
          if (identical(_sourceIterator, iterator)) {
            _sourceIterator = null;
          }
          if (!digestClosed) {
            digestInput.close();
          }
        }
      }
      _checkCanceled();
      onProgress?.call(
        TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Bytes uploaded. Asking the receiver to verify and save.',
          totalBytes: offer.totalBytes,
          processedBytes: sentBytes,
          totalFiles: offer.files.length,
          completedFiles: offer.files.length,
        ),
      );
      final commit = await _open(
        client,
        code,
        'POST',
        '/v1/commit/${offer.id}',
        uploadToken,
      );
      commit.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode(<String, Object>{'sha256': digests}));
      commit.contentLength = body.length;
      commit.add(body);
      _checkCanceled();
      commitStarted = true;
      final receipt = _verifyReceipt(
        await _response(commit, idleTimeout),
        offer,
        digests,
      );
      _emitCompleted(receipt, onProgress);
      return receipt;
    } catch (error) {
      _activeRequest?.abort();
      client.close(force: true);
      if (commitStarted && uploadToken != null) {
        final recovered = await _recoverReceipt(
          code,
          uploadToken,
          offer,
          digests,
        );
        if (recovered != null) {
          _emitCompleted(recovered, onProgress);
          return recovered;
        }
        throw const TransferException(
          'The final confirmation was lost. The receiver may already have saved '
          'the files. Check that device before sending again.',
          outcomeUncertain: true,
        );
      }
      if (uploadToken != null) {
        await _cancelRemote(code, uploadToken, offer.id);
      }
      if (_canceled) {
        throw const TransferCancelled();
      }
      if (error is TransferException) {
        rethrow;
      }
      if (error is HandshakeException) {
        throw const TransferException(
          'The receiver certificate did not match. Copy a fresh code directly from the receiver.',
        );
      }
      if (error is TimeoutException) {
        throw const TransferException(
          'The connection timed out. Keep both apps open and try again.',
        );
      }
      throw const TransferException(
        'Could not finish sending. Check Wi-Fi, storage, and the selected files.',
      );
    } finally {
      deadline.cancel();
      client.close(force: true);
      _client = null;
      _activeRequest = null;
      _sending = false;
    }
  }

  Future<HttpClientRequest> _open(
    HttpClient client,
    PairingCode code,
    String method,
    String path,
    String token,
  ) async {
    _checkCanceled();
    final request = await client
        .openUrl(method, code.endpoint(path))
        .timeout(connectionTimeout);
    _activeRequest = request;
    unawaited(
      request.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    _checkCanceled();
    return request;
  }

  Future<Map<String, dynamic>> _response(
    HttpClientRequest request,
    Duration timeout,
  ) async {
    final response = await request.close().timeout(timeout);
    final data = await readBoundedJson(response, timeout: idleTimeout);
    if (response.statusCode != 200) {
      final message = data['error'];
      throw TransferException(
        message is String && message.length <= 240
            ? message
            : 'The receiver rejected this operation.',
      );
    }
    return data;
  }

  TransferReceipt _verifyReceipt(
    Map<String, dynamic> data,
    IncomingOffer offer,
    Map<String, String> digests,
  ) {
    final receipt = TransferReceipt.fromJson(data);
    if (receipt.id != offer.id ||
        receipt.files.length != offer.files.length ||
        receipt.files.map((file) => file.id).toSet().length !=
            offer.files.length) {
      throw const TransferException(
        'The final receipt does not match this batch.',
      );
    }
    for (final expected in offer.files) {
      final matches = receipt.files.where((file) => file.id == expected.id);
      if (matches.isEmpty ||
          matches.first.size != expected.size ||
          matches.first.name != expected.name ||
          !secretEquals(matches.first.digest, digests[expected.id] ?? '')) {
        throw const TransferException(
          'The final receipt checksum does not match.',
        );
      }
    }
    return receipt;
  }

  void _emitCompleted(
    TransferReceipt receipt,
    void Function(TransferProgress)? callback,
  ) {
    callback?.call(
      TransferProgress(
        phase: TransferPhase.completed,
        message: 'Receiver confirmed every file is saved and verified.',
        totalBytes: receipt.totalBytes,
        processedBytes: receipt.totalBytes,
        totalFiles: receipt.files.length,
        completedFiles: receipt.files.length,
      ),
    );
  }

  Future<TransferReceipt?> _recoverReceipt(
    PairingCode code,
    String token,
    IncomingOffer offer,
    Map<String, String> digests,
  ) async {
    final client = createPinnedClient(
      code,
      connectionTimeout: const Duration(seconds: 3),
    );
    try {
      final request = await client
          .getUrl(code.endpoint('/v1/status/${offer.id}'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      return _verifyReceipt(
        await _response(request, const Duration(seconds: 3)),
        offer,
        digests,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _cancelRemote(PairingCode code, String token, String id) async {
    final client = createPinnedClient(
      code,
      connectionTimeout: const Duration(seconds: 3),
    );
    try {
      final request = await client
          .deleteUrl(code.endpoint('/v1/transfers/$id'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>().timeout(const Duration(seconds: 3));
    } catch (_) {
      // The receiver also removes an interrupted upload and expires abandoned batches.
    } finally {
      client.close(force: true);
    }
  }
}
```

### File 8 — `lib/screens/nearby_screen.dart` — NEW

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/share_file.dart';
import '../models/transfer_models.dart';
import '../services/local_transfer_service.dart';

enum NearbyMode { send, receive }

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    super.key,
    required this.mode,
    this.files = const <ShareFile>[],
    this.documentsDirectory = getApplicationDocumentsDirectory,
  });

  final NearbyMode mode;
  final List<ShareFile> files;
  final Future<Directory> Function() documentsDirectory;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  final TextEditingController _codeController = TextEditingController();
  late final TextEditingController _nameController;
  LocalReceiver? _receiver;
  LocalSender? _sender;
  ReceiverSession? _session;
  IncomingOffer? _pendingOffer;
  Completer<bool>? _decision;
  TransferProgress? _progress;
  TransferReceipt? _receipt;
  String? _selectedHost;
  String? _error;
  String? _notice;
  bool _starting = false;
  bool _sending = false;
  bool _stopping = false;
  bool _sharing = false;
  bool _allowPop = false;
  bool _askingToLeave = false;
  bool _disposing = false;
  bool _foreground = true;

  bool get _isReceiver => widget.mode == NearbyMode.receive;
  bool get _active => _starting || _sending || _session != null || _stopping;
  int get _selectedBytes =>
      widget.files.fold<int>(0, (sum, file) => sum + file.size);
  bool get _canUpdate => mounted && !_disposing;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: Platform.isIOS
          ? 'My iPhone'
          : Platform.isAndroid
          ? 'My Android'
          : 'My device',
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      if (_canUpdate && _active) {
        setState(
          () => _notice =
              'App moved to the background. Start a new session when ready.',
        );
      }
      _sender?.cancel();
      unawaited(
        _stopReceiving(
          reason:
              'App moved to the background. Start a new session when ready.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _resolveDecision(false);
    _sender?.cancel();
    final receiver = _receiver;
    if (receiver != null) {
      unawaited(receiver.stop());
    }
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _resolveDecision(bool accepted) {
    final decision = _decision;
    if (decision != null && !decision.isCompleted) {
      decision.complete(accepted);
    }
    _decision = null;
    if (_canUpdate) {
      setState(() => _pendingOffer = null);
    }
  }

  Future<bool> _askForApproval(IncomingOffer offer) {
    if (!_canUpdate) {
      return Future<bool>.value(false);
    }
    _resolveDecision(false);
    final decision = Completer<bool>();
    _decision = decision;
    setState(() {
      _pendingOffer = offer;
      _error = null;
    });
    return decision.future;
  }

  void _receiveProgress(TransferProgress progress) {
    if (!_canUpdate) {
      return;
    }
    if (progress.phase != TransferPhase.awaitingApproval) {
      _resolveDecision(false);
    }
    setState(() => _progress = progress);
  }

  Future<void> _startReceiving() async {
    if (_active || !_foreground) {
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
      _notice = null;
      _progress = null;
      _receipt = null;
    });
    LocalReceiver? receiver;
    try {
      final documents = await widget.documentsDirectory();
      if (!_canUpdate || !_foreground) {
        return;
      }
      receiver = LocalReceiver(
        storageRoot: Directory('${documents.path}/ShareBondhu/Received'),
        onOffer: _askForApproval,
        onProgress: _receiveProgress,
        onReceived: (receipt) {
          if (_canUpdate) {
            setState(() => _receipt = receipt);
          }
        },
        onStopped: (reason) {
          if (_canUpdate) {
            _resolveDecision(false);
            setState(() {
              _session = null;
              _selectedHost = null;
              _notice = reason;
            });
          }
        },
      );
      _receiver = receiver;
      final session = await receiver.start();
      if (!_canUpdate) {
        await receiver.stop();
        return;
      }
      setState(() {
        _session = session;
        _selectedHost = session.addresses.first;
      });
    } on MissingPluginException {
      if (receiver != null) {
        await receiver.stop();
      }
      if (_canUpdate) {
        setState(
          () => _error = 'Native storage support is missing. Run flutter pub get, stop the app, and rebuild it.',
        );
      }
    } catch (error) {
      if (receiver != null) {
        await receiver.stop();
      }
      if (_canUpdate) {
        setState(
          () => _error = error is TransferException ? error.message : 'Could not start receiving. Check Wi-Fi, local-network permission, and available storage.',
        );
      }
    } finally {
      if (_canUpdate) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopReceiving({
    String reason = 'Receiving stopped. Saved files are kept.',
  }) async {
    final receiver = _receiver;
    if (receiver == null || _stopping) {
      return;
    }
    if (_canUpdate) {
      setState(() => _stopping = true);
    }
    _resolveDecision(false);
    try {
      await receiver.stop(reason: reason);
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _error = 'The session closed, but cleanup could not finish. Check device storage.',
        );
      }
    } finally {
      if (identical(_receiver, receiver)) {
        _receiver = null;
      }
      if (_canUpdate) {
        setState(() {
          _session = null;
          _selectedHost = null;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _copyCode() async {
    final session = _session;
    final host = _selectedHost;
    if (session == null ||
        host == null ||
        DateTime.now().isAfter(session.expiresAt)) {
      _showMessage('Start a new receiving session to get a fresh code.');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: session.codeFor(host).encode()),
    );
    _showMessage(
      'Code copied. Share it privately with the intended sender only.',
    );
  }

  Future<void> _pasteCode() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (_canUpdate && !_sending && clipboard?.text != null) {
        _codeController.text = clipboard!.text!.trim();
      }
    } catch (_) {
      _showMessage(
        'Clipboard access was unavailable. Paste into the field yourself.',
      );
    }
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _receipt = null;
      _progress = null;
    });
    PairingCode code;
    try {
      code = PairingCode.parse(_codeController.text);
      createOutgoingOffer(widget.files, _nameController.text);
    } on TransferException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final sender = LocalSender();
    _sender = sender;
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
      _receipt = null;
    });
    try {
      final receipt = await sender.send(
        code: code,
        files: widget.files,
        senderName: _nameController.text,
        onProgress: (progress) {
          if (_canUpdate) {
            setState(() => _progress = progress);
          }
        },
      );
      if (_canUpdate) {
        setState(() => _receipt = receipt);
      }
    } on TransferException catch (error) {
      if (_canUpdate) {
        setState(() {
          _error = error.message;
          _progress = TransferProgress(
            phase: error is TransferCancelled
                ? TransferPhase.canceled
                : TransferPhase.failed,
            message: error.outcomeUncertain
                ? 'Check the receiver before retrying.'
                : error.message,
          );
        });
      }
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _error =
              'Sending stopped. Check the receiver before trying again.',
        );
      }
    } finally {
      if (identical(_sender, sender)) {
        _sender = null;
      }
      if (_canUpdate) {
        setState(() => _sending = false);
      }
    }
  }

  void _showMessage(String message) {
    if (_canUpdate) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _shareReceived(BuildContext buttonContext) async {
    final receipt = _receipt;
    if (receipt == null || _sharing) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      final files = <XFile>[];
      for (final file in receipt.files) {
        final path = file.localPath;
        if (path == null || !await File(path).exists()) {
          throw const TransferException(
            'A received copy is no longer available in app storage.',
          );
        }
        files.add(
          XFile(path, mimeType: 'application/octet-stream', name: file.name),
        );
      }
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          title: 'Files received with ShareBondhu',
          sharePositionOrigin: origin,
        ),
      );
      _showMessage(
        'Share sheet closed. Check your chosen destination to confirm any exported copies.',
      );
    } catch (error) {
      _showMessage(
        error is TransferException ? error.message : 'The system share sheet could not open. Try again after rebuilding the app.',
      );
    } finally {
      if (_canUpdate) {
        setState(() => _sharing = false);
      }
    }
  }

  Future<void> _confirmLeave() async {
    if (_askingToLeave) {
      return;
    }
    _askingToLeave = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this session?'),
        content: const Text(
          'Active work will stop. Files already confirmed as saved will be kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop and leave'),
          ),
        ],
      ),
    );
    _askingToLeave = false;
    if (leave != true || !_canUpdate) {
      return;
    }
    _sender?.cancel();
    await _stopReceiving();
    if (_canUpdate) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canUpdate) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_active || _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_confirmLeave());
        }
      },
      child: Scaffold(
        key: const ValueKey('nearby-scaffold'),
        appBar: AppBar(
          title: Text(_isReceiver ? 'Receive nearby' : 'Send nearby'),
          toolbarHeight: 70,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: <Widget>[
                  _buildHeader(theme),
                  const SizedBox(height: 18),
                  if (_error != null)
                    _MessagePanel(message: _error!, isError: true),
                  if (_notice != null) _MessagePanel(message: _notice!),
                  if (_isReceiver)
                    _buildReceiver(theme)
                  else
                    _buildSender(theme),
                  if (_pendingOffer != null)
                    _buildApproval(theme, _pendingOffer!),
                  if (_progress != null) _ProgressPanel(progress: _progress!),
                  if (_receipt != null) _buildReceipt(theme, _receipt!),
                  const SizedBox(height: 16),
                  const _MessagePanel(
                    message:
                        'Part 2: private IPv4 Wi-Fi/hotspot only. Keep both apps open. '
                        'Up to 50 files, 2 GiB each, 4 GiB per batch. '
                        'No QR scanner, resumable transfer, or background service yet.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF164D3C),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFD5F391),
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PART 02 · LOCAL TLS',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _isReceiver
                ? 'Your permission.\nYour files.'
                : 'A nearby connection.\nA private delivery.',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isReceiver
                ? 'Start a receiving session, give your code to the sender, then review their request.'
                : 'Paste the code directly from the receiver. File bytes leave only after they approve.',
            style: const TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiver(ThemeData theme) {
    final session = _session;
    return _NearbyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Receiving session',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Use a trusted private network. Anyone with the code can request a transfer, but your approval is still required.',
          ),
          const SizedBox(height: 18),
          if (session == null)
            FilledButton.icon(
              key: const ValueKey('start-receiving-button'),
              onPressed: _starting || _stopping ? null : _startReceiving,
              icon: _starting
                  ? const _BusyIcon()
                  : const Icon(Icons.download_rounded),
              label: Text(_starting ? 'Creating session' : 'Start receiving'),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (session.addresses.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedHost,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Wi-Fi address',
                      border: OutlineInputBorder(),
                    ),
                    items: session.addresses
                        .map(
                          (host) =>
                              DropdownMenuItem(value: host, child: Text(host)),
                        )
                        .toList(),
                    onChanged: (host) => setState(() => _selectedHost = host),
                  )
                else
                  Text(
                    'Local address: ${session.addresses.first}:${session.port}',
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 12),
                SelectableText(
                  session.codeFor(_selectedHost!).encode(),
                  key: const ValueKey('receiving-code'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Code expires at ${TimeOfDay.fromDateTime(session.expiresAt).format(context)}. '
                  'Keep the entire code private. This is manual pairing, not a QR scanner.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const ValueKey('copy-code-button'),
                      onPressed: _stopping ? null : _copyCode,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy code'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('stop-receiving-button'),
                      onPressed: _stopping ? null : () => _stopReceiving(),
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(_stopping ? 'Stopping' : 'Stop receiving'),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSender(ThemeData theme) {
    return _NearbyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${widget.files.length} selected · ${formatBytes(_selectedBytes)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: widget.files.length.clamp(1, 3) * 58.0,
            child: ListView.builder(
              itemCount: widget.files.length,
              itemBuilder: (context, index) {
                final file = widget.files[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(file.formattedSize),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('sender-name-field'),
            controller: _nameController,
            enabled: !_sending,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Your device name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pairing-code-field'),
            controller: _codeController,
            enabled: !_sending,
            minLines: 2,
            maxLines: 4,
            maxLength: 120,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Receiver pairing code',
              hintText: 'Paste the complete SB1 code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                key: const ValueKey('paste-code-button'),
                onPressed: _sending ? null : _pasteCode,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste code'),
              ),
              FilledButton.icon(
                key: const ValueKey('ask-to-send-button'),
                onPressed: _sending || widget.files.isEmpty ? null : _send,
                icon: _sending
                    ? const _BusyIcon()
                    : const Icon(Icons.arrow_upward_rounded),
                label: Text(_sending ? 'Sending' : 'Ask to send'),
              ),
              if (_sending)
                OutlinedButton.icon(
                  key: const ValueKey('cancel-sending-button'),
                  onPressed: () => _sender?.cancel(),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApproval(ThemeData theme, IncomingOffer offer) {
    return _NearbyPanel(
      color: theme.colorScheme.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Allow this transfer?',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text('${offer.senderName} · ${offer.remoteAddress}'),
          const SizedBox(height: 8),
          const Text(
            'Device names are self-reported. Check the sender in person. Answer within 60 seconds.',
          ),
          const SizedBox(height: 12),
          Text(
            '${offer.files.length} files · ${formatBytes(offer.totalBytes)}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: offer.files.length.clamp(1, 4) * 66.0,
            child: ListView.builder(
              itemCount: offer.files.length,
              itemBuilder: (context, index) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(offer.files[index].name),
                subtitle: Text(formatBytes(offer.files[index].size)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                key: const ValueKey('approve-transfer-button'),
                onPressed: () => _resolveDecision(true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Accept files'),
              ),
              OutlinedButton(
                key: const ValueKey('reject-transfer-button'),
                onPressed: () => _resolveDecision(false),
                child: const Text('Decline'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceipt(ThemeData theme, TransferReceipt receipt) {
    return _NearbyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Most recent confirmed batch',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Icon(
            Icons.verified_outlined,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            _isReceiver ? 'Saved and verified' : 'Delivery confirmed',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${receipt.files.length} files · ${formatBytes(receipt.totalBytes)}',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: receipt.files.length.clamp(1, 4) * 56.0,
            child: ListView.builder(
              itemCount: receipt.files.length,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(
                  receipt.files[index].name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (_isReceiver)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 12),
                const Text(
                  'Copies are saved in ShareBondhu app documents. Export important files before uninstalling. '
                  'On iPhone, choose Save to Files in the share sheet. Android destinations depend on installed apps.',
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    key: const ValueKey('share-received-button'),
                    onPressed: _sharing
                        ? null
                        : () => _shareReceived(buttonContext),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(
                      _sharing ? 'Opening share sheet' : 'Share / save copies',
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Your selected originals are unchanged. Returning home keeps the selection.',
            ),
        ],
      ),
    );
  }
}

class _NearbyPanel extends StatelessWidget {
  const _NearbyPanel({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _NearbyPanel(
      color: isError ? colors.errorContainer : colors.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: isError ? colors.onErrorContainer : colors.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? colors.onErrorContainer
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moving = <TransferPhase>{
      TransferPhase.sending,
      TransferPhase.receiving,
      TransferPhase.verifying,
      TransferPhase.awaitingApproval,
      TransferPhase.connecting,
      TransferPhase.completed,
    }.contains(progress.phase);
    return _NearbyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            progress.message,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress.fileName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(progress.fileName!),
            ),
          if (moving)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(
                value: progress.indeterminate ? null : progress.fraction,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
                semanticsLabel: 'Transferred bytes',
              ),
            ),
          if (progress.totalFiles > 0)
            Text(
              '${formatBytes(progress.processedBytes)} / ${formatBytes(progress.totalBytes)} · '
              '${progress.completedFiles} / ${progress.totalFiles} files',
            ),
          if (progress.phase == TransferPhase.sending ||
              progress.phase == TransferPhase.verifying)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '100% uploaded is not a delivery receipt. Wait for receiver confirmation.',
              ),
            ),
        ],
      ),
    );
  }
}

class _BusyIcon extends StatelessWidget {
  const _BusyIcon();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
```

### File 9 — `android/app/src/main/AndroidManifest.xml` — FIRST CUSTOMIZATION

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="ShareBondhu"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

### File 10 — `ios/Runner/Info.plist` — FIRST CUSTOMIZATION

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>ShareBondhu</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>sharebondhu</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
		<key>UISceneConfigurations</key>
		<dict>
			<key>UIWindowSceneSessionRoleApplication</key>
			<array>
				<dict>
					<key>UISceneClassName</key>
					<string>UIWindowScene</string>
					<key>UISceneConfigurationName</key>
					<string>flutter</string>
					<key>UISceneDelegateClassName</key>
					<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
					<key>UISceneStoryboardFile</key>
					<string>Main</string>
				</dict>
			</array>
		</dict>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>NSLocalNetworkUsageDescription</key>
	<string>ShareBondhu connects to nearby devices on your Wi-Fi to send and receive files with your approval.</string>
	<key>UIFileSharingEnabled</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>
</dict>
</plist>
```


## আগের File 1–5 — সম্পূর্ণ বর্তমান কোড

File 1, 4 ও 5 আপডেট হয়েছে। File 2 ও 3 আগের archive-এর সঙ্গে byte-for-byte একই আছে; তবুও সম্পূর্ণ দেওয়া হলো। শুধু code snippet যোগ না করে UPDATED file-এর পুরো content বসাবেন। আপনার নিজস্ব অতিরিক্ত পরিবর্তন থাকলে overwrite করার আগে backup/diff করুন।

### File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.2.0+2

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: 12.2.0
  basic_utils: 5.8.2
  crypto: 3.0.7
  path_provider: 2.1.6
  share_plus: 13.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0

flutter:
  uses-material-design: true
```

### File 2 — `lib/main.dart` — UNCHANGED

```dart
import 'package:flutter/material.dart';

import 'models/share_file.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShareBondhuApp());
}

class ShareBondhuApp extends StatefulWidget {
  const ShareBondhuApp({super.key, this.pickFiles});

  final PickShareFiles? pickFiles;

  @override
  State<ShareBondhuApp> createState() => _ShareBondhuAppState();
}

class _ShareBondhuAppState extends State<ShareBondhuApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    final currentlyDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };

    setState(() {
      _themeMode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF176B52),
      brightness: brightness,
    );
    final background = isDark
        ? const Color(0xFF101C18)
        : const Color(0xFFF6F8F5);

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 88,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: colors.onSurface,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: baseTheme.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: baseTheme.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShareBondhu',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomeScreen(
        pickFiles: widget.pickFiles ?? pickDeviceFiles,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
```

### File 3 — `lib/models/share_file.dart` — UNCHANGED

```dart
enum FileCategory { image, video, audio, document, archive, other }

typedef PickShareFiles = Future<FileSelection> Function();

class FileSelection {
  FileSelection({required Iterable<ShareFile> files, this.unavailableCount = 0})
    : files = List<ShareFile>.unmodifiable(files) {
    if (unavailableCount < 0) {
      throw ArgumentError.value(unavailableCount, 'unavailableCount');
    }
  }

  final List<ShareFile> files;
  final int unavailableCount;
}

class ShareFile {
  ShareFile({
    required this.name,
    required this.size,
    required this.sourceUri,
    required this.readStream,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'A file must have a name.');
    }
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'File size cannot be negative.');
    }
    if (!sourceUri.hasScheme) {
      throw ArgumentError.value(
        sourceUri,
        'sourceUri',
        'A source URI must include its scheme.',
      );
    }
  }

  final String name;
  final int size;
  final Uri sourceUri;
  final Stream<List<int>> Function() readStream;

  String get id => sourceUri.toString();

  String get formattedSize => formatBytes(size);

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  FileCategory get category => switch (extension) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'heif' ||
    'bmp' ||
    'avif' ||
    'svg' => FileCategory.image,
    'mp4' ||
    'mov' ||
    'mkv' ||
    'avi' ||
    'webm' ||
    'm4v' ||
    '3gp' => FileCategory.video,
    'mp3' ||
    'wav' ||
    'm4a' ||
    'aac' ||
    'ogg' ||
    'opus' ||
    'flac' ||
    'aiff' => FileCategory.audio,
    'pdf' ||
    'doc' ||
    'docx' ||
    'ppt' ||
    'pptx' ||
    'xls' ||
    'xlsx' ||
    'txt' ||
    'csv' ||
    'md' ||
    'rtf' ||
    'odt' ||
    'epub' => FileCategory.document,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' => FileCategory.archive,
    _ => FileCategory.other,
  };

  String get categoryLabel => switch (category) {
    FileCategory.image => 'Image',
    FileCategory.video => 'Video',
    FileCategory.audio => 'Audio',
    FileCategory.document => 'Document',
    FileCategory.archive => 'Archive',
    FileCategory.other => 'File',
  };

  /// Opens a fresh byte stream only when a caller needs the content.
  /// Selection, sizing and removal do not call this method.
  Stream<List<int>> openRead() => readStream();
}

String formatBytes(int bytes) {
  if (bytes < 0) {
    throw ArgumentError.value(bytes, 'bytes', 'Byte count cannot be negative.');
  }
  if (bytes < 1024) {
    return '$bytes B';
  }

  const units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final decimalPlaces = value == value.truncateToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(decimalPlaces)} ${units[unitIndex]}';
}
```

### File 4 — `lib/screens/home_screen.dart` — UPDATED

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_file.dart';
import 'nearby_screen.dart';

Future<FileSelection> pickDeviceFiles() async {
  final pickedFiles = await FilePicker.pickFiles(
    type: FileType.any,
    dialogTitle: 'Choose files for ShareBondhu',
  );
  final files = <ShareFile>[];
  var unavailableCount = 0;

  for (final picked in pickedFiles) {
    try {
      final byteCount = await picked.length();
      files.add(
        ShareFile(
          name: picked.name,
          size: byteCount,
          sourceUri: picked.uri,
          readStream: picked.readAsByteStream,
        ),
      );
    } catch (_) {
      unavailableCount += 1;
    }
  }

  return FileSelection(files: files, unavailableCount: unavailableCount);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.pickFiles,
    required this.onToggleTheme,
  });

  final PickShareFiles pickFiles;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<ShareFile> _files = <ShareFile>[];
  int _selectedIndex = 0;
  bool _isPicking = false;
  String? _errorMessage;

  int get _totalSize => _files.fold<int>(0, (sum, file) => sum + file.size);

  String get _selectionSummary {
    final noun = _files.length == 1 ? 'file' : 'files';
    return '${_files.length} $noun · ${formatBytes(_totalSize)}';
  }

  Future<void> _selectFiles() async {
    if (_isPicking) {
      return;
    }
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final selection = await widget.pickFiles();
      if (!mounted) {
        return;
      }
      if (selection.files.isEmpty && selection.unavailableCount == 0) {
        return;
      }

      final knownIds = _files.map((file) => file.id).toSet();
      final additions = <ShareFile>[];
      var duplicateCount = 0;

      for (final file in selection.files) {
        if (knownIds.add(file.id)) {
          additions.add(file);
        } else {
          duplicateCount += 1;
        }
      }

      setState(() {
        _files.addAll(additions);
        if (additions.isNotEmpty) {
          _selectedIndex = 1;
        }
      });

      final messages = <String>[];
      if (additions.isNotEmpty) {
        final noun = additions.length == 1 ? 'file' : 'files';
        messages.add('Added ${additions.length} $noun.');
      }
      if (duplicateCount > 0) {
        final noun = duplicateCount == 1 ? 'reference' : 'references';
        messages.add('$duplicateCount duplicate $noun skipped.');
      }
      if (selection.unavailableCount > 0) {
        final count = selection.unavailableCount;
        final noun = count == 1 ? 'file was' : 'files were';
        messages.add('$count $noun unavailable. Save locally and try again.');
      }
      if (messages.isNotEmpty) {
        _showMessage(messages.join(' '));
      }
    } on MissingPluginException {
      _showError(
        'The file picker is not installed in this build. Stop the app, '
        'run flutter pub get, and rebuild it.',
      );
    } on PlatformException catch (error) {
      _showError(
        error.code == 'permission_denied'
            ? 'File access was not allowed. You can try the system picker again.'
            : 'The file picker could not open. Close it and try again.',
      );
    } catch (_) {
      _showError(
        'We could not read that selection. Try choosing locally stored files.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
    });
  }

  void _removeFile(ShareFile file) {
    setState(() {
      _files.removeWhere((item) => item.id == file.id);
    });
    _showMessage('Removed from selection. Your original file is unchanged.');
  }

  Future<void> _clearSelection() async {
    if (_files.isEmpty || _isPicking) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear selection?'),
        content: const Text(
          'This only clears the list in ShareBondhu. '
          'Your original files will not be deleted.',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('keep-files-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep files'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear selection'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }
    setState(() {
      _files.clear();
    });
    _showMessage('Selection cleared. Your original files are unchanged.');
  }

  Future<void> _openNearby(NearbyMode mode) async {
    if (_isPicking) {
      return;
    }
    if (mode == NearbyMode.send && _files.isEmpty) {
      _showMessage('Select at least one file before sending.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => NearbyScreen(
          mode: mode,
          files: List<ShareFile>.unmodifiable(_files),
        ),
      ),
    );
  }

  void _changePage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: const ValueKey('main-scaffold'),
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.swap_calls_rounded,
                color: theme.colorScheme.onPrimary,
                size: 27,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ShareBondhu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Text(
                    'A LITTLE CLOSER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey('theme-toggle'),
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: <Widget>[
            if (_errorMessage != null)
              _ErrorNotice(
                message: _errorMessage!,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: switch (_selectedIndex) {
                    0 => _buildHome(context),
                    1 => _buildSelection(context),
                    _ => _buildGuide(context),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _changePage,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            key: ValueKey('nav-home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            key: ValueKey('nav-files'),
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            key: ValueKey('nav-guide'),
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Guide',
          ),
        ],
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('home-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: <Widget>[
        _HeroPanel(isPicking: _isPicking, onSelect: _selectFiles),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('receive-files-button'),
          onPressed: _isPicking ? null : () => _openNearby(NearbyMode.receive),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Receive files'),
        ),
        const SizedBox(height: 18),
        _SurfacePanel(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: 'FILES SELECTED',
                  value: '${_files.length}',
                  valueKey: const ValueKey('selected-count'),
                  icon: Icons.layers_outlined,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _Metric(
                  label: 'TOTAL SIZE',
                  value: formatBytes(_totalSize),
                  valueKey: const ValueKey('selected-size'),
                  icon: Icons.data_usage_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Your selection',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('view-selection-button'),
              onPressed: () => _changePage(1),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_files.isEmpty)
          const _EmptySelection()
        else
          Column(
            children: _files.take(3).map((file) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FileTile(file: file, onRemove: () => _removeFile(file)),
              );
            }).toList(),
          ),
        const SizedBox(height: 20),
        _SurfacePanel(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.construction_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PART 02 · NEARBY TRANSFER',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Manual pairing and TLS file transfers are ready for testing. '
                'Use Receive files here, or Send selected from the Files tab.',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('how-it-works-button'),
                onPressed: () => _changePage(2),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('See the build guide'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelection(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const PageStorageKey('selection-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Your selection',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _selectionSummary,
                  key: const ValueKey('selection-summary'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Selected on this device. Sending never removes your originals.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const ValueKey('add-files-button'),
                      onPressed: _isPicking ? null : _selectFiles,
                      icon: _isPicking
                          ? const _SmallProgress()
                          : const Icon(Icons.add_rounded),
                      label: Text(_isPicking ? 'Opening picker' : 'Add files'),
                    ),
                    if (_files.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('clear-selection-button'),
                        onPressed: _isPicking ? null : _clearSelection,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear list'),
                      ),
                    if (_files.isNotEmpty)
                      FilledButton.tonalIcon(
                        key: const ValueKey('send-selected-button'),
                        onPressed: _isPicking
                            ? null
                            : () => _openNearby(NearbyMode.send),
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Send selected'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_files.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _EmptySelection()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final file = _files[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FileTile(
                    file: file,
                    onRemove: () => _removeFile(file),
                  ),
                );
              }, childCount: _files.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ],
    );
  }

  Widget _buildGuide(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('guide-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: <Widget>[
        Text(
          'One step at a time.',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We are building a real nearby-sharing app in small, testable parts.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        const _GuideStep(
          number: '01',
          title: 'Choose your files',
          description:
              'Use the system picker. Review the names and sizes, '
              'then remove anything you do not want in the list.',
          status: 'READY',
          isReady: true,
        ),
        const _GuideStep(
          number: '02',
          title: 'Connect nearby',
          description:
              'Open Receive files and start a session. Copy its full SB1 code '
              'to the sender on the same private Wi-Fi or hotspot.',
          status: 'READY',
          isReady: true,
        ),
        const _GuideStep(
          number: '03',
          title: 'Approve and transfer',
          description:
              'The receiver approves each batch. TLS certificate pinning, '
              'streaming, SHA-256 verification, and cancellation are now added.',
          status: 'READY',
          isReady: true,
        ),
        const _GuideStep(
          number: '04',
          title: 'Save and keep track',
          description:
              'Received copies are saved in app documents and can be exported. '
              'A persistent history browser and QR pairing are planned next.',
          status: 'LATER',
        ),
        const SizedBox(height: 12),
        _SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'About this version',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const _InfoLine(
                icon: Icons.lock_outline_rounded,
                text: 'A TLS receiver runs only after you tap Start receiving. Keep its pairing code private.',
              ),
              const _InfoLine(
                icon: Icons.restart_alt_rounded,
                text: 'Selection and theme reset on restart. Saved received copies remain in app documents.',
              ),
              const _InfoLine(
                icon: Icons.verified_user_outlined,
                text: 'Clearing this list never deletes your original files.',
              ),
              const _InfoLine(
                icon: Icons.cloud_outlined,
                text: 'Cloud-only files may need internet to become available.',
              ),
              const _InfoLine(
                icon: Icons.smartphone_rounded,
                text:
                    'We share selected files, not installed iPhone apps. '
                    'iOS does not offer Android-style Wi-Fi Direct.',
              ),
              const SizedBox(height: 4),
              Text(
                'ShareBondhu is a working brand name. Check its availability '
                'before publishing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.isPicking, required this.onSelect});

  final bool isPicking;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF113F32), Color(0xFF1E7157)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.spa_outlined, size: 18, color: Color(0xFFD5F391)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A SPACE FOR YOUR FILES',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Good things are\nmeant to be shared.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.16,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Start with a photo, a video, or a whole collection. '
            'Your selection stays with you.',
            style: TextStyle(
              color: Color(0xFFE0EDE5),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 23),
          FilledButton.icon(
            key: const ValueKey('select-files-button'),
            onPressed: isPicking ? null : onSelect,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD5F391),
              foregroundColor: const Color(0xFF143D2D),
              disabledBackgroundColor: const Color(0xFF94B989),
              disabledForegroundColor: const Color(0xFF143D2D),
            ),
            icon: isPicking
                ? const _SmallProgress()
                : const Icon(Icons.add_rounded),
            label: Text(isPicking ? 'Opening picker' : 'Select files'),
          ),
        ],
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.icon,
  });

  final String label;
  final String value;
  final Key valueKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfacePanel(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 29,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'A fresh start',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No files selected yet.\nChoose something to add to your list.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.onRemove});

  final ShareFile file;
  final VoidCallback onRemove;

  IconData get _icon => switch (file.category) {
    FileCategory.image => Icons.image_outlined,
    FileCategory.video => Icons.movie_outlined,
    FileCategory.audio => Icons.music_note_outlined,
    FileCategory.document => Icons.description_outlined,
    FileCategory.archive => Icons.folder_zip_outlined,
    FileCategory.other => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 5, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_icon, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.formattedSize} · ${file.categoryLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('remove:${file.id}'),
            tooltip: 'Remove ${file.name} from selection',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
    required this.status,
    this.isReady = false,
  });

  final String number;
  final String title;
  final String description;
  final String status;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  number,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isReady
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('selection-error'),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            key: const ValueKey('dismiss-error-button'),
            tooltip: 'Dismiss error',
            onPressed: onDismiss,
            color: colors.onErrorContainer,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SmallProgress extends StatelessWidget {
  const _SmallProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
        semanticsLabel: 'Opening file picker',
      ),
    );
  }
}
```

### File 5 — `test/widget_test.dart` — UPDATED

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/main.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/transfer_models.dart';
import 'package:sharebondhu/services/local_transfer_service.dart';
import 'package:sharebondhu/screens/nearby_screen.dart';

ShareFile sampleFile({
  String name = 'notes.pdf',
  String path = '/picked/notes.pdf',
  int size = 1536,
  Stream<List<int>> Function()? openRead,
}) {
  return ShareFile(
    name: name,
    size: size,
    sourceUri: Uri.file(path),
    readStream: openRead ?? () => Stream<List<int>>.value(<int>[1, 2, 3]),
  );
}

Future<void> mountApp(
  WidgetTester tester,
  PickShareFiles picker, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.light;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(
    tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
  );
  await tester.pumpWidget(ShareBondhuApp(pickFiles: picker));
  await tester.pumpAndSettle();
}

Future<void> tapSelect(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('select-files-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> tapNavigation(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  group('File model', () {
    test('formats bytes with binary units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1 KiB');
      expect(formatBytes(1536), '1.5 KiB');
      expect(formatBytes(1048576), '1 MiB');
      expect(formatBytes(9663676416), '9 GiB');
    });

    test('rejects negative byte counts', () {
      expect(() => formatBytes(-1), throwsArgumentError);
      expect(() => sampleFile(size: -1), throwsArgumentError);
    });

    test('classifies file extensions without case sensitivity', () {
      expect(sampleFile(name: 'PHOTO.JPEG').category, FileCategory.image);
      expect(sampleFile(name: 'clip.mp4').category, FileCategory.video);
      expect(sampleFile(name: 'song.flac').category, FileCategory.audio);
      expect(sampleFile(name: 'slides.pptx').category, FileCategory.document);
      expect(sampleFile(name: 'backup.7z').category, FileCategory.archive);
      expect(sampleFile(name: 'package.apk').category, FileCategory.other);
    });

    test('handles dotfiles and names without extensions', () {
      expect(sampleFile(name: '.gitignore').extension, '');
      expect(sampleFile(name: 'README').extension, '');
      expect(sampleFile(name: 'trailing.').extension, '');
      expect(sampleFile(name: 'report.final.PDF').extension, 'pdf');
    });

    test('keeps source identity separate from the display name', () {
      final first = sampleFile(name: 'notes.pdf', path: '/one/notes.pdf');
      final second = sampleFile(name: 'notes.pdf', path: '/two/notes.pdf');
      expect(first.name, second.name);
      expect(first.id, isNot(second.id));
    });

    test('does not read file content until a stream is requested', () async {
      var readCount = 0;
      final file = sampleFile(
        size: 3,
        openRead: () {
          readCount += 1;
          return Stream<List<int>>.value(<int>[1, 2, 3]);
        },
      );
      expect(file.formattedSize, '3 B');
      expect(file.categoryLabel, 'Document');
      expect(readCount, 0);
      final content = await file.openRead().expand((chunk) => chunk).toList();
      expect(content, <int>[1, 2, 3]);
      expect(readCount, 1);
      await file.openRead().drain<void>();
      expect(readCount, 2);
    });

    test('validates filenames and URI schemes', () {
      expect(() => sampleFile(name: '  '), throwsArgumentError);
      expect(
        () => ShareFile(
          name: 'notes.pdf',
          size: 3,
          sourceUri: Uri.parse('relative-file'),
          readStream: () => const Stream<List<int>>.empty(),
        ),
        throwsArgumentError,
      );
    });

    test('freezes selection results and validates unavailable counts', () {
      final original = <ShareFile>[sampleFile()];
      final selection = FileSelection(files: original);
      original.clear();
      expect(selection.files, hasLength(1));
      expect(() => selection.files.clear(), throwsUnsupportedError);
      expect(
        () => FileSelection(files: <ShareFile>[], unavailableCount: -1),
        throwsArgumentError,
      );
    });
  });

  group('Part 1 user interface', () {
    testWidgets('starts with the brand and an empty selection', (tester) async {
      await mountApp(tester, () async => FileSelection(files: <ShareFile>[]));
      expect(find.text('ShareBondhu'), findsOneWidget);
      expect(find.text('Select files'), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-count')), findsOneWidget);
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '0');
      expect(find.text('Transfer complete'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selects several files and calculates the total', (
      tester,
    ) async {
      final files = <ShareFile>[
        sampleFile(),
        sampleFile(name: 'photo.jpg', path: '/picked/photo.jpg', size: 512),
      ];
      await mountApp(tester, () async => FileSelection(files: files));
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('2 files · 2 KiB'), findsOneWidget);
      expect(find.text('Added 2 files.'), findsOneWidget);
      expect(find.text('Transfer complete'), findsNothing);
    });

    testWidgets('skips duplicate source references in one selection', (
      tester,
    ) async {
      final file = sampleFile();
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file, file]),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(
        find.text('Added 1 file. 1 duplicate reference skipped.'),
        findsOneWidget,
      );
    });

    testWidgets('skips duplicate source references across picker calls', (
      tester,
    ) async {
      final file = sampleFile();
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('add-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(find.text('1 duplicate reference skipped.'), findsOneWidget);
    });

    testWidgets('keeps files that share a name but have different sources', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[
            sampleFile(path: '/one/notes.pdf'),
            sampleFile(path: '/two/notes.pdf'),
          ],
        ),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsNWidgets(2));
      expect(find.text('2 files · 3 KiB'), findsOneWidget);
    });

    testWidgets('preserves the selection when the picker is canceled', (
      tester,
    ) async {
      var calls = 0;
      await mountApp(tester, () async {
        calls += 1;
        return FileSelection(
          files: calls == 1 ? <ShareFile>[sampleFile()] : <ShareFile>[],
        );
      });
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('add-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('removes a reference without reading its original file', (
      tester,
    ) async {
      var reads = 0;
      final file = sampleFile(
        openRead: () {
          reads += 1;
          return const Stream<List<int>>.empty();
        },
      );
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[file]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(ValueKey('remove:${file.id}')));
      await tester.pumpAndSettle();
      expect(find.text('0 files · 0 B'), findsOneWidget);
      expect(find.text('notes.pdf'), findsNothing);
      expect(reads, 0);
      expect(
        find.text('Removed from selection. Your original file is unchanged.'),
        findsOneWidget,
      );
    });

    testWidgets('asks before clearing and respects both dialog choices', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      await tester.tap(find.byKey(const ValueKey('clear-selection-button')));
      await tester.pumpAndSettle();
      expect(find.text('Clear selection?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('keep-files-button')));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-selection-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-clear-button')));
      await tester.pumpAndSettle();
      expect(find.text('0 files · 0 B'), findsOneWidget);
      expect(find.text('notes.pdf'), findsNothing);
    });

    testWidgets('shows unavailable-file feedback without losing valid files', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[sampleFile()],
          unavailableCount: 1,
        ),
      );
      await tapSelect(tester);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(
        find.text(
          'Added 1 file. 1 file was unavailable. Save locally and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reports an entirely unavailable selection', (tester) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[], unavailableCount: 2),
      );
      await tapSelect(tester);
      expect(
        find.text('2 files were unavailable. Save locally and try again.'),
        findsOneWidget,
      );
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '0');
    });

    testWidgets('shows access errors and permits a successful retry', (
      tester,
    ) async {
      var calls = 0;
      await mountApp(tester, () async {
        calls += 1;
        if (calls == 1) {
          throw PlatformException(code: 'permission_denied');
        }
        return FileSelection(files: <ShareFile>[sampleFile()]);
      });
      await tapSelect(tester);
      expect(find.byKey(const ValueKey('selection-error')), findsOneWidget);
      expect(
        find.text(
          'File access was not allowed. You can try the system picker again.',
        ),
        findsOneWidget,
      );
      await tapSelect(tester);
      expect(find.byKey(const ValueKey('selection-error')), findsNothing);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('reports missing native plugins with rebuild instructions', (
      tester,
    ) async {
      await mountApp(tester, () async => throw MissingPluginException());
      await tapSelect(tester);
      expect(find.textContaining('run flutter pub get'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dismiss-error-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selection-error')), findsNothing);
    });

    testWidgets('handles an unexpected picker error without crashing', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => throw StateError('test picker failure'),
      );
      await tapSelect(tester);
      expect(
        find.text(
          'We could not read that selection. Try choosing locally stored files.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('prevents repeated picker calls while selection is pending', (
      tester,
    ) async {
      final pending = Completer<FileSelection>();
      var calls = 0;
      await mountApp(tester, () {
        calls += 1;
        return pending.future;
      });
      final button = find.byKey(const ValueKey('select-files-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(calls, 1);
      pending.complete(FileSelection(files: <ShareFile>[sampleFile()]));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('notes.pdf'), findsOneWidget);
    });

    testWidgets('changes themes without losing the current selection', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      final scaffold = find.byKey(const ValueKey('main-scaffold'));
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.dark);
      expect(find.text('notes.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(scaffold)).brightness, Brightness.light);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
    });

    testWidgets('keeps the selection when switching navigation tabs', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      await tapNavigation(tester, 'nav-guide');
      expect(find.text('One step at a time.'), findsOneWidget);
      expect(find.text('Connect nearby'), findsOneWidget);
      await tapNavigation(tester, 'nav-home');
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('selected-count')),
      );
      expect(count.data, '1');
      await tapNavigation(tester, 'nav-files');
      expect(find.text('notes.pdf'), findsOneWidget);
    });

    testWidgets('handles large metadata without reading the file into memory', (
      tester,
    ) async {
      var reads = 0;
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[
            sampleFile(
              name: 'large-video.mkv',
              size: 9663676416,
              openRead: () {
                reads += 1;
                return const Stream<List<int>>.empty();
              },
            ),
          ],
        ),
      );
      await tapSelect(tester);
      expect(find.text('1 file · 9 GiB'), findsOneWidget);
      expect(reads, 0);
    });

    testWidgets('renders narrow screens without layout errors', (tester) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      await tapSelect(tester);
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-guide');
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports large system text on a narrow screen', (
      tester,
    ) async {
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
        size: const Size(320, 740),
      );
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-files');
      expect(tester.takeException(), isNull);
      await tapNavigation(tester, 'nav-guide');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ignores late picker results after the screen is disposed', (
      tester,
    ) async {
      final pending = Completer<FileSelection>();
      await mountApp(tester, () => pending.future);
      final button = find.byKey(const ValueKey('select-files-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(FileSelection(files: <ShareFile>[sampleFile()]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
  registerPart2Tests();
}

ShareFile bytesFile(
  String name,
  List<int> bytes, {
  Stream<List<int>> Function()? reader,
  int? declaredSize,
}) {
  return ShareFile(
    name: name,
    size: declaredSize ?? bytes.length,
    sourceUri: Uri.file('/test-source/${randomTransferId()}'),
    readStream: reader ?? () => Stream<List<int>>.value(bytes),
  );
}

class ReceiverFixture {
  ReceiverFixture(this.root, this.receiver, this.session, this.receipts);

  final Directory root;
  final LocalReceiver receiver;
  final ReceiverSession session;
  final List<TransferReceipt> receipts;

  PairingCode get code => session.codeFor('127.0.0.1');

  Future<void> close() async {
    await receiver.stop();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Future<ReceiverFixture> startReceiverFixture(
  TlsIdentity identity, {
  Future<bool> Function(IncomingOffer)? approve,
  void Function(TransferProgress)? progress,
  Duration approvalTimeout = const Duration(seconds: 2),
  Duration inviteLifetime = const Duration(minutes: 2),
  Duration batchTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 30),
}) async {
  final root = await Directory.systemTemp.createTemp('sharebondhu-test-');
  final receipts = <TransferReceipt>[];
  final receiver = LocalReceiver(
    storageRoot: root,
    identityFactory: () async => identity,
    allowLoopback: true,
    approvalTimeout: approvalTimeout,
    inviteLifetime: inviteLifetime,
    batchTimeout: batchTimeout,
    idleTimeout: idleTimeout,
    onOffer: approve ?? (_) async => true,
    onProgress: progress,
    onReceived: receipts.add,
  );
  try {
    final session = await receiver.start(
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedAddresses: <String>['127.0.0.1'],
    );
    final fixture = ReceiverFixture(root, receiver, session, receipts);
    addTearDown(fixture.close);
    return fixture;
  } catch (_) {
    await receiver.stop();
    await root.delete(recursive: true);
    rethrow;
  }
}

Future<(int, Map<String, dynamic>)> rawTransferRequest(
  PairingCode code,
  String method,
  String path, {
  String? token,
  Map<String, Object>? json,
  List<int>? bytes,
  String? origin,
}) async {
  final client = createPinnedClient(code);
  try {
    final request = await client.openUrl(method, code.endpoint(path));
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${token ?? code.token}',
    );
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    if (json != null) {
      final body = utf8.encode(jsonEncode(json));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
    } else if (bytes != null) {
      request.headers.contentType = ContentType.binary;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 5));
    return (response.statusCode, await readBoundedJson(response));
  } finally {
    client.close(force: true);
  }
}

void registerPart2Tests() {
  group('Part 2 protocol models', () {
    test('pairing code round trips without exposing secrets in toString', () {
      final code = PairingCode(
        host: '192.168.4.1',
        port: 42000,
        token: randomToken(),
        fingerprint: List<String>.filled(64, 'a').join(),
      );
      expect(code.encode(), hasLength(98));
      final decoded = PairingCode.parse(code.encode());
      expect(decoded.host, code.host);
      expect(decoded.port, code.port);
      expect(decoded.token, code.token);
      expect(decoded.fingerprint, code.fingerprint);
      expect(code.toString(), isNot(contains(code.token)));
      expect(code.endpoint('/v1/offer').scheme, 'https');
    });

    test(
      'pairing rejects malformed, public, DNS and normal-app loopback targets',
      () {
        expect(
          () => PairingCode.parse('not a code'),
          throwsA(isA<TransferException>()),
        );
        for (final host in <String>[
          '8.8.8.8',
          'example.com',
          '127.0.0.1',
          '::1',
          '0.0.0.0',
        ]) {
          expect(
            () => PairingCode(
              host: host,
              port: 443,
              token: randomToken(),
              fingerprint: List<String>.filled(64, 'a').join(),
            ),
            throwsA(isA<TransferException>()),
          );
        }
        expect(isLocalIpv4('10.0.0.2'), isTrue);
        expect(isLocalIpv4('172.16.0.2'), isTrue);
        expect(isLocalIpv4('172.32.0.2'), isFalse);
        expect(isLocalIpv4('169.254.3.4'), isTrue);
      },
    );

    test(
      'filenames cannot create paths or hide direction-control characters',
      () {
        for (final name in <String>[
          '../../outside.txt',
          r'C:\system\file.txt',
          'bad\u202ename.txt',
          '.',
        ]) {
          final safe = safeFileName(name);
          expect(safe.contains('/'), isFalse);
          expect(safe.contains(r'\'), isFalse);
          expect(safe.contains('\u202e'), isFalse);
          expect(safe.startsWith('.'), isFalse);
          expect(safe, isNotEmpty);
        }
        expect(safeFileName('CON.txt'), '_CON.txt');
        expect(
          utf8
              .encode(safeFileName(List<String>.filled(200, 'বাংলা').join()))
              .length,
          lessThanOrEqualTo(180),
        );
      },
    );

    test('offer bounds reject empty, oversized and duplicate-id batches', () {
      expect(
        () => createOutgoingOffer(<ShareFile>[], 'test'),
        throwsA(isA<TransferException>()),
      );
      expect(
        () => createOutgoingOffer(<ShareFile>[
          bytesFile(
            'large.bin',
            <int>[],
            declaredSize: TransferLimits.maxFileBytes + 1,
          ),
        ], 'test'),
        throwsA(isA<TransferException>()),
      );
      expect(
        () => createOutgoingOffer(
          List<ShareFile>.generate(
            51,
            (index) => bytesFile('$index.txt', <int>[]),
          ),
          'test',
        ),
        throwsA(isA<TransferException>()),
      );
      final file = OfferedFile(id: randomTransferId(), name: 'a.txt', size: 1);
      expect(
        () => IncomingOffer(
          id: randomTransferId(),
          senderName: 'test',
          remoteAddress: '',
          files: <OfferedFile>[file, file],
        ),
        throwsA(isA<TransferException>()),
      );
      expect(
        () => createOutgoingOffer(
          List<ShareFile>.generate(
            3,
            (index) => bytesFile(
              '$index.bin',
              <int>[],
              declaredSize: TransferLimits.maxFileBytes,
            ),
          ),
          'test',
        ),
        throwsA(isA<TransferException>()),
      );
    });

    test('wire metadata and receipts never serialize local source paths', () {
      final source = bytesFile('a.txt', <int>[1]);
      final offer = createOutgoingOffer(<ShareFile>[source], 'device');
      expect(
        jsonEncode(offer.toJson()),
        isNot(contains(source.sourceUri.toString())),
      );
      final receipt = TransferReceipt(
        id: offer.id,
        senderName: 'device',
        completedAt: DateTime.utc(2026, 9, 6),
        files: <ReceivedFile>[
          ReceivedFile(
            id: offer.files.first.id,
            name: 'a.txt',
            size: 1,
            digest: sha256.convert(<int>[1]).toString(),
            localPath: '/private/app/a.txt',
          ),
        ],
      );
      expect(jsonEncode(receipt.toJson()), isNot(contains('/private')));
      expect(
        TransferReceipt.fromJson(receipt.toJson()).files.first.localPath,
        isNull,
      );
    });

    test(
      'bounded JSON rejects large messages, arrays and incomplete input',
      () async {
        expect(
          await readBoundedJson(
            Stream<List<int>>.value(utf8.encode('{"ok":true}')),
          ),
          <String, dynamic>{'ok': true},
        );
        await expectLater(
          readBoundedJson(
            Stream<List<int>>.value(List<int>.filled(20, 65)),
            maxBytes: 10,
          ),
          throwsA(isA<TransferException>()),
        );
        await expectLater(
          readBoundedJson(Stream<List<int>>.value(utf8.encode('[]'))),
          throwsA(isA<TransferException>()),
        );
        final controller = StreamController<List<int>>();
        await expectLater(
          readBoundedJson(
            controller.stream,
            timeout: const Duration(milliseconds: 20),
          ),
          throwsA(isA<TimeoutException>()),
        );
        await controller.close();
      },
    );

    test('an invalid checksum cannot be parsed as a receipt', () {
      final offer = createOutgoingOffer(<ShareFile>[
        bytesFile('a.txt', <int>[1]),
      ], 'test');
      expect(
        () => TransferReceipt.fromJson(<String, dynamic>{
          'version': 1,
          'id': offer.id,
          'senderName': 'test',
          'completedAt': DateTime.utc(2026).toIso8601String(),
          'files': <Object>[
            <String, Object>{
              'id': offer.files.first.id,
              'name': 'a.txt',
              'size': 1,
              'sha256': 'wrong',
            },
          ],
        }),
        throwsA(isA<TransferException>()),
      );
    });

    test('all byte progress can still be awaiting verification', () {
      const progress = TransferProgress(
        phase: TransferPhase.verifying,
        message: 'Verifying',
        totalBytes: 8,
        processedBytes: 8,
      );
      expect(progress.fraction, 1);
      expect(progress.indeterminate, isTrue);
      expect(progress.phase, isNot(TransferPhase.completed));
    });
  });

  group('Part 2 real loopback TLS transfers', () {
    late TlsIdentity identity;
    HttpOverrides? previousOverrides;

    setUpAll(() async {
      identity = await TlsIdentity.generate();
    });
    setUp(() {
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() {
      HttpOverrides.global = previousOverrides;
    });

    test(
      'streams multiple files, verifies hashes and preserves duplicate names',
      () async {
        var approved = false;
        final fixture = await startReceiverFixture(
          identity,
          approve: (offer) async {
            approved = true;
            return true;
          },
        );
        final bytes = List<int>.generate(131073, (index) => index % 251);
        Stream<List<int>> chunks() async* {
          expect(approved, isTrue);
          for (var offset = 0; offset < bytes.length; offset += 4096) {
            yield bytes.sublist(offset, (offset + 4096).clamp(0, bytes.length));
          }
        }

        final phases = <TransferPhase>[];
        final receipt = await LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('same.bin', bytes, reader: chunks),
            bytesFile('same.bin', <int>[5, 6, 7]),
            bytesFile('empty.txt', <int>[]),
          ],
          senderName: 'Test sender',
          onProgress: (progress) => phases.add(progress.phase),
        );
        expect(receipt.totalBytes, bytes.length + 3);
        expect(phases.last, TransferPhase.completed);
        expect(phases, contains(TransferPhase.verifying));
        expect(fixture.receipts, hasLength(1));
        final saved = fixture.receipts.single.files;
        expect(saved.map((file) => file.localPath).toSet(), hasLength(3));
        expect(await File(saved[0].localPath!).readAsBytes(), bytes);
        expect(await File(saved[1].localPath!).readAsBytes(), <int>[5, 6, 7]);
        expect(await File(saved[2].localPath!).length(), 0);
        expect(saved[0].digest, sha256.convert(bytes).toString());
        expect(
          (await fixture.root.list().toList()).every(
            (entity) => entity.path.contains('received-'),
          ),
          isTrue,
        );
        await fixture.receiver.stop();
        expect(await File(saved[0].localPath!).exists(), isTrue);
      },
    );

    test('decline reads no content and writes no staging files', () async {
      var reads = 0;
      final fixture = await startReceiverFixture(
        identity,
        approve: (_) async => false,
      );
      await expectLater(
        LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile(
              'a.txt',
              <int>[1],
              reader: () {
                reads += 1;
                return Stream<List<int>>.value(<int>[1]);
              },
            ),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
      expect(reads, 0);
      expect(await fixture.root.list().toList(), isEmpty);
      expect(fixture.receipts, isEmpty);
    });

    test('wrong pairing token never reaches receiver approval', () async {
      var offers = 0;
      final fixture = await startReceiverFixture(
        identity,
        approve: (_) async {
          offers += 1;
          return true;
        },
      );
      final wrong = PairingCode(
        host: fixture.code.host,
        port: fixture.code.port,
        token: randomToken(),
        fingerprint: fixture.code.fingerprint,
        allowLoopback: true,
      );
      await expectLater(
        LocalSender().send(
          code: wrong,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1]),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
      expect(offers, 0);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test(
      'wrong TLS fingerprint is rejected and the listener stays usable',
      () async {
        final fixture = await startReceiverFixture(identity);
        final wrong = PairingCode(
          host: fixture.code.host,
          port: fixture.code.port,
          token: fixture.code.token,
          fingerprint: List<String>.filled(64, '0').join(),
          allowLoopback: true,
        );
        await expectLater(
          LocalSender().send(
            code: wrong,
            files: <ShareFile>[
              bytesFile('a.txt', <int>[1]),
            ],
            senderName: 'test',
          ),
          throwsA(isA<TransferException>()),
        );
        expect(fixture.receipts, isEmpty);
        final receipt = await LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1]),
          ],
          senderName: 'test',
        );
        expect(receipt.totalBytes, 1);
      },
    );

    test('approval timeout defaults to rejection', () async {
      final decision = Completer<bool>();
      final fixture = await startReceiverFixture(
        identity,
        approve: (_) => decision.future,
        approvalTimeout: const Duration(milliseconds: 80),
      );
      await expectLater(
        LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1]),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
      decision.complete(false);
      expect(fixture.receipts, isEmpty);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test('an expired invitation closes the receiver', () async {
      final fixture = await startReceiverFixture(
        identity,
        inviteLifetime: const Duration(milliseconds: 60),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.receiver.isRunning, isFalse);
      await expectLater(
        LocalSender(connectionTimeout: const Duration(milliseconds: 200)).send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1]),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
    });

    test('truncated source data cannot be committed', () async {
      final fixture = await startReceiverFixture(identity);
      await expectLater(
        LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1, 2], declaredSize: 4),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
      await fixture.receiver.stop();
      expect(fixture.receipts, isEmpty);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test('extra source bytes cannot exceed the approved size', () async {
      final fixture = await startReceiverFixture(identity);
      await expectLater(
        LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('a.txt', <int>[1, 2, 3], declaredSize: 1),
          ],
          senderName: 'test',
        ),
        throwsA(isA<TransferException>()),
      );
      await fixture.receiver.stop();
      expect(fixture.receipts, isEmpty);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test(
      'a later source read failure rolls back the entire uncommitted batch',
      () async {
        final fixture = await startReceiverFixture(identity);
        Stream<List<int>> broken() async* {
          throw const FileSystemException('Test source became unavailable.');
        }

        await expectLater(
          LocalSender().send(
            code: fixture.code,
            files: <ShareFile>[
              bytesFile('first.txt', <int>[1, 2, 3]),
              bytesFile('second.txt', <int>[1], reader: broken),
            ],
            senderName: 'test',
          ),
          throwsA(isA<TransferException>()),
        );
        await fixture.receiver.stop();
        expect(fixture.receipts, isEmpty);
        expect(await fixture.root.list().toList(), isEmpty);
      },
    );

    test(
      'sender cancellation interrupts a real upload and cleans staging',
      () async {
        final sender = LocalSender();
        final fixture = await startReceiverFixture(
          identity,
          progress: (progress) {
            if (progress.phase == TransferPhase.receiving &&
                progress.processedBytes > 0) {
              sender.cancel();
            }
          },
        );
        Stream<List<int>> slow() async* {
          for (var i = 0; i < 30; i += 1) {
            yield List<int>.filled(1024, i);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }

        await expectLater(
          sender.send(
            code: fixture.code,
            files: <ShareFile>[
              bytesFile(
                'slow.bin',
                <int>[],
                declaredSize: 30 * 1024,
                reader: slow,
              ),
            ],
            senderName: 'test',
          ),
          throwsA(isA<TransferCancelled>()),
        );
        await fixture.receiver.stop();
        expect(fixture.receipts, isEmpty);
        expect(await fixture.root.list().toList(), isEmpty);
      },
    );

    test(
      'stopping the receiver during upload does not leave uncommitted files',
      () async {
        LocalReceiver? receiver;
        var stopped = false;
        final fixture = await startReceiverFixture(
          identity,
          progress: (progress) {
            if (!stopped &&
                progress.phase == TransferPhase.receiving &&
                progress.processedBytes > 0) {
              stopped = true;
              unawaited(receiver!.stop());
            }
          },
        );
        receiver = fixture.receiver;
        Stream<List<int>> slow() async* {
          for (var i = 0; i < 30; i += 1) {
            yield List<int>.filled(1024, i);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }

        await expectLater(
          LocalSender().send(
            code: fixture.code,
            files: <ShareFile>[
              bytesFile(
                'slow.bin',
                <int>[],
                declaredSize: 30 * 1024,
                reader: slow,
              ),
            ],
            senderName: 'test',
          ),
          throwsA(isA<TransferException>()),
        );
        await receiver.stop();
        expect(stopped, isTrue);
        expect(fixture.receipts, isEmpty);
        expect(await fixture.root.list().toList(), isEmpty);
      },
    );

    test('a second offer cannot bypass a pending approval', () async {
      final offered = Completer<void>();
      final decision = Completer<bool>();
      final fixture = await startReceiverFixture(
        identity,
        approve: (_) {
          if (!offered.isCompleted) offered.complete();
          return decision.future;
        },
      );
      final first = LocalSender().send(
        code: fixture.code,
        files: <ShareFile>[
          bytesFile('a.txt', <int>[1]),
        ],
        senderName: 'first',
      );
      final firstExpectation = expectLater(
        first,
        throwsA(isA<TransferException>()),
      );
      await offered.future;
      await expectLater(
        LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('b.txt', <int>[2]),
          ],
          senderName: 'second',
        ),
        throwsA(isA<TransferException>()),
      );
      decision.complete(false);
      await firstExpectation;
      expect(fixture.receipts, isEmpty);
    });

    test('wrong commit checksums discard all staged files', () async {
      final fixture = await startReceiverFixture(identity);
      final offer = createOutgoingOffer(<ShareFile>[
        bytesFile('a.txt', <int>[1, 2, 3]),
      ], 'test');
      final accepted = await rawTransferRequest(
        fixture.code,
        'POST',
        '/v1/offer',
        json: offer.toJson(),
      );
      expect(accepted.$1, 200);
      final token = accepted.$2['uploadToken'] as String;
      final fileId = offer.files.single.id;
      final uploaded = await rawTransferRequest(
        fixture.code,
        'PUT',
        '/v1/files/${offer.id}/$fileId',
        token: token,
        bytes: <int>[1, 2, 3],
      );
      expect(uploaded.$1, 200);
      expect(fixture.receipts, isEmpty);
      final committed = await rawTransferRequest(
        fixture.code,
        'POST',
        '/v1/commit/${offer.id}',
        token: token,
        json: <String, Object>{
          'sha256': <String, String>{
            fileId: List<String>.filled(64, '0').join(),
          },
        },
      );
      expect(committed.$1, 422);
      expect(fixture.receipts, isEmpty);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test(
      'path-like filenames stay inside the receiver-owned directory',
      () async {
        final fixture = await startReceiverFixture(identity);
        await LocalSender().send(
          code: fixture.code,
          files: <ShareFile>[
            bytesFile('../../outside.txt', <int>[8, 9]),
          ],
          senderName: 'test',
        );
        final file = fixture.receipts.single.files.single;
        expect(file.name.contains('/'), isFalse);
        expect(file.localPath, startsWith(fixture.root.path));
        expect(await File(file.localPath!).readAsBytes(), <int>[8, 9]);
        expect(
          await File('${fixture.root.parent.path}/outside.txt').exists(),
          isFalse,
        );
      },
    );

    test('browser-origin requests and unknown endpoints are refused', () async {
      final fixture = await startReceiverFixture(identity);
      final origin = await rawTransferRequest(
        fixture.code,
        'POST',
        '/v1/offer',
        json: <String, Object>{},
        origin: 'https://untrusted.example',
      );
      expect(origin.$1, 403);
      final unknown = await rawTransferRequest(
        fixture.code,
        'GET',
        '/private-files',
      );
      expect(unknown.$1, 404);
      expect(fixture.receipts, isEmpty);
    });

    test('approved but abandoned batches expire and clean staging', () async {
      final expired = Completer<void>();
      final fixture = await startReceiverFixture(
        identity,
        batchTimeout: const Duration(milliseconds: 100),
        progress: (progress) {
          if (progress.phase == TransferPhase.failed && !expired.isCompleted) {
            expired.complete();
          }
        },
      );
      final offer = createOutgoingOffer(<ShareFile>[
        bytesFile('a.txt', <int>[1]),
      ], 'test');
      expect(
        (await rawTransferRequest(
          fixture.code,
          'POST',
          '/v1/offer',
          json: offer.toJson(),
        )).$1,
        200,
      );
      await expired.future.timeout(const Duration(seconds: 2));
      expect(fixture.receipts, isEmpty);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test(
      'the first-upload idle deadline also cleans an approved batch',
      () async {
        final expired = Completer<void>();
        final fixture = await startReceiverFixture(
          identity,
          idleTimeout: const Duration(milliseconds: 100),
          progress: (progress) {
            if (progress.phase == TransferPhase.failed &&
                !expired.isCompleted) {
              expired.complete();
            }
          },
        );
        final offer = createOutgoingOffer(<ShareFile>[
          bytesFile('a.txt', <int>[1]),
        ], 'test');
        expect(
          (await rawTransferRequest(
            fixture.code,
            'POST',
            '/v1/offer',
            json: offer.toJson(),
          )).$1,
          200,
        );
        await expired.future.timeout(const Duration(seconds: 2));
        expect(await fixture.root.list().toList(), isEmpty);
        expect(fixture.receipts, isEmpty);
      },
    );

    test('the server enforces the file-count limit before approval', () async {
      var approvalCalls = 0;
      final fixture = await startReceiverFixture(
        identity,
        approve: (_) async {
          approvalCalls += 1;
          return true;
        },
      );
      final result = await rawTransferRequest(
        fixture.code,
        'POST',
        '/v1/offer',
        json: <String, Object>{
          'version': 1,
          'id': randomTransferId(),
          'senderName': 'test',
          'files': List<Map<String, Object>>.generate(
            51,
            (index) => <String, Object>{
              'id': randomTransferId(),
              'name': '$index.txt',
              'size': 1,
            },
          ),
        },
      );
      expect(result.$1, 422);
      expect(approvalCalls, 0);
      expect(await fixture.root.list().toList(), isEmpty);
    });

    test(
      'a completed receipt can be recovered with its upload token only',
      () async {
        final fixture = await startReceiverFixture(identity);
        final offer = createOutgoingOffer(<ShareFile>[
          bytesFile('a.txt', <int>[1, 2, 3]),
        ], 'test');
        final accepted = await rawTransferRequest(
          fixture.code,
          'POST',
          '/v1/offer',
          json: offer.toJson(),
        );
        final token = accepted.$2['uploadToken'] as String;
        final id = offer.files.single.id;
        await rawTransferRequest(
          fixture.code,
          'PUT',
          '/v1/files/${offer.id}/$id',
          token: token,
          bytes: <int>[1, 2, 3],
        );
        final result = await rawTransferRequest(
          fixture.code,
          'POST',
          '/v1/commit/${offer.id}',
          token: token,
          json: <String, Object>{
            'sha256': <String, String>{
              id: sha256.convert(<int>[1, 2, 3]).toString(),
            },
          },
        );
        expect(result.$1, 200);
        final recovered = await rawTransferRequest(
          fixture.code,
          'GET',
          '/v1/status/${offer.id}',
          token: token,
        );
        expect(recovered.$1, 200);
        expect(recovered.$2, result.$2);
        final denied = await rawTransferRequest(
          fixture.code,
          'GET',
          '/v1/status/${offer.id}',
        );
        expect(denied.$1, 404);
        expect(jsonEncode(recovered.$2), isNot(contains(fixture.root.path)));
      },
    );
  });

  group('Part 2 navigation', () {
    testWidgets('backgrounding during storage lookup never starts a receiver', (
      tester,
    ) async {
      final directory = Completer<Directory>();
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyScreen(
            mode: NearbyMode.receive,
            documentsDirectory: () => directory.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('start-receiving-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      directory.complete(Directory('/unused-test-directory'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('receiving-code')), findsNothing);
      expect(find.text('Creating session'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('receive screen is opt-in and returning preserves selection', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      await tapNavigation(tester, 'nav-home');
      final button = find.byKey(const ValueKey('receive-files-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('start-receiving-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('receiving-code')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapNavigation(tester, 'nav-files');
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
    });

    testWidgets('send screen opens without reading source bytes', (
      tester,
    ) async {
      var reads = 0;
      await mountApp(
        tester,
        () async => FileSelection(
          files: <ShareFile>[
            sampleFile(
              openRead: () {
                reads += 1;
                return const Stream<List<int>>.empty();
              },
            ),
          ],
        ),
      );
      await tapSelect(tester);
      final button = find.byKey(const ValueKey('send-selected-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pairing-code-field')), findsOneWidget);
      expect(reads, 0);
      expect(find.text('Delivery confirmed'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
    });

    testWidgets('invalid pairing code is rejected before networking', (
      tester,
    ) async {
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
      );
      await tapSelect(tester);
      final send = find.byKey(const ValueKey('send-selected-button'));
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('ask-to-send-button'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('Use the complete SB1 pairing code'),
        -300,
        scrollable: scroll,
      );
      expect(
        find.textContaining('Use the complete SB1 pairing code'),
        findsOneWidget,
      );
      expect(find.text('Delivery confirmed'), findsNothing);
    });

    testWidgets('nearby sender layout supports narrow large-text screens', (
      tester,
    ) async {
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await mountApp(
        tester,
        () async => FileSelection(files: <ShareFile>[sampleFile()]),
        size: const Size(320, 740),
      );
      await tapSelect(tester);
      final button = find.byKey(const ValueKey('send-selected-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nearby-scaffold')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
```


## প্রজেক্ট ফাইলের পূর্ণতা ও চালানো

ZIP-এ numbered File 1–10 ছাড়াও complete Android/iOS runner, launcher assets, Gradle wrapper, analysis configuration, dependency lockfile এবং documentation আছে। SDK/package cache/compiled output/machine-specific paths source deliverable নয়; `flutter pub get` ও Flutter run/build সেগুলো তৈরি করে। ZIP-এর প্রতিটি included file `docs/FILE_INVENTORY.txt`-এ আছে।

পুরোনো app পুরো stop করুন; শুধু hot reload নয়। project root-এ চালান:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Native Android/iOS build ও দুই বাস্তব ফোনের পরীক্ষা এখনো বাকি। এই source ZIP কোনো APK/IPA নয়। প্রথমে ছোট, locally stored file দিয়ে trusted Wi-Fi-তে পরীক্ষা করুন। Local-network permission deny করা থাকলে OS Settings থেকে এই app-এর অনুমতি পর্যালোচনা করুন।

### যাচাইয়ের ফল

- `flutter analyze`: No issues found.
- `flutter test`: 60 tests passed; আগের 28টি test-সহ।
- বাস্তব loopback HTTPS/TLS stream, disk output, hash matching, wrong token/pin, rejection, cancellation, timeout ও cleanup-এর tests আছে। এগুলো physical Android/iPhone integration tests নয়।
- File 2 ও 3 baseline-এর সঙ্গে byte-identical। Home-এর আগের methods, প্রথম 28টি test name এবং আগের iOS runner keys রক্ষার verification হয়েছে।
- এই guide-এর সব code block ও ZIP-এর corresponding source file byte-for-byte মিলিয়ে পরীক্ষা করা হয়েছে।

## ▶ Next — Part 3 (File 11–15)

পরের ধাপে QR pairing ও saved-file/history interface যোগ হবে। বর্তমান manual pairing, endpoint ও selection logic রাখা হবে। কোনো আগের file বদলালে সম্পূর্ণ updated file আবার দেব।

চালিয়ে যেতে চ্যাটে **`Next`** লিখুন।
