# ShareBondhu — Part 3 (File 11–15)

## Full Code + বাংলা ব্যবহার নির্দেশনা

নিজের ব্র্যান্ডের Flutter Android + iPhone অ্যাপের তৃতীয় ধাপ। **নতুন File 11–15**: QR display/scanner ও saved-file history। আগের manual pairing, selection, theme, receiver approval ও TLS transfer রাখা হয়েছে। নতুন database বা পুরোনো received files migrate করার দরকার নেই।

## এই Part-এ যা যোগ হয়েছে

- Receiver-এর একই **৯৮ অক্ষরের SB1 code** এখন QR হিসেবে দেখানো হয়। QR-এর নিচে আগের manual code ও Copy code আছে।
- QR-তে white quiet zone, black modules, expiry countdown; invitation expire হলে QR লুকানো হয়। নতুন code নিজে থেকে তৈরি হয় না।
- Sender-এর **Scan receiver QR → Start camera → Use this code** flow। তারপরও **Ask to send** চাপতে হয় এবং receiver-কে **Accept** করতে হয়। স্ক্যান কোনো network request বা file transfer নিজে থেকে শুরু করে না।
- Camera permission optional; না দিলে manual pairing চালু থাকে। Arbitrary URL/অন্য QR খোলা হয় না। Duplicate detection, pause, retry, flashlight এবং startup/background/disposal guard আছে।
- Home-এর **Saved files**: Part 2 ও পরের receiving session-এর `transfer.json` পড়ে batch, sender, সময়, filename ও recorded size দেখায়।
- Local search, Available / Needs attention filter, missing/changed/unreadable file status এবং **Verify checksums**। শুধু size মিলে গেলে বর্তমানে verified বলা হয় না।
- History থেকে একটি file বা পুরো batch আবার share করা যায়। History-এর share action আগে সংশ্লিষ্ট file-এর SHA-256 পরীক্ষা করে, তারপর native share sheet খোলে।
- History read-only: কোনো delete, rename, receipt rewrite, automatic repair বা original source file পরিবর্তনের ব্যবস্থা যোগ করা হয়নি।

## কী অপরিবর্তিত

**File 2, 3, 6 ও 7 Part 2-এর সঙ্গে byte-for-byte একই।** অর্থাৎ app entry/theme, selected-file model, SB1 protocol model এবং সম্পূর্ণ TLS engine অপরিবর্তিত। পাঁচটি v1 endpoint-ও একই আছে। File 4 ও 8-এর আগের methods রেখে নতুন UI যোগ হয়েছে। Camera permission ছাড়া iOS-এর আগের keys বদলানো হয়নি; Android-এর আগের permission/activity/query রাখা হয়েছে।

## পরীক্ষার ফল ও সীমা

- Flutter static analysis: **No issues found**।
- **৯৭টি automated test পাস**: আগের ৬০টি এবং নতুন ৩৭টি।
- Actual filesystem history, hash checking, changed/missing copies, symlink rejection, cancellation এবং আগের TLS engine-এর output history-তে পড়ার পরীক্ষা হয়েছে।
- Flutter-rendered QR-এর দুইটি demo payload software decoder দিয়ে আবার পড়ে সম্পূর্ণ ৯৮ অক্ষরের SB1 data মিলিয়ে দেখা হয়েছে।
- Camera lifecycle/permission/UI পরীক্ষায় **test camera** ব্যবহার হয়েছে। এটি বাস্তব camera test নয়।

**এই পরিবেশে Android/iPhone native compilation, দুই ফোনের Wi-Fi transfer, বাস্তব camera scan, native permission prompt এবং share sheet যাচাই করা হয়নি। ZIP-এ তৈরি APK/IPA নেই। এটি development MVP, store-ready release নয়।**

## কম্পিউটারে চালান

পরীক্ষিত toolchain: **Flutter 3.47.2 / Dart 3.13.2**। Minimum: Flutter 3.47.0 / Dart 3.13.0। আগের direct dependencies রাখা হয়েছে; নতুন pinned dependencies: `qr_flutter 4.1.0`, `mobile_scanner 7.4.0`, `path 1.9.1`। Transitive graph `pubspec.lock`-এ আছে।

Flutter install: https://docs.flutter.dev/install

Android Studio: https://developer.android.com/studio

ZIP extract করে `sharebondhu` folder-এ terminal খুলুন:

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

**আগের app পুরো stop করে rebuild করুন।** Camera/native plugin যোগ হওয়া শুধু hot reload দিয়ে কার্যকর হবে না। প্রথমে আগের project backup রাখুন। এই ZIP-এ standard Android/iOS runner, assets, Gradle wrapper ও complete source আছে; SDK/cache/build output/machine-specific configuration নেই। Flutter tools সেগুলো regenerate করে।

Android: Android Studio SDK/toolchain ও compatible Java 17+ JDK দরকার; Java 11 নয়। বর্তমান generated configuration target/compile SDK 36, minimum SDK 24। Camera hardware optional ঘোষণা করা হয়েছে, যাতে camera ছাড়া device-এ manual mode রাখা যায়। Future target-SDK upgrade-এর আগে নতুন permission requirements যাচাই করতে হবে।

নিজের কম্পিউটারে debug APK:

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`। এটি development build; release signing এখনো প্রস্তুত নয়।

iPhone: Mac ও compatible Xcode দরকার; real device-এর জন্য signing team। iOS deployment target 15.0। Windows/Linux থেকে স্থানীয় iOS build নয়। Mac-এ:

```bash
open -a Simulator
flutter devices
flutter run
```

Camera feature পরীক্ষা করতে উপযুক্ত বাস্তব device ব্যবহার করুন। Simulator/no-camera environment-এ manual pairing ব্যবহার করুন।

## QR দিয়ে দুই ফোনে ব্যবহার

1. দুই ফোনে app চালিয়ে একই private IPv4 Wi-Fi বা device-to-device traffic অনুমোদিত hotspot-এ রাখুন। QR নিজে Wi-Fi connection তৈরি করে না।
2. **গ্রহণকারী:** Home → Receive files → Start receiving। Local-network permission চাইলে পর্যালোচনা করে অনুমতি দিন।
3. একাধিক IP থাকলে সঠিক Wi-Fi address বাছুন। Receiver-এর QR শুধু যাঁকে পাঠাতে দেবেন তাঁকেই দেখান—QR-তে authentication secret আছে। Public post করবেন না।
4. **পাঠানো ফোন:** Select files → Files → Send selected → Scan receiver QR → Start camera। চাইলে camera permission দিন।
5. QR পাওয়ার পরে address/pin ও সতর্কতা দেখুন। **Use this code** code field পূরণ করে; তখনো file পাঠায় না।
6. Sender **Ask to send** চাপবেন। Receiver file list দেখে **Accept files** চাপবেন। Device name self-reported, তাই পরিচয়ের নিশ্চয়তা নয়।
7. Receiver-এর Saved and verified এবং sender-এর Delivery confirmed পর্যন্ত অপেক্ষা করুন। 100% upload final receipt নয়।

Camera না চাইলে **Use manual code instead** দিয়ে ফিরে paste করুন। Part 2-এর code একইভাবে কাজ করে। পুরোনো/expired QR format হিসেবে valid হতে পারে, কিন্তু receiver তা গ্রহণ নাও করবে; fresh receiving session-এর QR নিন। Android scanner-এর default bundled on-device barcode model configuration রাখা হয়েছে, unbundled first-use model download চালু করা হয়নি। এই app-এর scanner flow camera image save/upload করে না; SDK/store privacy review তবুও publishing-এর আগে বাকি।

## সংরক্ষিত file খুঁজুন ও আবার share করুন

1. চলতি receiving screen ছাড়তে হলে আগের Stop/leave confirmation ব্যবহার করুন। এরপর Home → **Saved files**।
2. এটি **received copies-এর ইতিহাস**; sent-history database নয়। Part 2-এর completed receipts সরাসরি পড়া হয়।
3. Batch খুললে filename, size, receipt SHA-256 ও বর্তমান availability দেখবেন। Search দিয়ে name/sender খুঁজতে পারবেন।
4. **Verify checksums** দিলে file stream করে SHA-256 পুনরায় পরীক্ষা হয়। Cancel করলে বা app background হলে check বন্ধ হয়; saved data মুছে যায় না।
5. **Share all copies** বা file-এর share icon সংশ্লিষ্ট copies যাচাই করে native share sheet খোলে। কোনো copy missing/changed হলে সেটি share করার আগে সমস্যা দেখানো হয়।
6. Share sheet বন্ধ হওয়া মানেই অন্য app file save করেছে এমন দাবি করা হয় না—নিজের chosen destination যাচাই করুন। Receive screen-এর আগের Share / save copies-ও রাখা হয়েছে।

Saved copies app Documents-এর `ShareBondhu/Received` folder-এ থাকে। History engine শুধু receiver-generated `received-` folders ও valid receipts পড়ে; `.incoming-` staging ignore করে। Serialized external path ব্যবহার করে না; unsafe links/receipts reject করে। Default scan cap: 250 shown batches, 2000 root entries inspected; সীমা এলে UI জানায়। কোনো archive delete হয় না।

Verification status বর্তমান screen/session-এর জন্য; disk-এ নতুন verified flag লেখা হয় না। File বা receipt পরে বদলাতে পারে। SHA-256 stored receipt-এর সঙ্গে তুলনা করে—receipt নিজে cryptographically signed নয়। Hostile local filesystem race/tampering-এর সম্পূর্ণ প্রতিরোধ বা independent security audit দাবি করা হয়নি। আলাদা at-rest encryption নেই। App uninstall/clear-data-এর আগে গুরুত্বপূর্ণ copies export করুন; OS backup policy প্রযোজ্য।

## আগের transfer সীমা একই

১–৫০টি file, প্রতিটি সর্বোচ্চ 2 GiB, batch-এ মোট 4 GiB। Invitation ১০ মিনিট, receiver approval ৬০ সেকেন্ড; transfer idle/overall deadlines আগের মতো। দুই app foreground-এ রাখুন। Auto-discovery/hotspot control, IPv6-only transfer, resumable/background transfer এবং বিজ্ঞাপন এখনো যোগ হয়নি। Cloud-only source file local করতে internet লাগতে পারে। Final commit-এর সময় cancellation হলে receipt দেখে ফল নিশ্চিত করুন; অনিশ্চিত অবস্থায় blind retry করবেন না।

## ফাইল নম্বর

| File | Path | Part 3 |
|---|---|---|
| 1 | `pubspec.yaml` | UPDATED |
| 2 | `lib/main.dart` | UNCHANGED |
| 3 | `lib/models/share_file.dart` | UNCHANGED |
| 4 | `lib/screens/home_screen.dart` | UPDATED |
| 5 | `test/widget_test.dart` | UPDATED; আগের 60টি test retained |
| 6 | `lib/models/transfer_models.dart` | UNCHANGED |
| 7 | `lib/services/local_transfer_service.dart` | UNCHANGED |
| 8 | `lib/screens/nearby_screen.dart` | UPDATED |
| 9 | `android/app/src/main/AndroidManifest.xml` | UPDATED; optional camera permission/feature |
| 10 | `ios/Runner/Info.plist` | UPDATED; camera usage description |
| 11 | `lib/models/saved_transfer.dart` | NEW |
| 12 | `lib/services/transfer_history_service.dart` | NEW |
| 13 | `lib/screens/history_screen.dart` | NEW |
| 14 | `lib/widgets/pairing_qr_card.dart` | NEW |
| 15 | `lib/screens/scan_pairing_screen.dart` | NEW |

`docs/PART_03_FULL_CODE.md`-এ নতুন File 11–15 এবং আগের File 1–10-এর পুরো বর্তমান কোড আছে। `docs/FILE_INVENTORY.txt`-এ ZIP-এর সব file, `docs/SHA256SUMS.txt`-এ checksum, এবং `docs/PART_03_TEST_RESULTS.txt`-এ verification output আছে। Historical Part 1/2 documents ও archive অপরিবর্তিত রাখা হয়েছে। Preview-তে test data এবং একটি QR component demo আছে; demo QR কোনো active receiver নয়।

ShareBondhu নাম ও `com.sharebondhu.sharebondhu` ID অস্থায়ী। Brand availability, final launcher icon, signing, privacy declaration, real-device QA ও store release preparation বাকি।


## নতুন File 11–15 — সম্পূর্ণ কোড

প্রতিটি code block সেই file-এর শুরু থেকে শেষ পর্যন্ত সম্পূর্ণ content। কোনো function বা implementation বাদ দিয়ে সংক্ষিপ্ত করা হয়নি। নতুন file নিজের project root-এর relative path-এ রাখুন। নিচের পরবর্তী বিভাগে পুরোনো File 1–10-এর পুরো বর্তমান সংস্করণও আছে। ZIP-এর প্রতিটি numbered file-এর সঙ্গে এই blocks byte-for-byte মিলিয়ে যাচাই করা হয়েছে।

### File 11 — `lib/models/saved_transfer.dart` — NEW

```dart
import 'dart:convert';

