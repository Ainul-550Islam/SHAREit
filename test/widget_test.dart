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