import 'transfer_models.dart';

class HistoryException extends TransferException {
  const HistoryException(super.message);
}

class HistoryCancelled extends HistoryException {
  const HistoryCancelled()
    : super('File checking canceled. Saved files are unchanged.');
}

class HistoryCancellation {
  bool _canceled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCanceled => _canceled;

  void throwIfCanceled() {
    if (_canceled) {
      throw const HistoryCancelled();
    }
  }

  void Function() onCancel(void Function() listener) {
    if (_canceled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_canceled) {
      return;
    }
    _canceled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // Cancellation must still reach the remaining owned operations.
      }
    }
  }
}

enum SavedFileStatus {
  available,
  verified,
  missing,
  sizeChanged,
  checksumMismatch,
  unsafe,
  unreadable,
}

class SavedFile {
  const SavedFile({
    required this.index,
    required this.receipt,
    required this.status,
    this.currentSize,
  });

  final int index;
  final ReceivedFile receipt;
  final SavedFileStatus status;
  final int? currentSize;

  String get storedName =>
      '${(index + 1).toString().padLeft(3, '0')}_${receipt.name}';

  bool get canCheck =>
      status == SavedFileStatus.available ||
      status == SavedFileStatus.verified ||
      status == SavedFileStatus.checksumMismatch;

  bool get hasIssue =>
      status != SavedFileStatus.available && status != SavedFileStatus.verified;

  String get statusLabel => switch (status) {
    SavedFileStatus.available => 'Size matches · not rechecked',
    SavedFileStatus.verified => 'Checksum verified this session',
    SavedFileStatus.missing => 'Saved copy is missing',
    SavedFileStatus.sizeChanged => 'File size changed',
    SavedFileStatus.checksumMismatch => 'Checksum does not match',
    SavedFileStatus.unsafe => 'Unsafe file reference blocked',
    SavedFileStatus.unreadable => 'File could not be read',
  };

  SavedFile withStatus(SavedFileStatus value, {int? size}) => SavedFile(
    index: index,
    receipt: receipt,
    status: value,
    currentSize: size ?? currentSize,
  );
}

class SavedTransfer {
  SavedTransfer({
    required this.folderName,
    required this.receipt,
    required this.manifestDigest,
    required Iterable<SavedFile> files,
    this.verifiedAt,
  }) : files = List<SavedFile>.unmodifiable(files) {
    if (!isReceivedFolderName(folderName) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestDigest)) {
      throw const HistoryException('Invalid saved-transfer reference.');
    }
  }

  final String folderName;
  final TransferReceipt receipt;
  final String manifestDigest;
  final List<SavedFile> files;
  final DateTime? verifiedAt;

  // Folder identity is receiver-generated. A sender can repeat a wire batch ID.
  String get id => folderName;
  int get totalBytes => receipt.totalBytes;
  bool get hasIssues => files.any((file) => file.hasIssue);
  bool get allVerified =>
      files.isNotEmpty &&
      files.every((file) => file.status == SavedFileStatus.verified);

  SavedTransfer withFiles(Iterable<SavedFile> updated, {DateTime? checkedAt}) =>
      SavedTransfer(
        folderName: folderName,
        receipt: receipt,
        manifestDigest: manifestDigest,
        files: updated,
        verifiedAt: checkedAt,
      );
}

class HistorySnapshot {
  HistorySnapshot({
    required Iterable<SavedTransfer> transfers,
    this.skippedEntries = 0,
    this.truncated = false,
  }) : transfers = List<SavedTransfer>.unmodifiable(transfers);

  final List<SavedTransfer> transfers;
  final int skippedEntries;
  final bool truncated;

  int get fileCount =>
      transfers.fold<int>(0, (count, batch) => count + batch.files.length);
  int get recordedBytes =>
      transfers.fold<int>(0, (count, batch) => count + batch.totalBytes);
}

class HistoryCheckProgress {
  const HistoryCheckProgress({
    required this.filesChecked,
    required this.totalFiles,
    required this.bytesChecked,
    required this.totalBytes,
    required this.fileName,
  });

  final int filesChecked;
  final int totalFiles;
  final int bytesChecked;
  final int totalBytes;
  final String fileName;

  double get fraction => totalBytes == 0
      ? (filesChecked == totalFiles ? 1 : 0)
      : (bytesChecked / totalBytes).clamp(0.0, 1.0);
}

class HistoryShareFile {
  const HistoryShareFile({required this.path, required this.name});

  final String path;
  final String name;
}

bool isReceivedFolderName(String value) =>
    RegExp(r'^received-[a-f0-9]{32}$').hasMatch(value);

TransferReceipt parseSavedReceipt(Map<String, dynamic> data) {
  try {
    final id = data['id'];
    final sender = data['senderName'];
    final completed = data['completedAt'];
    final entries = data['files'];
    if (data['version'] != TransferLimits.protocolVersion ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        sender is! String ||
        utf8.encode(sender).length > 80 ||
        completed is! String ||
        completed.length > 40 ||
        entries is! List ||
        entries.isEmpty ||
        entries.length > TransferLimits.maxFiles) {
      throw const FormatException();
    }
    final timestamp = DateTime.tryParse(completed);
    if (timestamp == null || !timestamp.isUtc) {
      throw const FormatException();
    }
    final ids = <String>{};
    var total = 0;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final name = entry['name'];
      final descriptor = OfferedFile.fromJson(entry);
      if (name is! String ||
          utf8.encode(name).length > TransferLimits.maxNameBytes ||
          safeFileName(name) != name ||
          !ids.add(descriptor.id)) {
        throw const FormatException();
      }
      total += descriptor.size;
      if (total > TransferLimits.maxBatchBytes) {
        throw const FormatException();
      }
    }
    // The v1 parser discards serialized localPath fields. Disk paths are derived
    // separately from the checked folder, list position and safe display name.
    return TransferReceipt.fromJson(data);
  } catch (_) {
    throw const HistoryException('A saved receipt is invalid or unsupported.');
  }
}
```

### File 12 — `lib/services/transfer_history_service.dart` — NEW

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/saved_transfer.dart';
import '../models/transfer_models.dart';

class TransferHistoryService {
  TransferHistoryService(
    this.storageRoot, {
    this.maxBatches = 250,
    this.maxDirectoryEntries = 2000,
    this.readTimeout = const Duration(seconds: 30),
  }) {
    if (maxBatches < 1 ||
        maxDirectoryEntries < 1 ||
        readTimeout <= Duration.zero) {
      throw ArgumentError('History limits and read timeout must be positive.');
    }
  }

  final Directory storageRoot;
  final int maxBatches;
  final int maxDirectoryEntries;
  final Duration readTimeout;

  static Directory rootForDocuments(Directory documents) =>
      Directory(p.join(documents.path, 'ShareBondhu', 'Received'));

  Future<HistorySnapshot> load({HistoryCancellation? cancellation}) async {
    final token = cancellation ?? HistoryCancellation();
    token.throwIfCanceled();
    final root = await _safeRoot();
    if (root == null) {
      return HistorySnapshot(transfers: const <SavedTransfer>[]);
    }
    final candidates = <({String name, DateTime modified})>[];
    var inspected = 0;
    var skipped = 0;
    var truncated = false;
    try {
      await for (final entity in Directory(root).list(followLinks: false)) {
        token.throwIfCanceled();
        inspected += 1;
        if (inspected > maxDirectoryEntries) {
          truncated = true;
          break;
        }
        final name = p.basename(entity.path);
        if (!isReceivedFolderName(name)) {
          continue;
        }
        if (entity is! Directory) {
          skipped += 1;
          continue;
        }
        try {
          final stat = await entity.stat();
          candidates.add((name: name, modified: stat.modified));
        } on FileSystemException {
          skipped += 1;
        }
      }
    } on FileSystemException {
      throw const HistoryException(
        'Saved-file storage could not be listed. Try again.',
      );
    }
    candidates.sort((a, b) {
      final byTime = b.modified.compareTo(a.modified);
      return byTime == 0 ? a.name.compareTo(b.name) : byTime;
    });
    final transfers = <SavedTransfer>[];
    for (var index = 0; index < candidates.length; index += 1) {
      token.throwIfCanceled();
      if (transfers.length >= maxBatches) {
        truncated = true;
        break;
      }
      try {
        transfers.add(await _loadFolder(candidates[index].name, token));
      } on HistoryCancelled {
        rethrow;
      } on HistoryException {
        skipped += 1;
      } on FileSystemException {
        skipped += 1;
      } on TimeoutException {
        skipped += 1;
      }
    }
    transfers.sort((a, b) {
      final byTime = b.receipt.completedAt.compareTo(a.receipt.completedAt);
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    });
    token.throwIfCanceled();
    return HistorySnapshot(
      transfers: transfers,
      skippedEntries: skipped,
      truncated: truncated,
    );
  }

  Future<SavedTransfer> verify(
    SavedTransfer transfer, {
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    final token = cancellation ?? HistoryCancellation();
    final fresh = await _reloadUnchanged(transfer, token);
    final indices = List<int>.generate(fresh.files.length, (index) => index);
    return _check(fresh, indices, token, onProgress);
  }

  Future<List<HistoryShareFile>> prepareShare(
    SavedTransfer transfer, {
    int? fileIndex,
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    final token = cancellation ?? HistoryCancellation();
    final fresh = await _reloadUnchanged(transfer, token);
    if (fileIndex != null &&
        (fileIndex < 0 || fileIndex >= fresh.files.length)) {
      throw const HistoryException(
        'That saved file is no longer in this batch.',
      );
    }
    final indices = fileIndex == null
        ? List<int>.generate(fresh.files.length, (index) => index)
        : <int>[fileIndex];
    final checked = await _check(fresh, indices, token, onProgress);
    if (indices.any(
      (index) => checked.files[index].status != SavedFileStatus.verified,
    )) {
      throw const HistoryException(
        'Some selected copies are missing, changed, or unreadable. '
        'Refresh and check the file details before sharing.',
      );
    }
    final directory = await _safeBatchDirectory(checked.folderName);
    final result = <HistoryShareFile>[];
    for (final index in indices) {
      token.throwIfCanceled();
      final file = checked.files[index];
      final probe = await _regularFile(directory, file.storedName);
      if (probe.stat.size != file.receipt.size) {
        throw const HistoryException(
          'A saved copy changed after checking. Try again.',
        );
      }
      result.add(HistoryShareFile(path: probe.path, name: file.receipt.name));
    }
    token.throwIfCanceled();
    return List<HistoryShareFile>.unmodifiable(result);
  }

  Future<SavedTransfer> _check(
    SavedTransfer fresh,
    List<int> indices,
    HistoryCancellation token,
    void Function(HistoryCheckProgress)? onProgress,
  ) async {
    final files = fresh.files.toList();
    final totalBytes = indices.fold<int>(
      0,
      (sum, index) => sum + files[index].receipt.size,
    );
    var bytesChecked = 0;
    var filesChecked = 0;
    for (final index in indices) {
      token.throwIfCanceled();
      final file = files[index];
      files[index] = await _checkFile(fresh.folderName, file, token, (count) {
        bytesChecked += count;
        onProgress?.call(
          HistoryCheckProgress(
            filesChecked: filesChecked,
            totalFiles: indices.length,
            bytesChecked: bytesChecked,
            totalBytes: totalBytes,
            fileName: file.receipt.name,
          ),
        );
      });
      filesChecked += 1;
      onProgress?.call(
        HistoryCheckProgress(
          filesChecked: filesChecked,
          totalFiles: indices.length,
          bytesChecked: bytesChecked,
          totalBytes: totalBytes,
          fileName: file.receipt.name,
        ),
      );
    }
    token.throwIfCanceled();
    // A receipt changed during checking is not silently accepted as a new truth.
    await _reloadUnchanged(fresh, token);
    return fresh.withFiles(files, checkedAt: DateTime.now().toUtc());
  }

  Future<SavedFile> _checkFile(
    String folder,
    SavedFile saved,
    HistoryCancellation token,
    void Function(int count) onBytes,
  ) async {
    token.throwIfCanceled();
    StreamIterator<List<int>>? iterator;
    void Function()? unlisten;
    ByteConversionSink? hashInput;
    var hashClosed = false;
    try {
      final directory = await _safeBatchDirectory(folder);
      final before = await _regularFile(directory, saved.storedName);
      if (before.stat.size != saved.receipt.size) {
        return saved.withStatus(
          SavedFileStatus.sizeChanged,
          size: before.stat.size,
        );
      }
      final output = _HistoryDigestOutput();
      hashInput = sha256.startChunkedConversion(output);
      final reader = StreamIterator<List<int>>(File(before.path).openRead());
      iterator = reader;
      unlisten = token.onCancel(() {
        unawaited(
          reader.cancel().then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {},
          ),
        );
      });
      var count = 0;
      while (await reader.moveNext().timeout(readTimeout)) {
        token.throwIfCanceled();
        final chunk = reader.current;
        count += chunk.length;
        if (count > saved.receipt.size) {
          return saved.withStatus(SavedFileStatus.sizeChanged, size: count);
        }
        hashInput.add(chunk);
        onBytes(chunk.length);
      }
      token.throwIfCanceled();
      hashInput.close();
      hashClosed = true;
      final afterDirectory = await _safeBatchDirectory(folder);
      final after = await _regularFile(afterDirectory, saved.storedName);
      if (count != saved.receipt.size ||
          after.stat.size != saved.receipt.size ||
          after.stat.modified != before.stat.modified ||
          !p.equals(after.path, before.path)) {
        return saved.withStatus(
          SavedFileStatus.sizeChanged,
          size: after.stat.size,
        );
      }
      final matches = secretEquals(
        output.value!.toString(),
        saved.receipt.digest,
      );
      return saved.withStatus(
        matches ? SavedFileStatus.verified : SavedFileStatus.checksumMismatch,
        size: count,
      );
    } on HistoryCancelled {
      rethrow;
    } on _FileProblem catch (problem) {
      return saved.withStatus(problem.status);
    } on FileSystemException {
      return saved.withStatus(SavedFileStatus.unreadable);
    } on TimeoutException {
      return saved.withStatus(SavedFileStatus.unreadable);
    } finally {
      unlisten?.call();
      if (iterator != null) {
        try {
          await iterator.cancel().timeout(readTimeout);
        } catch (_) {}
      }
      if (hashInput != null && !hashClosed) {
        hashInput.close();
      }
    }
  }

  Future<SavedTransfer> _reloadUnchanged(
    SavedTransfer transfer,
    HistoryCancellation token,
  ) async {
    final fresh = await _loadFolder(transfer.folderName, token);
    if (!secretEquals(fresh.manifestDigest, transfer.manifestDigest)) {
      throw const HistoryException(
        'The saved receipt changed. Refresh the list before continuing.',
      );
    }
    return fresh;
  }

  Future<SavedTransfer> _loadFolder(
    String name,
    HistoryCancellation token,
  ) async {
    token.throwIfCanceled();
    final directory = await _safeBatchDirectory(name);
    late Uint8List bytes;
    try {
      final probe = await _regularFile(directory, 'transfer.json');
      if (probe.stat.size > TransferLimits.maxMetadataBytes) {
        throw const HistoryException('A saved receipt is too large.');
      }
      bytes = await _readReceipt(probe.path, token);
      final after = await _regularFile(directory, 'transfer.json');
      if (after.stat.size != bytes.length ||
          after.stat.modified != probe.stat.modified) {
        throw const HistoryException(
          'The saved receipt changed while loading.',
        );
      }
    } on _FileProblem {
      throw const HistoryException('The saved receipt is missing or unsafe.');
    }
    token.throwIfCanceled();
    late TransferReceipt receipt;
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException();
      }
      receipt = parseSavedReceipt(data);
    } catch (_) {
      throw const HistoryException(
        'A saved receipt is invalid or unsupported.',
      );
    }
    final files = <SavedFile>[];
    for (var index = 0; index < receipt.files.length; index += 1) {
      token.throwIfCanceled();
      final file = SavedFile(
        index: index,
        receipt: receipt.files[index],
        status: SavedFileStatus.available,
      );
      try {
        final probe = await _regularFile(directory, file.storedName);
        files.add(
          file.withStatus(
            probe.stat.size == file.receipt.size
                ? SavedFileStatus.available
                : SavedFileStatus.sizeChanged,
            size: probe.stat.size,
          ),
        );
      } on _FileProblem catch (problem) {
        files.add(file.withStatus(problem.status));
      } on FileSystemException {
        files.add(file.withStatus(SavedFileStatus.unreadable));
      }
    }
    return SavedTransfer(
      folderName: name,
      receipt: receipt,
      manifestDigest: sha256.convert(bytes).toString(),
      files: files,
    );
  }

  Future<Uint8List> _readReceipt(String path, HistoryCancellation token) async {
    final reader = StreamIterator<List<int>>(File(path).openRead());
    final builder = BytesBuilder(copy: false);
    final clock = Stopwatch()..start();
    final unlisten = token.onCancel(() {
      unawaited(
        reader.cancel().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
    });
    try {
      while (true) {
        token.throwIfCanceled();
        final remaining = readTimeout - clock.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Receipt read deadline exceeded.');
        }
        if (!await reader.moveNext().timeout(remaining)) {
          break;
        }
        if (builder.length + reader.current.length >
            TransferLimits.maxMetadataBytes) {
          throw const HistoryException('A saved receipt is too large.');
        }
        builder.add(reader.current);
      }
      token.throwIfCanceled();
      return builder.takeBytes();
    } finally {
      unlisten();
      try {
        await reader.cancel().timeout(readTimeout);
      } catch (_) {}
    }
  }

  Future<String?> _safeRoot() async {
    final type = await FileSystemEntity.type(
      storageRoot.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    if (type != FileSystemEntityType.directory) {
      throw const HistoryException(
        'Saved-file storage is not a regular app directory.',
      );
    }
    final root = p.normalize(await storageRoot.resolveSymbolicLinks());
    if (p.equals(p.dirname(root), root)) {
      throw const HistoryException(
        'Refusing to inspect the filesystem root as app history.',
      );
    }
    return root;
  }

  Future<String> _safeBatchDirectory(String name) async {
    if (!isReceivedFolderName(name)) {
      throw const HistoryException('Invalid saved-transfer folder.');
    }
    final root = await _safeRoot();
    if (root == null) {
      throw const HistoryException(
        'Saved-file storage is no longer available.',
      );
    }
    final directory = p.join(root, name);
    if (await FileSystemEntity.type(directory, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const HistoryException('The saved batch is missing or is a link.');
    }
    final resolved = p.normalize(
      await Directory(directory).resolveSymbolicLinks(),
    );
    if (!p.equals(resolved, directory) ||
        !p.equals(p.dirname(resolved), root)) {
      throw const HistoryException('A saved batch points outside app storage.');
    }
    return resolved;
  }

  Future<({String path, FileStat stat})> _regularFile(
    String directory,
    String name,
  ) async {
    if (p.basename(name) != name || name == '.' || name == '..') {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(
          p.normalize(await Directory(directory).resolveSymbolicLinks()),
          directory,
        )) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final path = p.join(directory, name);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const _FileProblem(SavedFileStatus.missing);
    }
    if (type != FileSystemEntityType.file) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final resolved = p.normalize(await File(path).resolveSymbolicLinks());
    if (!p.equals(resolved, path) ||
        !p.equals(p.dirname(resolved), directory)) {
      throw const _FileProblem(SavedFileStatus.unsafe);
    }
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const _FileProblem(SavedFileStatus.unreadable);
    }
    return (path: resolved, stat: stat);
  }
}

class _HistoryDigestOutput implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _FileProblem implements Exception {
  const _FileProblem(this.status);

  final SavedFileStatus status;
}
```

### File 13 — `lib/screens/history_screen.dart` — NEW

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/saved_transfer.dart';
import '../models/share_file.dart';
import '../services/transfer_history_service.dart';

typedef HistoryShareAction = Future<void> Function(
  List<HistoryShareFile> files,
  Rect origin,
);

Future<void> shareSavedCopies(List<HistoryShareFile> files, Rect origin) async {
  await SharePlus.instance.share(
    ShareParams(
      files: files
          .map(
            (file) => XFile(
              file.path,
              name: file.name,
              mimeType: 'application/octet-stream',
            ),
          )
          .toList(),
      title: 'Files saved with ShareBondhu',
      sharePositionOrigin: origin,
    ),
  );
}

enum HistoryFilter { all, available, attention }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.service,
    this.documentsDirectory = getApplicationDocumentsDirectory,
    this.shareAction = shareSavedCopies,
  });

  final TransferHistoryService? service;
  final Future<Directory> Function() documentsDirectory;
  final HistoryShareAction shareAction;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  final TextEditingController _search = TextEditingController();
  final ScrollController _bodyScroll = ScrollController();
  TransferHistoryService? _service;
  HistorySnapshot? _snapshot;
  HistoryCancellation? _loadToken;
  HistoryCancellation? _operationToken;
  HistoryCheckProgress? _progress;
  HistoryFilter _filter = HistoryFilter.all;
  String _query = '';
  String? _activeBatch;
  String? _error;
  String? _feedback;
  bool _loading = true;
  bool _sharing = false;
  bool _disposing = false;
  int _loadGeneration = 0;
  int _operationGeneration = 0;

  bool get _canUpdate => mounted && !_disposing;
  bool get _busy => _activeBatch != null;

  List<SavedTransfer> get _visible {
    final entries = _snapshot?.transfers ?? const <SavedTransfer>[];
    return entries.where((batch) {
      if (_filter == HistoryFilter.available && batch.hasIssues) {
        return false;
      }
      if (_filter == HistoryFilter.attention && !batch.hasIssues) {
        return false;
      }
      return _query.isEmpty ||
          batch.receipt.senderName.toLowerCase().contains(_query) ||
          batch.files.any(
            (file) => file.receipt.name.toLowerCase().contains(_query),
          );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _loadToken?.cancel();
      _operationToken?.cancel();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _loadToken?.cancel();
    _operationToken?.cancel();
    _bodyScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_sharing) {
      return;
    }
    _loadToken?.cancel();
    _operationToken?.cancel();
    final generation = ++_loadGeneration;
    _operationGeneration += 1;
    final token = HistoryCancellation();
    _loadToken = token;
    if (_canUpdate) {
      setState(() {
        _loading = true;
        _activeBatch = null;
        _progress = null;
        _error = null;
        _feedback = null;
      });
    }
    try {
      if (_service == null) {
        final documents = await widget.documentsDirectory();
        token.throwIfCanceled();
        _service = TransferHistoryService(
          TransferHistoryService.rootForDocuments(documents),
        );
      }
      final snapshot = await _service!.load(cancellation: token);
      if (_canUpdate && generation == _loadGeneration && !token.isCanceled) {
        setState(() => _snapshot = snapshot);
      }
    } on HistoryCancelled {
      if (_canUpdate && generation == _loadGeneration) {
        setState(() => _feedback = 'Loading paused. Tap Refresh when ready.');
      }
    } on MissingPluginException {
      if (_canUpdate && generation == _loadGeneration) {
        setState(
          () => _error = 'Native storage support is missing. Run flutter pub get, stop the app, and rebuild it.',
        );
      }
    } catch (error) {
      if (_canUpdate && generation == _loadGeneration) {
        setState(
          () => _error = error is HistoryException
              ? error.message
              : 'Saved files could not be loaded. Try Refresh.',
        );
      }
    } finally {
      if (_canUpdate && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _replace(SavedTransfer updated) {
    final snapshot = _snapshot;
    if (!_canUpdate || snapshot == null) {
      return;
    }
    setState(() {
      _snapshot = HistorySnapshot(
        transfers: snapshot.transfers.map(
          (batch) => batch.id == updated.id ? updated : batch,
        ),
        skippedEntries: snapshot.skippedEntries,
        truncated: snapshot.truncated,
      );
    });
  }

  void _focusStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canUpdate && _bodyScroll.hasClients) {
        _bodyScroll.jumpTo(0);
      }
    });
  }

  Future<void> _verify(SavedTransfer transfer) async {
    final service = _service;
    if (service == null || _busy || _loading) {
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_operationGeneration;
    final token = HistoryCancellation();
    _operationToken = token;
    setState(() {
      _activeBatch = transfer.id;
      _progress = null;
      _error = null;
      _feedback = null;
    });
    _focusStatus();
    try {
      final checked = await service.verify(
        transfer,
        cancellation: token,
        onProgress: (progress) {
          if (_canUpdate && generation == _operationGeneration) {
            setState(() => _progress = progress);
          }
        },
      );
      token.throwIfCanceled();
      if (_canUpdate && generation == _operationGeneration) {
        _replace(checked);
        setState(
          () => _feedback = checked.allVerified
              ? 'Checksums match the stored receipt. This check is for the current session.'
              : 'Some files need attention. Open the batch to see each file status.',
        );
      }
    } catch (error) {
      if (_canUpdate && generation == _operationGeneration) {
        setState(
          () => _feedback = error is HistoryException
              ? error.message
              : 'The file check could not finish. Saved files are unchanged.',
        );
      }
    } finally {
      if (_canUpdate && generation == _operationGeneration) {
        setState(() {
          _activeBatch = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _share(
    SavedTransfer transfer,
    BuildContext buttonContext, {
    int? fileIndex,
  }) async {
    final service = _service;
    if (service == null || _busy || _loading) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero) & box.size;
    FocusScope.of(context).unfocus();
    final generation = ++_operationGeneration;
    final token = HistoryCancellation();
    _operationToken = token;
    setState(() {
      _activeBatch = transfer.id;
      _progress = null;
      _error = null;
      _feedback =
          'Checking the selected copies before opening the share sheet.';
    });
    _focusStatus();
    try {
      final files = await service.prepareShare(
        transfer,
        fileIndex: fileIndex,
        cancellation: token,
        onProgress: (progress) {
          if (_canUpdate && generation == _operationGeneration) {
            setState(() => _progress = progress);
          }
        },
      );
      token.throwIfCanceled();
      if (!_canUpdate || generation != _operationGeneration) {
        return;
      }
      final checkedFiles = transfer.files.map((file) {
        return fileIndex == null || file.index == fileIndex
            ? file.withStatus(SavedFileStatus.verified)
            : file;
      });
      _replace(
        transfer.withFiles(checkedFiles, checkedAt: DateTime.now().toUtc()),
      );
      setState(() => _sharing = true);
      await widget.shareAction(files, origin);
      if (_canUpdate && generation == _operationGeneration) {
        setState(
          () => _feedback = 'Share sheet closed. Check the destination to confirm exported copies. Your saved originals remain in app storage.',
        );
      }
    } catch (error) {
      if (_canUpdate && generation == _operationGeneration) {
        setState(
          () => _feedback = error is HistoryException
              ? error.message
              : 'The share sheet could not open. No saved files were removed.',
        );
      }
    } finally {
      if (_canUpdate && generation == _operationGeneration) {
        setState(() {
          _activeBatch = null;
          _progress = null;
          _sharing = false;
        });
      }
    }
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _query = '';
      _filter = HistoryFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    return Scaffold(
      key: const ValueKey('history-scaffold'),
      appBar: AppBar(
        title: const Text('Saved files'),
        toolbarHeight: 70,
        actions: <Widget>[
          IconButton(
            key: const ValueKey('refresh-history-button'),
            tooltip: 'Refresh saved files',
            onPressed: _loading || _sharing ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                controller: _bodyScroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  _buildSummary(theme),
                  const SizedBox(height: 18),
                  TextField(
                    key: const ValueKey('history-search-field'),
                    controller: _search,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search filename or sender',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _filterChip('All', HistoryFilter.all),
                      _filterChip('Available', HistoryFilter.available),
                      _filterChip('Needs attention', HistoryFilter.attention),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const LinearProgressIndicator(
                      key: ValueKey('history-loading'),
                    ),
                  if (_error != null)
                    _HistoryNotice(message: _error!, isError: true),
                  if (_feedback != null) _HistoryNotice(message: _feedback!),
                  if (_snapshot != null && _snapshot!.skippedEntries > 0)
                    _HistoryNotice(
                      message:
                          '${_snapshot!.skippedEntries} receipt entries could not be loaded. They were not changed or deleted.',
                    ),
                  if (_snapshot?.truncated ?? false)
                    const _HistoryNotice(
                      message: 'The bounded history scan reached its limit. Not every archived batch may be shown. No data was removed.',
                    ),
                  if (_busy) _buildOperation(theme),
                  if (!_loading && _error == null && visible.isEmpty)
                    _buildEmpty(theme),
                  Column(
                    children: visible
                        .map((batch) => _buildBatch(theme, batch))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Received copies only. Part 2 and later receipts are read from this app\'s documents. '
                    'Availability checks size, not content. Verify checksums to recheck file contents. '
                    'This screen never deletes files or rewrites receipts; export important copies before uninstalling.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, HistoryFilter value) => FilterChip(
    key: ValueKey('history-filter-${value.name}'),
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
  );

  Widget _buildSummary(ThemeData theme) {
    final snapshot = _snapshot;
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
                Icons.inventory_2_outlined,
                color: Color(0xFFD5F391),
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'YOUR RECEIVED COPIES',
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
            'Find it again.\nKeep it with you.',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            snapshot == null
                ? 'Reading saved receipts from this device.'
                : '${snapshot.transfers.length} batches · ${snapshot.fileCount} recorded files · ${formatBytes(snapshot.recordedBytes)}',
            key: const ValueKey('history-summary'),
            style: const TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final hasEntries = _snapshot?.transfers.isNotEmpty ?? false;
    return Container(
      key: const ValueKey('history-empty-state'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            hasEntries ? Icons.search_off_rounded : Icons.folder_open_rounded,
            size: 44,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            hasEntries ? 'No matching saved files' : 'No received files yet',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hasEntries ? 'Try another search or filter.' : 'Complete a receiving session. Its saved files and receipt will appear here, including transfers from Part 2.',
            textAlign: TextAlign.center,
          ),
          if (hasEntries)
            TextButton(
              onPressed: _clearSearch,
              child: const Text('Clear search and filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildOperation(ThemeData theme) {
    final progress = _progress;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _sharing ? 'System share sheet' : 'Checking saved bytes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                progress.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress?.fraction),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${formatBytes(progress.bytesChecked)} / ${formatBytes(progress.totalBytes)} · ${progress.filesChecked} / ${progress.totalFiles} files',
              ),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('cancel-history-check-button'),
            onPressed: _sharing ? null : () => _operationToken?.cancel(),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel check'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatch(ThemeData theme, SavedTransfer batch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey('history-batch-${batch.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        leading: Icon(
          batch.allVerified
              ? Icons.verified_outlined
              : batch.hasIssues
              ? Icons.folder_off_outlined
              : Icons.folder_copy_outlined,
          color: batch.hasIssues
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
        title: Text(
          batch.receipt.senderName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${batch.files.length} ${batch.files.length == 1 ? 'file' : 'files'} · ${formatBytes(batch.totalBytes)}\n${_timestamp(batch.receipt.completedAt)}',
        ),
        children: <Widget>[
          Text(
            'Receipt recorded at transfer time. Only an explicit check below rechecks today\'s file bytes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: batch.files
                .map((file) => _buildFile(theme, batch, file))
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                key: ValueKey('verify-history-${batch.id}'),
                onPressed: _busy || _loading ? null : () => _verify(batch),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Verify checksums'),
              ),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  key: ValueKey('share-history-${batch.id}'),
                  onPressed: _busy || _loading || batch.hasIssues
                      ? null
                      : () => _share(batch, buttonContext),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share all copies'),
                ),
              ),
            ],
          ),
          if (batch.hasIssues)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Some copies need attention. Individual available files can still be checked and shared.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFile(ThemeData theme, SavedTransfer batch, SavedFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  file.receipt.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Builder(
                builder: (buttonContext) => IconButton(
                  key: ValueKey('share-history-file-${batch.id}-${file.index}'),
                  tooltip: 'Check and share this saved copy',
                  onPressed: _busy || _loading || file.hasIssue
                      ? null
                      : () =>
                            _share(batch, buttonContext, fileIndex: file.index),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                ),
              ),
            ],
          ),
          Text(
            '${formatBytes(file.receipt.size)} · ${file.statusLabel}',
            key: ValueKey('history-file-status-${batch.id}-${file.index}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: file.hasIssue
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text('Receipt SHA-256', style: theme.textTheme.labelSmall),
          SelectableText(
            key: PageStorageKey('history-hash-${batch.id}-${file.index}'),
            file.receipt.digest,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _timestamp(DateTime input) {
    final date = input.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
        ),
      ),
    );
  }
}
```

### File 14 — `lib/widgets/pairing_qr_card.dart` — NEW

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/transfer_models.dart';

class PairingQrCard extends StatefulWidget {
  const PairingQrCard({
    super.key,
    required this.code,
    required this.expiresAt,
    this.clock = DateTime.now,
  });

  final PairingCode code;
  final DateTime expiresAt;
  final DateTime Function() clock;

  @override
  State<PairingQrCard> createState() => _PairingQrCardState();
}

class _PairingQrCardState extends State<PairingQrCard> {
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _synchronize();
  }

  @override
  void didUpdateWidget(PairingQrCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  void _synchronize() {
    _remaining = widget.expiresAt.difference(widget.clock()).inSeconds;
    _timer?.cancel();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        final next = widget.expiresAt.difference(widget.clock()).inSeconds;
        if (next != _remaining) {
          setState(() => _remaining = next);
        }
        if (next <= 0) {
          _timer?.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _remaining > 0;
    final time =
        '${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}';
    return Container(
      key: const ValueKey('pairing-qr-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            active ? 'Let the sender scan this' : 'This invitation expired',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (active)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(260.0, constraints.maxWidth);
                return Center(
                  child: RepaintBoundary(
                    key: const ValueKey('pairing-qr-image-boundary'),
                    child: QrImageView(
                      key: const ValueKey('pairing-qr-image'),
                      data: widget.code.encode(),
                      size: size,
                      padding: const EdgeInsets.all(24),
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      semanticsLabel:
                          'Private ShareBondhu receiver pairing QR code',
                      errorStateBuilder: (context, error) => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'QR display is unavailable. Use Copy code below.',
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Icon(
                Icons.timer_off_outlined,
                size: 44,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            active
                ? 'New requests allowed for $time'
                : 'Stop receiving, then start a new session for a fresh QR.',
            key: const ValueKey('pairing-qr-expiry'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This QR contains the same private SB1 code as Copy code. '
            'Show it only to your intended sender. You still approve each batch.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
```

### File 15 — `lib/screens/scan_pairing_screen.dart` — NEW

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/transfer_models.dart';

class PairingCameraException implements Exception {
  const PairingCameraException(this.message);

  final String message;
}

abstract class PairingCamera {
  Stream<String> get codes;
  bool get isRunning;
  bool get hasPermission;
  bool get canToggleTorch;
  bool get torchIsOn;
  Widget buildPreview(BuildContext context);
  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  Future<void> dispose();
}

PairingCamera createPairingCamera() => MobilePairingCamera();

PairingCameraException cameraFailure(Object error) {
  if (error is PairingCameraException) {
    return error;
  }
  if (error is MobileScannerException) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => const PairingCameraException(
        'Camera access was not allowed. Review ShareBondhu camera permission '
        'in device Settings, or use the manual code.',
      ),
      MobileScannerErrorCode.unsupported => const PairingCameraException(
        'No supported camera is available. Use the manual pairing code instead.',
      ),
      _ => const PairingCameraException(
        'The camera could not start. Try again, or use the manual code.',
      ),
    };
  }
  return const PairingCameraException(
    'The camera is unavailable. Rebuild the app or use the manual code.',
  );
}

class MobilePairingCamera implements PairingCamera {
  MobilePairingCamera() {
    _subscription = _controller.barcodes.listen(
      (capture) {
        if (_disposed) {
          return;
        }
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null) {
            _codes.add(raw);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_disposed) {
          _codes.addError(cameraFailure(error));
        }
      },
    );
  }

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 300,
    returnImage: false,
  );
  final StreamController<String> _codes = StreamController<String>.broadcast(
    sync: true,
  );
  late final StreamSubscription<BarcodeCapture> _subscription;
  Future<void>? _starting;
  Future<void>? _disposing;
  bool _disposed = false;

  @override
  Stream<String> get codes => _codes.stream;
  @override
  bool get isRunning => !_disposed && _controller.value.isRunning;
  @override
  bool get hasPermission => !_disposed && _controller.value.hasCameraPermission;
  @override
  bool get canToggleTorch =>
      !_disposed && _controller.value.torchState != TorchState.unavailable;
  @override
  bool get torchIsOn =>
      !_disposed && _controller.value.torchState == TorchState.on;

  @override
  Widget buildPreview(BuildContext context) => MobileScanner(
    controller: _controller,
    useAppLifecycleState: false,
    tapToFocus: true,
    placeholderBuilder: (context) => const ColoredBox(color: Color(0xFF10291F)),
    errorBuilder: (context, error) => ColoredBox(
      color: const Color(0xFF10291F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            cameraFailure(error).message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  @override
  Future<void> start() async {
    if (_disposed) {
      throw const PairingCameraException('This camera session is closed.');
    }
    if (_starting != null) {
      await _starting;
      return;
    }
    final operation = _controller.start();
    _starting = operation;
    try {
      await operation;
      if (_disposed) {
        return;
      }
      final error = _controller.value.error;
      if (error != null || !_controller.value.isRunning) {
        throw cameraFailure(
          error ??
              const PairingCameraException(
                'The camera did not become ready. Try again.',
              ),
        );
      }
    } catch (error) {
      throw cameraFailure(error);
    } finally {
      _starting = null;
    }
  }

  @override
  Future<void> stop() async {
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    if (!_disposed) {
      await _controller.stop();
    }
  }

  @override
  Future<void> toggleTorch() async {
    if (isRunning && canToggleTorch) {
      await _controller.toggleTorch();
    }
  }

  @override
  Future<void> dispose() => _disposing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    await _subscription.cancel();
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    try {
      await _controller.dispose();
    } finally {
      await _codes.close();
    }
  }
}

Future<String?> scanReceiverCode(BuildContext context) => Navigator.of(context)
    .push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const ScanPairingScreen(),
      ),
    );

class ScanPairingScreen extends StatefulWidget {
  const ScanPairingScreen({
    super.key,
    this.cameraFactory = createPairingCamera,
  });

  final PairingCamera Function() cameraFactory;

  @override
  State<ScanPairingScreen> createState() => _ScanPairingScreenState();
}

class _ScanPairingScreenState extends State<ScanPairingScreen>
    with WidgetsBindingObserver {
  late final PairingCamera _camera;
  late final StreamSubscription<String> _subscription;
  PairingCode? _candidate;
  String? _error;
  String? _notice;
  bool _starting = false;
  bool _stopping = false;
  bool _running = false;
  bool _wantRunning = false;
  bool _foreground = true;
  bool _disposing = false;
  bool _accepting = false;

  bool get _canUpdate => mounted && !_disposing;

  @override
  void initState() {
    super.initState();
    _camera = widget.cameraFactory();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
    _subscription = _camera.codes.listen(
      _detected,
      onError: (Object error, StackTrace stack) {
        if (_canUpdate) {
          setState(() => _error = cameraFailure(error).message);
          unawaited(_stopCamera());
        }
      },
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Restart is explicit. Returning to the app does not turn on the camera.
      return;
    }
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (background) {
      _foreground = false;
    }
    if (background ||
        (state == AppLifecycleState.inactive &&
            _running &&
            _camera.hasPermission)) {
      _wantRunning = false;
      if (_canUpdate) {
        setState(
          () => _notice = 'Camera paused. Tap Start camera when you are ready.',
        );
      }
      unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _wantRunning = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    unawaited(
      _camera.dispose().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_starting ||
        _stopping ||
        _running ||
        _candidate != null ||
        !_foreground) {
      return;
    }
    _wantRunning = true;
    setState(() {
      _starting = true;
      _error = null;
      _notice = null;
    });
    try {
      await _camera.start();
      if (!_canUpdate || !_foreground || !_wantRunning) {
        await _camera.stop();
        return;
      }
      setState(() => _running = _camera.isRunning);
    } catch (error) {
      if (_canUpdate && _foreground && _wantRunning) {
        setState(() => _error = cameraFailure(error).message);
      }
    } finally {
      if (_canUpdate) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopCamera() async {
    _wantRunning = false;
    if (_stopping) {
      return;
    }
    if (_canUpdate) {
      setState(() {
        _stopping = true;
        _running = false;
      });
    }
    try {
      await _camera.stop();
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _notice =
              'Close this screen if the camera does not stop normally.',
        );
      }
    } finally {
      if (_canUpdate) {
        setState(() => _stopping = false);
      }
    }
  }

  void _detected(String value) {
    if (!_canUpdate ||
        !_foreground ||
        !_wantRunning ||
        _candidate != null ||
        _accepting) {
      return;
    }
    PairingCode parsed;
    try {
      parsed = PairingCode.parse(value);
    } on TransferException {
      const message =
          'Not a supported ShareBondhu receiver code. URLs and other QR content are ignored.';
      if (_error != message) {
        setState(() => _error = message);
      }
      return;
    }
    _wantRunning = false;
    setState(() {
      _candidate = parsed;
      _error = null;
      _notice = null;
    });
    unawaited(_stopCamera());
  }

  Future<void> _accept() async {
    final code = _candidate;
    if (code == null || _accepting || !_foreground) {
      return;
    }
    setState(() => _accepting = true);
    await _stopCamera();
    if (mounted && !_disposing && _foreground) {
      Navigator.of(context).pop(code.encode());
    } else if (_canUpdate) {
      setState(() => _accepting = false);
    }
  }

  Future<void> _scanAgain() async {
    await _stopCamera();
    if (_canUpdate) {
      setState(() {
        _candidate = null;
        _error = null;
      });
      await _startCamera();
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _camera.toggleTorch();
      if (_canUpdate) {
        setState(() {});
      }
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _notice = 'The flashlight is unavailable on this device.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = _candidate;
    return Scaffold(
      key: const ValueKey('scan-pairing-scaffold'),
      appBar: AppBar(title: const Text('Scan receiver QR'), toolbarHeight: 70),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: <Widget>[
                Text(
                  'Point. Check. Connect.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Scan the QR shown inside ShareBondhu on the receiving phone. '
                  'Both phones must still use the same private Wi-Fi or hotspot.',
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 1.15,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _camera.buildPreview(context),
                        if (!_running)
                          ColoredBox(
                            color: const Color(0xFF10291F),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    candidate == null
                                        ? Icons.qr_code_scanner_rounded
                                        : Icons.qr_code_rounded,
                                    color: const Color(0xFFD5F391),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    candidate == null
                                        ? 'Camera is off'
                                        : 'Code captured · camera stopped',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_running)
                          IgnorePointer(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.72,
                                heightFactor: 0.72,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFD5F391),
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) _ScannerNote(message: _error!, error: true),
                if (_notice != null) _ScannerNote(message: _notice!),
                if (candidate == null)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        key: const ValueKey('start-camera-button'),
                        onPressed: _starting || _stopping || _running
                            ? null
                            : _startCamera,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _starting ? 'Starting camera' : 'Start camera',
                        ),
                      ),
                      if (_running)
                        OutlinedButton(
                          key: const ValueKey('pause-camera-button'),
                          onPressed: _stopCamera,
                          child: const Text('Pause'),
                        ),
                      if (_running && _camera.canToggleTorch)
                        OutlinedButton.icon(
                          key: const ValueKey('camera-torch-button'),
                          onPressed: _toggleTorch,
                          icon: Icon(
                            _camera.torchIsOn
                                ? Icons.flash_off_rounded
                                : Icons.flash_on_rounded,
                          ),
                          label: Text(
                            _camera.torchIsOn ? 'Light off' : 'Light on',
                          ),
                        ),
                    ],
                  )
                else
                  Container(
                    key: const ValueKey('scanned-code-confirmation'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Pairing code found',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Receiver: ${candidate.host}:${candidate.port}'),
                        const SizedBox(height: 8),
                        const Text(
                          'The format is valid; a connection has not been verified yet. '
                          'Confirm this is the device you intend to use. Expired codes may still scan.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Certificate SHA-256',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          candidate.fingerprint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            FilledButton(
                              key: const ValueKey('use-scanned-code-button'),
                              onPressed: _accepting || _stopping
                                  ? null
                                  : _accept,
                              child: const Text('Use this code'),
                            ),
                            OutlinedButton(
                              key: const ValueKey('scan-again-button'),
                              onPressed: _accepting || _stopping
                                  ? null
                                  : _scanAgain,
                              child: const Text('Scan again'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const ValueKey('manual-pairing-fallback-button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Use manual code instead'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Camera access is optional. This screen does not send files, open scanned links, '
                  'save camera images, or approve transfers. You still tap Ask to send afterwards.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerNote extends StatelessWidget {
  const _ScannerNote({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? colors.onErrorContainer : colors.onSurface,
        ),
      ),
    );
  }
}
```


## আগের File 1–10 — সম্পূর্ণ বর্তমান সংস্করণ

File 1, 4, 5, 8, 9, 10 আপডেট হয়েছে। File 2, 3, 6, 7 Part 2-এর সঙ্গে byte-identical; তবুও পুরো file এখানে দেওয়া হলো। নিজের কোনো অতিরিক্ত edit থাকলে আগে backup/diff করবেন। UPDATED file-এর শুধু snippet নয়, সম্পূর্ণ সঠিক version বসাবেন।

### File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.3.0+3

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
  qr_flutter: 4.1.0
  mobile_scanner: 7.4.0
  path: 1.9.1

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
import 'history_screen.dart';

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

Widget buildDefaultHistoryScreen(BuildContext context) => const HistoryScreen();

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.pickFiles,
    required this.onToggleTheme,
    this.historyScreenBuilder = buildDefaultHistoryScreen,
  });

  final PickShareFiles pickFiles;
  final VoidCallback onToggleTheme;
  final WidgetBuilder historyScreenBuilder;

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

  Future<void> _openHistory() async {
    if (_isPicking) {
      return;
    }
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: widget.historyScreenBuilder));
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
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('saved-files-button'),
          onPressed: _isPicking ? null : _openHistory,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Saved files'),
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
                      'PART 03 · QR & SAVED FILES',
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
                'QR pairing and a saved-file browser are now added. '
                'Manual pairing, receiver approval and TLS transfers still work as before.',
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
              'Start receiving and let the sender scan your QR. The same full SB1 '
              'code can still be copied manually on a private Wi-Fi or hotspot.',
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
              'Open Saved files to find received batches, recheck SHA-256, '
              'and share copies again. Nothing is deleted by the history browser.',
          status: 'READY',
          isReady: true,
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
import 'package:sharebondhu/models/saved_transfer.dart';
import 'package:sharebondhu/services/transfer_history_service.dart';
import 'package:sharebondhu/screens/history_screen.dart';
import 'package:sharebondhu/screens/home_screen.dart';
import 'package:sharebondhu/screens/scan_pairing_screen.dart';
import 'package:sharebondhu/widgets/pairing_qr_card.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  registerPart3Tests();
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

class HistoryDiskFixture {
  const HistoryDiskFixture(this.directory, this.receipt);
  final Directory directory;
  final TransferReceipt receipt;
  File get manifest => File('${directory.path}/transfer.json');
  File fileAt(int index) => File(
    '${directory.path}/${(index + 1).toString().padLeft(3, '0')}_${receipt.files[index].name}',
  );
}

Future<HistoryDiskFixture> writeHistoryDiskFixture(
  Directory root, {
  String? wireId,
  String sender = 'Test sender',
  DateTime? date,
  List<(String, List<int>)> payloads = const <(String, List<int>)>[
    ('notes.txt', <int>[1, 2, 3]),
  ],
}) async {
  final directory = await Directory(
    '${root.path}/received-${randomTransferId()}',
  ).create(recursive: true);
  final files = <ReceivedFile>[];
  for (var i = 0; i < payloads.length; i += 1) {
    final (name, bytes) = payloads[i];
    files.add(
      ReceivedFile(
        id: randomTransferId(),
        name: name,
        size: bytes.length,
        digest: sha256.convert(bytes).toString(),
      ),
    );
    await File('${directory.path}/${(i + 1).toString().padLeft(3, '0')}_$name')
        .writeAsBytes(bytes, flush: true);
  }
  final receipt = TransferReceipt(
    id: wireId ?? randomTransferId(),
    senderName: sender,
    completedAt: date ?? DateTime.utc(2026, 9, 6, 12),
    files: files,
  );
  final fixture = HistoryDiskFixture(directory, receipt);
  await fixture.manifest.writeAsString(
    jsonEncode(receipt.toJson()),
    flush: true,
  );
  return fixture;
}

Future<Directory> historyTestRoot() async {
  final root = await Directory.systemTemp.createTemp(
    'sharebondhu-history-test-',
  );
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  return root;
}

SavedTransfer savedUiFixture({
  String sender = 'Ayesha',
  String name = 'weekend.jpg',
  SavedFileStatus status = SavedFileStatus.available,
}) {
  final record = ReceivedFile(
    id: randomTransferId(),
    name: name,
    size: 3,
    digest: sha256.convert(<int>[1, 2, 3]).toString(),
  );
  return SavedTransfer(
    folderName: 'received-${randomTransferId()}',
    receipt: TransferReceipt(
      id: randomTransferId(),
      senderName: sender,
      completedAt: DateTime.utc(2026, 9, 6, 12),
      files: <ReceivedFile>[record],
    ),
    manifestDigest: sha256.convert(utf8.encode(sender + name)).toString(),
    files: <SavedFile>[
      SavedFile(
        index: 0,
        receipt: record,
        status: status,
        currentSize: status == SavedFileStatus.missing ? null : 3,
      ),
    ],
  );
}

class FakeHistoryService extends TransferHistoryService {
  FakeHistoryService(this.snapshot) : super(Directory('/unused-history-test'));
  HistorySnapshot snapshot;
  int verifies = 0;
  int preparations = 0;
  Completer<HistorySnapshot>? pendingLoad;
  Completer<void>? pendingPreparation;

  @override
  Future<HistorySnapshot> load({HistoryCancellation? cancellation}) async {
    final result = pendingLoad == null ? snapshot : await pendingLoad!.future;
    cancellation?.throwIfCanceled();
    return result;
  }

  @override
  Future<SavedTransfer> verify(
    SavedTransfer transfer, {
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    verifies += 1;
    cancellation?.throwIfCanceled();
    return transfer.withFiles(
      transfer.files.map((file) => file.withStatus(SavedFileStatus.verified)),
      checkedAt: DateTime.utc(2026, 9, 6),
    );
  }

  @override
  Future<List<HistoryShareFile>> prepareShare(
    SavedTransfer transfer, {
    int? fileIndex,
    HistoryCancellation? cancellation,
    void Function(HistoryCheckProgress)? onProgress,
  }) async {
    preparations += 1;
    if (pendingPreparation != null) await pendingPreparation!.future;
    cancellation?.throwIfCanceled();
    return <HistoryShareFile>[
      HistoryShareFile(
        path: '/unused-history-test/verified.txt',
        name: transfer.files.first.receipt.name,
      ),
    ];
  }
}

class FakePairingCamera implements PairingCamera {
  final StreamController<String> events = StreamController<String>.broadcast(
    sync: true,
  );
  Completer<void>? pendingStart;
  Object? startError;
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  bool running = false;
  bool closed = false;
  bool light = false;

  @override
  Stream<String> get codes => events.stream;
  @override
  bool get isRunning => running && !closed;
  @override
  bool get hasPermission => running;
  @override
  bool get canToggleTorch => true;
  @override
  bool get torchIsOn => light;
  @override
  Widget buildPreview(BuildContext context) =>
      const ColoredBox(color: Color(0xFF10291F));
  @override
  Future<void> start() async {
    starts += 1;
    if (pendingStart != null) await pendingStart!.future;
    if (startError != null) throw startError!;
    if (!closed) running = true;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    if (pendingStart != null) await pendingStart!.future;
    running = false;
  }

  @override
  Future<void> toggleTorch() async => light = !light;
  @override
  Future<void> dispose() async {
    disposals += 1;
    closed = true;
    running = false;
    await events.close();
  }
}

PairingCode qrTestCode({String host = '192.168.4.1'}) => PairingCode(
  host: host,
  port: 43000,
  token: randomToken(),
  fingerprint: List<String>.filled(64, 'a').join(),
);

Future<void> tapVisibleKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> mountHistory(
  WidgetTester tester,
  FakeHistoryService service, {
  HistoryShareAction? shareAction,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: HistoryScreen(
        service: service,
        shareAction: shareAction ?? (files, origin) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openFakeScanner(
  WidgetTester tester,
  FakePairingCamera camera, {
  void Function(String?)? result,
  Size size = const Size(390, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-test-scanner'),
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (context) =>
                        ScanPairingScreen(cameraFactory: () => camera),
                  ),
                );
                result?.call(code);
              },
              child: const Text('Open scanner'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tapVisibleKey(tester, const ValueKey('open-test-scanner'));
}

void registerPart3Tests() {
  group('Part 3 saved receipt models', () {
    test(
      'strict receipts reject traversal, duplicate IDs and non-UTC timestamps',
      () {
        final fixture = savedUiFixture();
        final original = fixture.receipt.toJson();
        final badName =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        (badName['files'] as List).first['name'] = '../outside.txt';
        expect(
          () => parseSavedReceipt(badName),
          throwsA(isA<HistoryException>()),
        );
        final duplicate =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        (duplicate['files'] as List).add((duplicate['files'] as List).first);
        expect(
          () => parseSavedReceipt(duplicate),
          throwsA(isA<HistoryException>()),
        );
        final noZone = Map<String, dynamic>.from(original)
          ..['completedAt'] = '2026-09-06T12:00:00';
        expect(
          () => parseSavedReceipt(noZone),
          throwsA(isA<HistoryException>()),
        );
        final invalidId = Map<String, dynamic>.from(original)
          ..['id'] = '../../path';
        expect(
          () => parseSavedReceipt(invalidId),
          throwsA(isA<HistoryException>()),
        );
      },
    );

    test(
      'history identity and status do not imply current checksum verification',
      () {
        final fixture = savedUiFixture();
        expect(fixture.id, fixture.folderName);
        expect(fixture.id, isNot(fixture.receipt.id));
        expect(fixture.allVerified, isFalse);
        expect(fixture.files.single.statusLabel, contains('not rechecked'));
        expect(fixture.files.single.storedName, '001_weekend.jpg');
        expect(() => fixture.files.clear(), throwsUnsupportedError);
      },
    );

    test(
      'history cancellation notifies once and supports listener removal',
      () {
        final token = HistoryCancellation();
        var calls = 0;
        final remove = token.onCancel(() => calls += 10);
        remove();
        token.onCancel(() => calls += 1);
        token.cancel();
        token.cancel();
        expect(calls, 1);
        expect(token.throwIfCanceled, throwsA(isA<HistoryCancelled>()));
        token.onCancel(() => calls += 2);
        expect(calls, 3);
      },
    );
  });

  group('Part 3 real saved-file storage', () {
    test(
      'missing history is empty and does not create the received directory',
      () async {
        final root = await historyTestRoot();
        final missing = Directory('${root.path}/not-created');
        final result = await TransferHistoryService(missing).load();
        expect(result.transfers, isEmpty);
        expect(await missing.exists(), isFalse);
      },
    );

    test(
      'loads legacy v1 receipts and streams checks without rewriting anything',
      () async {
        final root = await historyTestRoot();
        final fixture = await writeHistoryDiskFixture(
          root,
          payloads: <(String, List<int>)>[
            ('notes.txt', List<int>.generate(131073, (index) => index % 251)),
            ('empty.txt', <int>[]),
          ],
        );
        final original = await fixture.manifest.readAsBytes();
        final service = TransferHistoryService(root);
        final saved = (await service.load()).transfers.single;
        expect(saved.allVerified, isFalse);
        final checked = await service.verify(saved);
        expect(checked.allVerified, isTrue);
        expect(checked.files[1].currentSize, 0);
        final share = await service.prepareShare(saved);
        expect(share, hasLength(2));
        expect(share.first.path, fixture.fileAt(0).path);
        expect(await fixture.manifest.readAsBytes(), original);
        expect(await fixture.fileAt(0).length(), 131073);
      },
    );

    test(
      'repeated wire IDs and duplicate names keep separate saved identities',
      () async {
        final root = await historyTestRoot();
        final id = randomTransferId();
        await writeHistoryDiskFixture(
          root,
          wireId: id,
          payloads: const <(String, List<int>)>[
            ('same.txt', <int>[1]),
            ('same.txt', <int>[2]),
          ],
        );
        await writeHistoryDiskFixture(root, wireId: id);
        final service = TransferHistoryService(root);
        final batches = (await service.load()).transfers;
        expect(batches, hasLength(2));
        expect(batches.map((batch) => batch.id).toSet(), hasLength(2));
        final duplicate = batches.firstWhere(
          (batch) => batch.files.length == 2,
        );
        final shares = await service.prepareShare(duplicate);
        expect(shares.map((file) => file.path).toSet(), hasLength(2));
      },
    );

    test('missing and different-size copies are visible without a false verified state', () async {
      final root = await historyTestRoot();
      final fixture = await writeHistoryDiskFixture(
        root,
        payloads: const <(String, List<int>)>[
          ('one.txt', <int>[1]),
          ('two.txt', <int>[2]),
        ],
      );
      await fixture.fileAt(0).delete();
      await fixture.fileAt(1).writeAsBytes(<int>[2, 3]);
      final batch = (await TransferHistoryService(
        root,
      ).load()).transfers.single;
      expect(batch.files[0].status, SavedFileStatus.missing);
      expect(batch.files[1].status, SavedFileStatus.sizeChanged);
      expect(batch.hasIssues, isTrue);
      expect(batch.allVerified, isFalse);
    });

    test('same-size content changes fail checksum verification and export preparation', () async {
      final root = await historyTestRoot();
      final fixture = await writeHistoryDiskFixture(root);
      await fixture.fileAt(0).writeAsBytes(<int>[8, 9, 0]);
      final service = TransferHistoryService(root);
      final entry = (await service.load()).transfers.single;
      expect(entry.files.single.status, SavedFileStatus.available);
      final checked = await service.verify(entry);
      expect(checked.files.single.status, SavedFileStatus.checksumMismatch);
      await expectLater(
        service.prepareShare(entry),
        throwsA(isA<HistoryException>()),
      );
      expect(await fixture.fileAt(0).readAsBytes(), <int>[8, 9, 0]);
    });

    test(
      'an individual intact copy can be shared when another file is missing',
      () async {
        final root = await historyTestRoot();
        final fixture = await writeHistoryDiskFixture(
          root,
          payloads: const <(String, List<int>)>[
            ('gone.txt', <int>[1]),
            ('keep.txt', <int>[2]),
          ],
        );
        await fixture.fileAt(0).delete();
        final service = TransferHistoryService(root);
        final entry = (await service.load()).transfers.single;
        final share = await service.prepareShare(entry, fileIndex: 1);
        expect(share.single.name, 'keep.txt');
        await expectLater(
          service.prepareShare(entry, fileIndex: -1),
          throwsA(isA<HistoryException>()),
        );
      },
    );

    test(
      'serialized localPath fields are never used to find shared files',
      () async {
        final root = await historyTestRoot();
        final fixture = await writeHistoryDiskFixture(root);
        final data = jsonDecode(
          await fixture.manifest.readAsString(),
        ) as Map<String, dynamic>;
        (data['files'] as List).first['localPath'] = '/outside/private.txt';
        await fixture.manifest.writeAsString(jsonEncode(data));
        final service = TransferHistoryService(root);
        final entry = (await service.load()).transfers.single;
        final files = await service.prepareShare(entry);
        expect(files.single.path, fixture.fileAt(0).path);
        expect(entry.receipt.files.single.localPath, isNull);
      },
    );

    test(
      'corrupt and oversized manifests are skipped without deletion',
      () async {
        final root = await historyTestRoot();
        final invalid = await writeHistoryDiskFixture(root);
        final large = await writeHistoryDiskFixture(root);
        await invalid.manifest.writeAsString('not json');
        await large.manifest.writeAsBytes(
          List<int>.filled(TransferLimits.maxMetadataBytes + 1, 65),
        );
        final result = await TransferHistoryService(root).load();
        expect(result.transfers, isEmpty);
        expect(result.skippedEntries, 2);
        expect(await invalid.directory.exists(), isTrue);
        expect(
          await large.manifest.length(),
          TransferLimits.maxMetadataBytes + 1,
        );
      },
    );

    test('staging and unrelated directories are ignored', () async {
      final root = await historyTestRoot();
      await Directory('${root.path}/.incoming-sb1-unfinished').create();
      await Directory('${root.path}/unrelated').create();
      final result = await TransferHistoryService(root).load();
      expect(result.transfers, isEmpty);
      expect(result.skippedEntries, 0);
      expect(await root.list().length, 2);
    });

    test(
      'file symlinks are blocked even if their target matches the checksum',
      () async {
        final root = await historyTestRoot();
        final fixture = await writeHistoryDiskFixture(root);
        final outside = File('${root.path}/outside.txt');
        await outside.writeAsBytes(<int>[1, 2, 3]);
        await fixture.fileAt(0).delete();
        await Link(fixture.fileAt(0).path).create(outside.path);
        final service = TransferHistoryService(root);
        final entry = (await service.load()).transfers.single;
        expect(entry.files.single.status, SavedFileStatus.unsafe);
        await expectLater(
          service.prepareShare(entry),
          throwsA(isA<HistoryException>()),
        );
        expect(await outside.readAsBytes(), <int>[1, 2, 3]);
      },
      skip: Platform.isWindows
          ? 'This symlink test needs POSIX link support.'
          : false,
    );

    test(
      'symlinked receipts, batch directories and storage roots are refused',
      () async {
        final root = await historyTestRoot();
        final fixture = await writeHistoryDiskFixture(root);
        final realManifest = File('${root.path}/real-manifest.json');
        await fixture.manifest.rename(realManifest.path);
        await Link(fixture.manifest.path).create(realManifest.path);
        await Link('${root.path}/received-${randomTransferId()}')
            .create(fixture.directory.path);
        final result = await TransferHistoryService(root).load();
        expect(result.transfers, isEmpty);
        expect(result.skippedEntries, 2);
        final link = Link('${root.path}/root-link');
        await link.create(root.path);
        await expectLater(
          TransferHistoryService(Directory(link.path)).load(),
          throwsA(isA<HistoryException>()),
        );
      },
      skip: Platform.isWindows
          ? 'This symlink test needs POSIX link support.'
          : false,
    );

    test('receipt edits after listing require a refresh before verification or sharing', () async {
      final root = await historyTestRoot();
      final fixture = await writeHistoryDiskFixture(root);
      final service = TransferHistoryService(root);
      final entry = (await service.load()).transfers.single;
      final data = jsonDecode(
        await fixture.manifest.readAsString(),
      ) as Map<String, dynamic>;
      data['senderName'] = 'Changed sender';
      await fixture.manifest.writeAsString(jsonEncode(data), flush: true);
      await expectLater(
        service.verify(entry),
        throwsA(isA<HistoryException>()),
      );
      await expectLater(
        service.prepareShare(entry),
        throwsA(isA<HistoryException>()),
      );
    });

    test(
      'canceling a streamed verification leaves files and receipts unchanged',
      () async {
        final root = await historyTestRoot();
        final bytes = List<int>.generate(131073, (index) => index % 251);
        final fixture = await writeHistoryDiskFixture(
          root,
          payloads: <(String, List<int>)>[('large.bin', bytes)],
        );
        final service = TransferHistoryService(root);
        final entry = (await service.load()).transfers.single;
        final before = await fixture.manifest.readAsBytes();
        final token = HistoryCancellation();
        await expectLater(
          service.verify(
            entry,
            cancellation: token,
            onProgress: (progress) {
              if (progress.bytesChecked > 0) token.cancel();
            },
          ),
          throwsA(isA<HistoryCancelled>()),
        );
        expect(await fixture.fileAt(0).readAsBytes(), bytes);
        expect(await fixture.manifest.readAsBytes(), before);
        final alreadyCanceled = HistoryCancellation()..cancel();
        await expectLater(
          service.load(cancellation: alreadyCanceled),
          throwsA(isA<HistoryCancelled>()),
        );
      },
    );

    test('scan limits are disclosed and never remove other batches', () async {
      final root = await historyTestRoot();
      await writeHistoryDiskFixture(root);
      await writeHistoryDiskFixture(root);
      await writeHistoryDiskFixture(root);
      final result = await TransferHistoryService(root, maxBatches: 2).load();
      expect(result.transfers, hasLength(2));
      expect(result.truncated, isTrue);
      expect(await root.list().length, 3);
    });

    test(
      'unchanged Part 2 TLS output can be loaded and verified by Part 3',
      () async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          final receiver = await startReceiverFixture(
            await TlsIdentity.generate(),
          );
          await LocalSender().send(
            code: receiver.code,
            files: <ShareFile>[
              bytesFile('from-network.txt', <int>[7, 8, 9]),
            ],
            senderName: 'Real TLS sender',
          );
          final service = TransferHistoryService(receiver.root);
          final entry = (await service.load()).transfers.single;
          expect(entry.receipt.senderName, 'Real TLS sender');
          expect((await service.verify(entry)).allVerified, isTrue);
          expect(
            await File((await service.prepareShare(entry)).single.path)
                .readAsBytes(),
            <int>[7, 8, 9],
          );
        } finally {
          HttpOverrides.global = previous;
        }
      },
    );
  });

  group('Part 3 QR display', () {
    testWidgets('active QR uses a white quiet zone and a real QR widget', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 9, 6, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairingQrCard(
              code: qrTestCode(),
              expiresAt: now.add(const Duration(minutes: 10)),
              clock: () => now,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('pairing-qr-image')), findsOneWidget);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, Colors.white);
      expect(qr.padding, const EdgeInsets.all(24));
      expect(qr.errorCorrectionLevel, QrErrorCorrectLevel.M);
      expect(find.text('New requests allowed for 10:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('QR is removed at expiry and a new invitation can be shown', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 9, 6, 12);
      final expiry = now.add(const Duration(seconds: 2));
      final code = qrTestCode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairingQrCard(
              code: code,
              expiresAt: expiry,
              clock: () => now,
            ),
          ),
        ),
      );
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('This invitation expired'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairingQrCard(
              code: code,
              expiresAt: now.add(const Duration(minutes: 2)),
              clock: () => now,
            ),
          ),
        ),
      );
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('QR remains readable-sized on a narrow large-text screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final now = DateTime.utc(2026);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: PairingQrCard(
                  code: qrTestCode(),
                  expiresAt: now.add(const Duration(minutes: 1)),
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(QrImageView)).width,
        greaterThanOrEqualTo(200),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Part 3 camera and QR flow', () {
    testWidgets('visiting the scanner does not start the camera', (
      tester,
    ) async {
      final camera = FakePairingCamera();
      await openFakeScanner(tester, camera);
      expect(camera.starts, 0);
      expect(find.text('Camera is off'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(camera.disposals, 1);
    });

    testWidgets(
      'a valid capture waits for explicit confirmation and ignores duplicates',
      (tester) async {
        final camera = FakePairingCamera();
        String? result;
        final code = qrTestCode();
        await openFakeScanner(
          tester,
          camera,
          result: (value) => result = value,
        );
        await tapVisibleKey(tester, const ValueKey('start-camera-button'));
        camera.events.add(code.encode());
        camera.events.add(qrTestCode(host: '192.168.4.2').encode());
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(camera.isRunning, isFalse);
        expect(find.text('Receiver: 192.168.4.1:43000'), findsOneWidget);
        await tapVisibleKey(tester, const ValueKey('use-scanned-code-button'));
        expect(result, code.encode());
        expect(camera.disposals, 1);
      },
    );

    testWidgets(
      'arbitrary URLs and malformed payloads are ignored without showing their content',
      (tester) async {
        final camera = FakePairingCamera();
        await openFakeScanner(tester, camera);
        await tapVisibleKey(tester, const ValueKey('start-camera-button'));
        camera.events.add('https://untrusted.example/private-value');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('scanned-code-confirmation')),
          findsNothing,
        );
        expect(
          find.textContaining('URLs and other QR content are ignored'),
          findsOneWidget,
        );
        expect(find.textContaining('untrusted.example'), findsNothing);
        expect(camera.isRunning, isTrue);
        await tester.pageBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('permission failure keeps the manual fallback usable', (
      tester,
    ) async {
      final camera = FakePairingCamera()
        ..startError = const PairingCameraException(
          'Camera permission denied for this test. Use manual code.',
        );
      String? result = 'not closed';
      await openFakeScanner(tester, camera, result: (value) => result = value);
      await tapVisibleKey(tester, const ValueKey('start-camera-button'));
      expect(
        find.textContaining('Camera permission denied for this test'),
        findsOneWidget,
      );
      await tapVisibleKey(
        tester,
        const ValueKey('manual-pairing-fallback-button'),
      );
      expect(result, isNull);
      expect(camera.isRunning, isFalse);
    });

    testWidgets(
      'backgrounding during camera startup stops a late permission result',
      (tester) async {
        final camera = FakePairingCamera()..pendingStart = Completer<void>();
        await openFakeScanner(tester, camera);
        final button = find.byKey(const ValueKey('start-camera-button'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        camera.pendingStart!.complete();
        await tester.pumpAndSettle();
        expect(camera.isRunning, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(camera.starts, 1);
        expect(camera.isRunning, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'disposing during startup ignores late results and releases the camera',
      (tester) async {
        final camera = FakePairingCamera()..pendingStart = Completer<void>();
        await openFakeScanner(tester, camera);
        final button = find.byKey(const ValueKey('start-camera-button'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        camera.pendingStart!.complete();
        await tester.pumpAndSettle();
        expect(camera.isRunning, isFalse);
        expect(camera.disposals, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('scan again restarts capture and flashlight remains explicit', (
      tester,
    ) async {
      final camera = FakePairingCamera();
      await openFakeScanner(tester, camera);
      await tapVisibleKey(tester, const ValueKey('start-camera-button'));
      await tapVisibleKey(tester, const ValueKey('camera-torch-button'));
      expect(camera.light, isTrue);
      camera.events.add(qrTestCode().encode());
      await tester.pumpAndSettle();
      await tapVisibleKey(tester, const ValueKey('scan-again-button'));
      expect(camera.starts, 2);
      expect(
        find.byKey(const ValueKey('scanned-code-confirmation')),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'QR selection fills the sender field without reading or sending files',
      (tester) async {
        var reads = 0;
        final code = qrTestCode();
        await tester.pumpWidget(
          MaterialApp(
            home: NearbyScreen(
              mode: NearbyMode.send,
              files: <ShareFile>[
                sampleFile(
                  openRead: () {
                    reads += 1;
                    return const Stream<List<int>>.empty();
                  },
                ),
              ],
              scanCode: (context) async => code.encode(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisibleKey(tester, const ValueKey('scan-receiver-qr-button'));
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('pairing-code-field')),
        );
        expect(field.controller!.text, code.encode());
        expect(reads, 0);
        expect(find.text('Delivery confirmed'), findsNothing);
        await tester.scrollUntilVisible(
          find.textContaining('QR code filled'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('QR code filled'), findsOneWidget);
      },
    );

    testWidgets(
      'canceling the QR route preserves an already-entered manual code',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: NearbyScreen(
              mode: NearbyMode.send,
              files: <ShareFile>[sampleFile()],
              scanCode: (context) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('pairing-code-field')),
          'manual code stays',
        );
        await tapVisibleKey(tester, const ValueKey('scan-receiver-qr-button'));
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('pairing-code-field')),
              )
              .controller!
              .text,
          'manual code stays',
        );
      },
    );
  });

  group('Part 3 history interface', () {
    testWidgets('empty history has no invented transfer rows', (tester) async {
      await mountHistory(
        tester,
        FakeHistoryService(HistorySnapshot(transfers: <SavedTransfer>[])),
      );
      expect(find.text('No received files yet'), findsOneWidget);
      expect(find.text('0 batches · 0 recorded files · 0 B'), findsOneWidget);
    });

    testWidgets(
      'local search and issue filtering select the matching batches',
      (tester) async {
        final good = savedUiFixture(sender: 'Ayesha', name: 'trip.jpg');
        final missing = savedUiFixture(
          sender: 'Rafi',
          name: 'report.pdf',
          status: SavedFileStatus.missing,
        );
        await mountHistory(
          tester,
          FakeHistoryService(
            HistorySnapshot(transfers: <SavedTransfer>[good, missing]),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('history-search-field')),
          'trip',
        );
        await tester.pumpAndSettle();
        expect(find.text('Ayesha'), findsOneWidget);
        expect(find.text('Rafi'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('history-search-field')),
          '',
        );
        await tapVisibleKey(tester, const ValueKey('history-filter-attention'));
        expect(find.text('Rafi'), findsOneWidget);
        expect(find.text('Ayesha'), findsNothing);
      },
    );

    testWidgets(
      'verification is explicit and then updates the checked status',
      (tester) async {
        final entry = savedUiFixture();
        final service = FakeHistoryService(
          HistorySnapshot(transfers: <SavedTransfer>[entry]),
        );
        await mountHistory(tester, service);
        expect(service.verifies, 0);
        await tapVisibleKey(
          tester,
          PageStorageKey('history-batch-${entry.id}'),
        );
        expect(
          find.textContaining('Size matches · not rechecked'),
          findsOneWidget,
        );
        await tapVisibleKey(tester, ValueKey('verify-history-${entry.id}'));
        expect(service.verifies, 1);
        expect(
          find.textContaining('Checksum verified this session'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'history share checks copies first and does not claim the destination saved them',
      (tester) async {
        final entry = savedUiFixture();
        final service = FakeHistoryService(
          HistorySnapshot(transfers: <SavedTransfer>[entry]),
        );
        var shares = 0;
        await mountHistory(
          tester,
          service,
          shareAction: (files, origin) async {
            expect(service.preparations, 1);
            expect(origin.width, greaterThan(0));
            shares += 1;
          },
        );
        await tapVisibleKey(
          tester,
          PageStorageKey('history-batch-${entry.id}'),
        );
        await tapVisibleKey(tester, ValueKey('share-history-${entry.id}'));
        expect(shares, 1);
        expect(
          find.textContaining(
            'Check the destination to confirm exported copies',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('canceling preparation prevents a native share action', (
      tester,
    ) async {
      final entry = savedUiFixture();
      final service = FakeHistoryService(
        HistorySnapshot(transfers: <SavedTransfer>[entry]),
      )..pendingPreparation = Completer<void>();
      var shares = 0;
      await mountHistory(
        tester,
        service,
        shareAction: (files, origin) async => shares += 1,
      );
      await tapVisibleKey(tester, PageStorageKey('history-batch-${entry.id}'));
      final share = find.byKey(ValueKey('share-history-${entry.id}'));
      await tester.ensureVisible(share);
      await tester.pumpAndSettle();
      await tester.tap(share);
      await tester.pump();
      final cancel = find.byKey(const ValueKey('cancel-history-check-button'));
      await tester.ensureVisible(cancel);
      await tester.pump();
      await tester.tap(cancel);
      service.pendingPreparation!.complete();
      await tester.pumpAndSettle();
      expect(shares, 0);
      expect(find.textContaining('File checking canceled'), findsOneWidget);
    });

    testWidgets('a history screen ignores a load completed after disposal', (
      tester,
    ) async {
      final service = FakeHistoryService(
        HistorySnapshot(transfers: <SavedTransfer>[]),
      )..pendingLoad = Completer<HistorySnapshot>();
      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(service: service)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      service.pendingLoad!.complete(
        HistorySnapshot(transfers: <SavedTransfer>[savedUiFixture()]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'home can open saved files and return without losing the selection',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async =>
                  FileSelection(files: <ShareFile>[sampleFile()]),
              onToggleTheme: () {},
              historyScreenBuilder: (context) => HistoryScreen(
                service: FakeHistoryService(
                  HistorySnapshot(transfers: <SavedTransfer>[]),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapSelect(tester);
        await tapNavigation(tester, 'nav-home');
        await tapVisibleKey(tester, const ValueKey('saved-files-button'));
        expect(find.byKey(const ValueKey('history-scaffold')), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapNavigation(tester, 'nav-files');
        expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      },
    );
  });
}
```

### File 6 — `lib/models/transfer_models.dart` — UNCHANGED

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

### File 7 — `lib/services/local_transfer_service.dart` — UNCHANGED

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

### File 8 — `lib/screens/nearby_screen.dart` — UPDATED

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
import '../widgets/pairing_qr_card.dart';
import 'scan_pairing_screen.dart';

enum NearbyMode { send, receive }

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    super.key,
    required this.mode,
    this.files = const <ShareFile>[],
    this.documentsDirectory = getApplicationDocumentsDirectory,
    this.scanCode = scanReceiverCode,
  });

  final NearbyMode mode;
  final List<ShareFile> files;
  final Future<Directory> Function() documentsDirectory;
  final Future<String?> Function(BuildContext context) scanCode;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  final TextEditingController _codeController = TextEditingController();
  final ScrollController _bodyScroll = ScrollController();
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
  bool _scanning = false;
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
    _bodyScroll.dispose();
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

  void _focusStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canUpdate && _bodyScroll.hasClients) {
        _bodyScroll.jumpTo(0);
      }
    });
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
    _focusStatus();
    return decision.future;
  }

  void _receiveProgress(TransferProgress progress) {
    if (!_canUpdate) {
      return;
    }
    final changedPhase = _progress?.phase != progress.phase;
    if (progress.phase != TransferPhase.awaitingApproval) {
      _resolveDecision(false);
    }
    setState(() => _progress = progress);
    if (changedPhase && progress.phase != TransferPhase.waiting) {
      _focusStatus();
    }
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

  Future<void> _scanReceiverQr() async {
    if (_sending || _scanning || !_foreground) {
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final result = await widget.scanCode(context);
      if (!_canUpdate || !_foreground || result == null) {
        return;
      }
      final code = PairingCode.parse(result);
      _codeController.text = code.encode();
      setState(
        () => _notice = 'QR code filled. Review it, then tap Ask to send.',
      );
    } catch (error) {
      if (_canUpdate) {
        setState(
          () => _error = error is TransferException
              ? error.message
              : 'The QR scanner could not open. Use manual pairing instead.',
        );
      }
    } finally {
      if (_canUpdate) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _scanning) {
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
    _focusStatus();
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
                controller: _bodyScroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: <Widget>[
                  if (_pendingOffer != null)
                    _buildApproval(theme, _pendingOffer!),
                  if (_progress != null &&
                      _progress!.phase != TransferPhase.waiting)
                    _ProgressPanel(progress: _progress!),
                  if (_receipt != null) _buildReceipt(theme, _receipt!),
                  _buildHeader(theme),
                  const SizedBox(height: 18),
                  if (_error != null)
                    _MessagePanel(message: _error!, isError: true),
                  if (_notice != null) _MessagePanel(message: _notice!),
                  if (_isReceiver)
                    _buildReceiver(theme)
                  else
                    _buildSender(theme),
                  if (_progress?.phase == TransferPhase.waiting)
                    _ProgressPanel(progress: _progress!),
                  const SizedBox(height: 16),
                  const _MessagePanel(
                    message:
                        'Part 3: private IPv4 Wi-Fi/hotspot only. Keep both apps open. '
                        'Up to 50 files, 2 GiB each, 4 GiB per batch. '
                        'QR and manual pairing are available. Resume and background transfer are not added yet.',
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
                  'PART 03 · LOCAL TLS',
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
                ? 'Start a session, show your QR or copy your code, then review the sender request.'
                : 'Scan the receiver QR or paste their code. File bytes leave only after they approve.',
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
                    onChanged: (host) {
                      if (host != null) {
                        setState(() => _selectedHost = host);
                      }
                    },
                  )
                else
                  Text(
                    'Local address: ${session.addresses.first}:${session.port}',
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 12),
                PairingQrCard(
                  code: session.codeFor(_selectedHost!),
                  expiresAt: session.expiresAt,
                ),
                const SizedBox(height: 16),
                Text('Manual pairing code', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
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
                  'Keep the QR and complete code private. The sender can scan or paste it.',
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
                key: const ValueKey('scan-receiver-qr-button'),
                onPressed: _sending || _scanning ? null : _scanReceiverQr,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan receiver QR'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('paste-code-button'),
                onPressed: _sending || _scanning ? null : _pasteCode,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste code'),
              ),
              FilledButton.icon(
                key: const ValueKey('ask-to-send-button'),
                onPressed: _sending || _scanning || widget.files.isEmpty
                    ? null
                    : _send,
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

### File 9 — `android/app/src/main/AndroidManifest.xml` — UPDATED

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
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

### File 10 — `ios/Runner/Info.plist` — UPDATED

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
	<key>NSCameraUsageDescription</key>
	<string>ShareBondhu uses the camera to scan the pairing QR shown by a nearby receiver. Scanning does not start a file transfer or save camera images.</string>
</dict>
</plist>
```


## চালানো ও যাচাই

নতুন camera/native dependency-এর জন্য app সম্পূর্ণ বন্ধ করে rebuild করুন; শুধু hot reload নয়। project root-এ:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

ZIP-এ numbered File 1–15 ছাড়াও পুরো standard Android/iOS runner, assets, Gradle wrapper, configuration, lockfile ও documentation আছে। SDK/package caches/build outputs/machine-specific generated files source হিসেবে বিতরণ করা হয়নি; Flutter tools প্রয়োজনমতো regenerate করবে। ZIP-এর included file list `docs/FILE_INVENTORY.txt`-এ আছে।

৯৭টি automated test পাস হয়েছে এবং analysis clean। Software decoder দুইটি actual Flutter QR raster থেকে সম্পূর্ণ SB1 code ফিরিয়ে দিয়েছে। Camera flow test adapter দিয়ে পরীক্ষা হয়েছে; **বাস্তব camera/phone, native APK/IPA build ও share sheet এখনো যাচাই করা হয়নি**। প্রথমে দুইটি বাস্তব ফোনে ছোট, locally stored file দিয়ে trusted Wi-Fi-তে পরীক্ষা করুন। কোনো store-ready বা audited-security দাবি করা হচ্ছে না।

## ▶ Next — Part 4 (File 16–20)

পরের ধাপে settings/branding এবং device-test/release-preparation এগোব। বর্তমান QR/manual pairing, received history, selection ও সব v1 endpoint রাখা হবে। পরিবর্তিত পুরোনো file-এরও সম্পূর্ণ code আবার দেব।

চালিয়ে যেতে চ্যাটে **`Next`** লিখুন।
