import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/saved_transfer.dart';
import 'package:sharebondhu/models/transfer_activity.dart';
import 'package:sharebondhu/models/transfer_models.dart';
import 'package:sharebondhu/screens/history_screen.dart';
import 'package:sharebondhu/screens/nearby_screen.dart';
import 'package:sharebondhu/services/local_transfer_service.dart';
import 'package:sharebondhu/services/transfer_history_service.dart';
import 'package:sharebondhu/services/transfer_progress_controller.dart';
import 'package:sharebondhu/widgets/transfer_progress_panel.dart';
import 'package:sharebondhu/widgets/transfer_result_panel.dart';

import 'package:sharebondhu/models/share_coin_models.dart';
import 'package:sharebondhu/models/user_models.dart';
import 'package:sharebondhu/services/share_coin_service.dart';
import 'package:sharebondhu/services/connectivity_service.dart';
import 'package:sharebondhu/screens/share_coin_home_screen.dart';
import 'package:sharebondhu/screens/home_screen.dart';

import 'widget_test.dart' as baseline;

class ProgressProbe {
  ProgressProbe({
    List<int> sizes = const <int>[1000],
    this.role = TransferRole.sender,
  }) {
    files = List<OfferedFile>.generate(
      sizes.length,
      (i) => OfferedFile(
        id: randomTransferId(),
        name: 'file-$i.bin',
        size: sizes[i],
      ),
    );
    controller = TransferProgressController(
      clock: () => time,
      autoRefresh: false,
    );
    epoch = controller.open(role);
    addTearDown(controller.dispose);
  }
  final TransferRole role;
  final String id = randomTransferId();
  String attempt = randomTransferId();
  late List<OfferedFile> files;
  late TransferProgressController controller;
  late int epoch;
  int sequence = 0;
  Duration time = Duration.zero;
  TransferActivity get state => controller.value;

  TransferProgress frame(
    TransferPhase phase, {
    int? bytes,
    int? done,
    int? checked,
    int? index,
    int? fileBytes,
    bool commit = false,
    TransferReceipt? receipt,
  }) {
    final active = index ?? state.progress.currentFileIndex;
    return TransferProgress(
      phase: phase,
      message: 'Engine event: ${phase.name}',
      transferId: id,
      attemptId: attempt,
      sequence: ++sequence,
      manifest: files,
      totalBytes: files.fold<int>(0, (sum, file) => sum + file.size),
      totalFiles: files.length,
      processedBytes: bytes ?? state.batchBytes,
      completedFiles: done ?? state.completedFiles,
      verifiedFiles: checked ?? state.verifiedFiles,
      currentFileIndex: active,
      currentFileTotalBytes:
          active == null || active >= files.length || active < 0
          ? null
          : files[active].size,
      currentFileBytes: active == null
          ? null
          : fileBytes ?? state.fileBytes ?? 0,
      fileName: active == null || active >= files.length || active < 0
          ? null
          : files[active].name,
      commitStarted: commit,
      receipt: receipt,
    );
  }

  bool step(
    TransferPhase phase, {
    int? bytes,
    int? done,
    int? checked,
    int? index,
    int? fileBytes,
    bool commit = false,
    TransferReceipt? receipt,
  }) => controller.addEngineEvent(
    epoch,
    frame(
      phase,
      bytes: bytes,
      done: done,
      checked: checked,
      index: index,
      fileBytes: fileBytes,
      commit: commit,
      receipt: receipt,
    ),
  );

  void start() {
    if (role == TransferRole.sender) step(TransferPhase.connecting);
    step(TransferPhase.awaitingApproval);
    step(TransferPhase.approved);
    step(TransferPhase.preparing, index: 0, fileBytes: 0);
    step(
      role == TransferRole.sender
          ? TransferPhase.sending
          : TransferPhase.receiving,
    );
  }

  TransferReceipt receipt({String? digest}) => TransferReceipt(
    id: id,
    senderName: 'Test peer',
    completedAt: DateTime.utc(2026, 9, 8),
    files: files.map(
      (file) => ReceivedFile(
        id: file.id,
        name: file.name,
        size: file.size,
        digest: digest ?? sha256.convert(<int>[1]).toString(),
      ),
    ),
  );

  void finishBytes() {
    for (var index = 0; index < files.length; index += 1) {
      if (index > 0) step(TransferPhase.preparing, index: index, fileBytes: 0);
      final bytes = files
          .take(index + 1)
          .fold<int>(0, (sum, file) => sum + file.size);
      step(
        role == TransferRole.sender
            ? TransferPhase.sending
            : TransferPhase.receiving,
        index: index,
        fileBytes: files[index].size,
        bytes: bytes,
        done: index + 1,
        checked: role == TransferRole.sender ? index + 1 : 0,
      );
    }
  }
}

// Test-only sender: production NearbyScreen still defaults to LocalSender.new.
class ControlledSender extends LocalSender {
  final Completer<TransferReceipt> completion = Completer<TransferReceipt>();
  late IncomingOffer offer;
  void Function(TransferProgress)? callback;
  int sequence = 0;
  int cancellations = 0;
  @override
  Future<TransferReceipt> send({
    required PairingCode code,
    required List<ShareFile> files,
    required String senderName,
    void Function(TransferProgress)? onProgress,
  }) {
    offer = createOutgoingOffer(files, senderName);
    callback = onProgress;
    emit(TransferPhase.connecting);
    emit(TransferPhase.awaitingApproval);
    return completion.future;
  }

  void emit(
    TransferPhase phase, {
    bool full = false,
    TransferReceipt? receipt,
  }) {
    callback?.call(
      TransferProgress(
        phase: phase,
        message: 'Controlled UI-test event',
        transferId: offer.id,
        attemptId: offer.id,
        sequence: ++sequence,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        totalFiles: offer.files.length,
        processedBytes: full ? offer.totalBytes : 0,
        completedFiles: full ? offer.files.length : 0,
        verifiedFiles: full ? offer.files.length : 0,
        receipt: receipt,
      ),
    );
  }

  @override
  void cancel() {
    cancellations += 1;
    if (!completion.isCompleted) {
      completion.completeError(const TransferCancelled());
    }
  }

  void fail() {
    if (!completion.isCompleted) {
      completion.completeError(
        const TransferException('Test source became unreadable.'),
      );
    }
  }

  void confirm() {
    final receipt = TransferReceipt(
      id: offer.id,
      senderName: offer.senderName,
      completedAt: DateTime.utc(2026, 9, 8),
      files: offer.files.map(
        (file) => ReceivedFile(
          id: file.id,
          name: file.name,
          size: file.size,
          digest: sha256.convert(<int>[1]).toString(),
        ),
      ),
    );
    emit(TransferPhase.approved);
    emit(TransferPhase.sending, full: true);
    emit(TransferPhase.completed, full: true, receipt: receipt);
    completion.complete(receipt);
  }
}

Future<void> mountSender(WidgetTester tester, ControlledSender sender) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: NearbyScreen(
        mode: NearbyMode.send,
        files: <ShareFile>[baseline.sampleFile(size: 3)],
        senderFactory: () => sender,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pairing-code-field')),
    baseline.qrTestCode().encode(),
  );
  final button = find.byKey(const ValueKey('ask-to-send-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  registerPart5Tests();
  group('Part 4 controller', () {
    test('01 initial idle state', () {
      final p = ProgressProbe();
      expect(p.state.phase, TransferPhase.idle);
      expect(p.state.percentage, 0);
      expect(p.state.eta, isNull);
      expect(p.state.canCancel, isFalse);
    });
    test('02 connecting state', () {
      final p = ProgressProbe();
      expect(p.step(TransferPhase.connecting), isTrue);
      expect(p.state.phase, TransferPhase.connecting);
      expect(p.state.batchBytes, 0);
    });
    test('03 waiting for approval has no file bytes', () {
      final p = ProgressProbe();
      p.step(TransferPhase.connecting);
      p.step(TransferPhase.awaitingApproval);
      expect(p.state.phase, TransferPhase.awaitingApproval);
      expect(p.state.currentFileNumber, isNull);
    });
    test('04 approval is a distinct real-engine state', () {
      final p = ProgressProbe();
      p.step(TransferPhase.connecting);
      p.step(TransferPhase.awaitingApproval);
      p.step(TransferPhase.approved);
      expect(p.state.phase, TransferPhase.approved);
      expect(p.state.successfulFiles, 0);
    });
    test('05 sending counters come from events', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
      expect(p.state.phase, TransferPhase.sending);
      expect(p.state.batchBytes, 100);
      expect(p.state.fileBytes, 100);
    });
    test('06 receiver uses the same progress abstraction', () {
      final p = ProgressProbe(role: TransferRole.receiver)..start();
      p.step(TransferPhase.receiving, bytes: 80, fileBytes: 80);
      expect(p.state.phase, TransferPhase.receiving);
      expect(p.state.role, TransferRole.receiver);
    });
    test('07 verifying is not completed', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.verifying, commit: true);
      expect(p.state.phase, TransferPhase.verifying);
      expect(p.state.percentage, 100);
      expect(p.state.confirmed, isFalse);
    });
    test('08 completion requires an engine-validated receipt boundary', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed);
      expect(p.state.confirmed, isFalse);
      expect(p.state.terminal, isFalse);
      p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt());
      expect(p.state.phase, TransferPhase.completed);
      expect(p.state.successfulFiles, 1);
    });
    test('09 definitive failure preserves real byte counts', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 45, fileBytes: 45);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('File read failed.'),
      );
      expect(p.state.phase, TransferPhase.failed);
      expect(p.state.batchBytes, 45);
      expect(p.state.unsuccessfulFiles, 1);
    });
    test('10 requested cancellation is not prematurely terminal', () {
      final p = ProgressProbe()..start();
      p.controller.requestCancellation(p.epoch);
      expect(p.state.cancelRequested, isTrue);
      expect(p.state.terminal, isFalse);
      p.controller.finishFailure(p.epoch, const TransferCancelled());
      expect(p.state.phase, TransferPhase.canceled);
    });
    test(
      '11 zero-byte file uses staged-file completion without division by zero',
      () {
        final p = ProgressProbe(sizes: <int>[0])..start();
        expect(p.state.fraction, 0);
        p.finishBytes();
        expect(p.state.percentage, 100);
        expect(p.state.confirmed, isFalse);
        p.step(TransferPhase.completed, receipt: p.receipt());
        expect(p.state.confirmed, isTrue);
        expect(p.state.batchBytes, 0);
      },
    );
    test('12 single-file name index and byte totals', () {
      final p = ProgressProbe(sizes: <int>[72])..start();
      p.step(TransferPhase.sending, bytes: 20, fileBytes: 20);
      expect(p.state.fileName, 'file-0.bin');
      expect(p.state.currentFileNumber, 1);
      expect(p.state.fileTotalBytes, 72);
    });
    test('13 multiple files keep cumulative bytes and separate file bytes', () {
      final p = ProgressProbe(sizes: <int>[100, 200])..start();
      p.step(
        TransferPhase.sending,
        bytes: 100,
        fileBytes: 100,
        done: 1,
        checked: 1,
      );
      p.step(TransferPhase.preparing, index: 1, fileBytes: 0);
      p.step(TransferPhase.sending, bytes: 150, fileBytes: 50);
      expect(p.state.fileBytes, 50);
      expect(p.state.batchBytes, 150);
      expect(p.state.totalBytes, 300);
      expect(p.state.currentFileNumber, 2);
      expect(p.state.completedFiles, 1);
    });
    test('14 exactly 100 percent bytes does not imply delivery', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      expect(p.state.fraction, 1);
      expect(p.state.successfulFiles, 0);
      expect(p.state.receipt, isNull);
    });
    test('15 invalid over-range and negative counters are safely bounded', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: -30, fileBytes: -20, done: -4);
      expect(p.state.batchBytes, 0);
      expect(p.state.fileBytes, 0);
      p.step(TransferPhase.sending, bytes: 9999, fileBytes: 9999, done: 99);
      expect(p.state.percentage, 100);
      expect(p.state.completedFiles, 1);
      expect(p.state.confirmed, isFalse);
      expect(p.state.warning, isNotNull);
    });
    test(
      '16 cancellation during transfer rejects duplicate cancel requests',
      () {
        final p = ProgressProbe()..start();
        expect(p.controller.requestCancellation(p.epoch), isTrue);
        expect(p.controller.requestCancellation(p.epoch), isFalse);
        p.controller.finishFailure(p.epoch, const TransferCancelled());
        expect(p.state.successfulFiles, 0);
      },
    );
    test('17 a real completion receipt wins a cancellation race', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.controller.requestCancellation(p.epoch);
      p.controller.finishFailure(p.epoch, const TransferCancelled());
      expect(
        p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt()),
        isTrue,
      );
      expect(p.state.confirmed, isTrue);
      expect(p.state.cancelRequested, isTrue);
    });
    test('18 commit ambiguity never guesses success or failure counts', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.verifying, commit: true);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('Confirmation lost.', outcomeUncertain: true),
      );
      p.controller.settle(p.epoch);
      expect(p.state.successfulFiles, isNull);
      expect(p.state.unsuccessfulFiles, isNull);
      expect(p.state.canRetry, isFalse);
    });
    test('19 safe retry requires settled uncommitted work and a new epoch', () {
      final p = ProgressProbe()..start();
      final oldEpoch = p.epoch;
      final oldEvent = p.frame(TransferPhase.sending, bytes: 5, fileBytes: 5);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('Connection failed.'),
      );
      expect(p.state.canRetry, isFalse);
      p.controller.settle(p.epoch);
      expect(p.state.canRetry, isTrue);
      p.epoch = p.controller.open(TransferRole.sender);
      expect(p.controller.addEngineEvent(oldEpoch, oldEvent), isFalse);
      expect(p.state.phase, TransferPhase.idle);
    });
    test('20 file-count progress cannot regress', () {
      final p = ProgressProbe(sizes: <int>[10, 20])..start();
      p.step(TransferPhase.sending, bytes: 10, fileBytes: 10, done: 1);
      expect(p.step(TransferPhase.sending, done: 0), isFalse);
      expect(p.state.completedFiles, 1);
    });
    test('21 byte-count progress cannot regress', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
      expect(p.step(TransferPhase.sending, bytes: 80, fileBytes: 80), isFalse);
      expect(p.state.batchBytes, 100);
    });
    test(
      '22 speed is measured from monotonic elapsed time and actual bytes',
      () {
        final p = ProgressProbe()..start();
        p.time = const Duration(seconds: 2);
        p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
        expect(p.state.bytesPerSecond, closeTo(100, 0.001));
      },
    );
    test(
      '23 ETA estimates only the remaining payload and expires on stalls',
      () {
        final p = ProgressProbe()..start();
        p.time = const Duration(seconds: 2);
        p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
        expect(p.state.eta, const Duration(seconds: 8));
        p.time = const Duration(seconds: 6);
        p.controller.refreshEstimates();
        expect(p.state.bytesPerSecond, 0);
        expect(p.state.eta, isNull);
        expect(p.state.batchBytes, 200);
      },
    );
    test('24 malformed verification receipts cannot confirm delivery', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed, receipt: p.receipt(digest: 'not-a-hash'));
      expect(p.state.confirmed, isFalse);
      expect(p.state.warning, contains('receipt'));
    });
    test('29 duplicate and stale progress frames are ignored', () {
      final p = ProgressProbe()..start();
      final event = p.frame(TransferPhase.sending, bytes: 10, fileBytes: 10);
      expect(p.controller.addEngineEvent(p.epoch, event), isTrue);
      expect(p.controller.addEngineEvent(p.epoch, event), isFalse);
      expect(
        p.controller.addEngineEvent(
          p.epoch,
          event.copyWith(attemptId: randomTransferId(), sequence: 999),
        ),
        isFalse,
      );
      expect(p.state.batchBytes, 10);
    });
    test('30 inconsistent metadata indices totals and states do not corrupt progress', () {
      final p = ProgressProbe()..start();
      final wrongTotal = p
          .frame(TransferPhase.sending)
          .copyWith(totalBytes: 4000);
      expect(p.controller.addEngineEvent(p.epoch, wrongTotal), isFalse);
      expect(p.step(TransferPhase.sending, index: 8), isFalse);
      expect(p.step(TransferPhase.connecting), isFalse);
      expect(p.state.phase, TransferPhase.sending);
      expect(p.state.totalBytes, 1000);
    });
    test('repeated wire IDs have distinct receiver attempt identities', () {
      final p = ProgressProbe(role: TransferRole.receiver)
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed, receipt: p.receipt());
      final oldAttempt = p.attempt;
      p.attempt = randomTransferId();
      final event = TransferProgress(
        phase: TransferPhase.awaitingApproval,
        message: 'Next offer',
        transferId: p.id,
        attemptId: p.attempt,
        sequence: ++p.sequence,
        manifest: p.files,
        totalBytes: 1000,
        totalFiles: 1,
      );
      expect(p.controller.addEngineEvent(p.epoch, event), isTrue);
      expect(p.state.confirmed, isFalse);
      expect(
        p.controller.completeFromReceipt(p.epoch, oldAttempt, p.receipt()),
        isFalse,
      );
    });
    test(
      'public activity projection remains safe for malformed numerical inputs',
      () {
        final activity = TransferActivity(
          progress: const TransferProgress(
            phase: TransferPhase.sending,
            message: '',
            processedBytes: -10,
            totalBytes: -1,
            totalFiles: -5,
          ),
          measuredBytesPerSecond: double.nan,
          estimatedRemaining: const Duration(seconds: -1),
        );
        expect(activity.fraction, 0);
        expect(activity.totalFiles, 0);
        expect(activity.bytesPerSecond, isNull);
        expect(activity.eta, isNull);
      },
    );
    test('clock rollback and estimator refresh never create bytes', () {
      final p = ProgressProbe()..start();
      p.time = const Duration(seconds: 2);
      p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
      p.time = const Duration(seconds: 1);
      p.controller.refreshEstimates();
      expect(p.state.batchBytes, 200);
      expect(p.state.bytesPerSecond, isNull);
    });
    test(
      'disposed controller ignores queued progress receipts and cancellation',
      () {
        final p = ProgressProbe()..start();
        final event = p.frame(TransferPhase.sending, bytes: 1, fileBytes: 1);
        p.controller.dispose();
        expect(p.controller.addEngineEvent(p.epoch, event), isFalse);
        expect(
          p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt()),
          isFalse,
        );
        expect(p.controller.requestCancellation(p.epoch), isFalse);
      },
    );
  });

  group('Part 4 malformed-event regressions', () {
    test('a rejected high sequence cannot poison later valid telemetry', () {
      final p = ProgressProbe()..start();
      final bad = p
          .frame(TransferPhase.sending)
          .copyWith(sequence: 999999, totalBytes: 9000);
      expect(p.controller.addEngineEvent(p.epoch, bad), isFalse);
      expect(p.step(TransferPhase.sending, bytes: 30, fileBytes: 30), isTrue);
      expect(p.state.batchBytes, 30);
    });
    test(
      'current-file counters cannot go backwards while batch counters advance',
      () {
        final p = ProgressProbe()..start();
        p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
        expect(
          p.step(TransferPhase.sending, bytes: 110, fileBytes: 90),
          isFalse,
        );
        expect(p.state.fileBytes, 100);
      },
    );
    test('malformed hash-check counts cannot invent matched checksums', () {
      final p = ProgressProbe()..start();
      p.step(
        TransferPhase.sending,
        bytes: 1000,
        fileBytes: 1000,
        done: 1,
        checked: 999,
      );
      expect(p.state.verifiedFiles, 0);
      expect(p.state.confirmed, isFalse);
    });
  });

  group('Part 4 real TLS progress', () {
    late TlsIdentity identity;
    HttpOverrides? previous;
    setUpAll(() async {
      identity = await TlsIdentity.generate();
    });
    setUp(() {
      previous = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() {
      HttpOverrides.global = previous;
    });

    test(
      '25 receiver completion uses existing saved history and receipt',
      () async {
        final controller = TransferProgressController(autoRefresh: false);
        addTearDown(controller.dispose);
        final epoch = controller.open(TransferRole.receiver);
        final phases = <TransferPhase>{};
        final receiver = await baseline.startReceiverFixture(
          identity,
          progress: (event) {
            phases.add(event.phase);
            expect(controller.addEngineEvent(epoch, event), isTrue);
          },
        );
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('one.txt', <int>[1, 2]),
            baseline.bytesFile('empty.txt', <int>[]),
          ],
          senderName: 'Progress integration',
        );
        expect(controller.value.confirmed, isTrue);
        expect(controller.value.verifiedFiles, 2);
        expect(
          phases,
          containsAll(<TransferPhase>[
            TransferPhase.approved,
            TransferPhase.preparing,
            TransferPhase.receiving,
            TransferPhase.verifying,
            TransferPhase.completed,
          ]),
        );
        final history = await TransferHistoryService(receiver.root).load();
        expect(
          history.transfers.single.receipt.id,
          controller.value.receipt!.id,
        );
      },
    );
    test(
      '26 sender confirmation and counters use real TLS engine events',
      () async {
        final receiver = await baseline.startReceiverFixture(identity);
        final controller = TransferProgressController(autoRefresh: false);
        addTearDown(controller.dispose);
        final epoch = controller.open(TransferRole.sender);
        final stages = <int>[];
        final receipt = await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('a.txt', <int>[1]),
            baseline.bytesFile('b.txt', <int>[2, 3]),
          ],
          senderName: 'Sender',
          onProgress: (event) {
            expect(controller.addEngineEvent(epoch, event), isTrue);
            stages.add(event.completedFiles);
          },
        );
        expect(controller.value.receipt, same(receipt));
        expect(controller.value.batchBytes, 3);
        expect(stages, containsAll(<int>[0, 1, 2]));
      },
    );
    test('real approval denial reads no source and remains retryable only after settlement', () async {
      final receiver = await baseline.startReceiverFixture(
        identity,
        approve: (_) async => false,
      );
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      var reads = 0;
      try {
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.sampleFile(
              size: 3,
              openRead: () {
                reads += 1;
                return Stream<List<int>>.value(<int>[1, 2, 3]);
              },
            ),
          ],
          senderName: 'Denied',
          onProgress: (event) => controller.addEngineEvent(epoch, event),
        );
        fail('A declined batch must not complete.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      expect(reads, 0);
      expect(controller.value.canRetry, isFalse);
      controller.settle(epoch);
      expect(controller.value.canRetry, isTrue);
    });
    test('real streamed cancellation keeps original content and records no saved success', () async {
      final receiver = await baseline.startReceiverFixture(identity);
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      final sender = LocalSender();
      final source = ShareFile(
        name: 'cancel.bin',
        size: 4,
        sourceUri: Uri.file('/selected/cancel.bin'),
        readStream: () async* {
          yield <int>[1, 2];
          await Future<void>.delayed(const Duration(milliseconds: 30));
          yield <int>[3, 4];
        },
      );
      try {
        await sender.send(
          code: receiver.code,
          files: <ShareFile>[source],
          senderName: 'Cancel test',
          onProgress: (event) {
            controller.addEngineEvent(epoch, event);
            if (event.processedBytes > 0 && !controller.value.cancelRequested) {
              controller.requestCancellation(epoch);
              sender.cancel();
            }
          },
        );
        fail('Canceled streaming must not complete.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      controller.settle(epoch);
      expect(controller.value.phase, TransferPhase.canceled);
      expect(controller.value.successfulFiles, 0);
      expect(
        (await TransferHistoryService(receiver.root).load()).transfers,
        isEmpty,
      );
    });
    test('real source failure has no false successful-file count', () async {
      final receiver = await baseline.startReceiverFixture(identity);
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      try {
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('short.txt', <int>[1], declaredSize: 2),
          ],
          senderName: 'Short source',
          onProgress: (event) => controller.addEngineEvent(epoch, event),
        );
        fail('A short stream must fail.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      expect(controller.value.phase, TransferPhase.failed);
      expect(controller.value.batchBytes, 1);
      expect(controller.value.successfulFiles, 0);
    });
  });

  group('Part 4 widgets and lifecycle', () {
    testWidgets('progress fits narrow screens with large system text', (
      tester,
    ) async {
      final p = ProgressProbe(sizes: <int>[10, 20])..start();
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransferProgressPanel(
                controller: p.controller,
                onCancel: () => p.controller.requestCancellation(p.epoch),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('File 1 of 2'), findsOneWidget);
    });
    testWidgets(
      '27 disposing progress widget detaches without owning the engine',
      (tester) async {
        final p = ProgressProbe()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TransferProgressPanel(controller: p.controller),
              ),
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        p.step(TransferPhase.sending, bytes: 10, fileBytes: 10);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(p.state.batchBytes, 10);
      },
    );
    testWidgets('28 backgrounding Nearby cancels its real sender interface', (
      tester,
    ) async {
      final sender = ControlledSender();
      await mountSender(tester, sender);
      expect(find.text('Waiting for approval'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(sender.cancellations, greaterThan(0));
      expect(find.text('Cancelled'), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Delivery confirmed'), findsNothing);
    });
    testWidgets('disposing Nearby cancels work and ignores late callbacks', (
      tester,
    ) async {
      final sender = ControlledSender();
      await mountSender(tester, sender);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sender.emit(TransferPhase.sending);
      await tester.pump();
      expect(sender.cancellations, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'a confirmed sender result retains the existing delivery receipt UI',
      (tester) async {
        final sender = ControlledSender();
        await mountSender(tester, sender);
        sender.confirm();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('transfer-result-panel')),
          findsOneWidget,
        );
        expect(find.text('Successful files: 1'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Delivery confirmed'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Delivery confirmed'), findsOneWidget);
      },
    );
    testWidgets(
      'receiver result opens the existing HistoryScreen instead of a second database',
      (tester) async {
        final p = ProgressProbe(role: TransferRole.receiver)
          ..start()
          ..finishBytes();
        p.step(TransferPhase.completed, receipt: p.receipt());
        final root = await tester.runAsync(
          () => Directory.systemTemp.createTemp('part4-history-ui-'),
        );
        addTearDown(() async {
          await root!.delete(recursive: true);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: SingleChildScrollView(
                  child: TransferResultPanel(
                    activity: p.state,
                    onDone: () => Navigator.pop(context),
                    onViewSavedFiles: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => HistoryScreen(
                          service: baseline.FakeHistoryService(
                            HistorySnapshot(transfers: []),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('result-view-saved-files'),
        );
        expect(find.byKey(const ValueKey('history-scaffold')), findsOneWidget);
      },
    );
    testWidgets(
      'safe retry is explicit and does not discard selected originals',
      (tester) async {
        final sender = ControlledSender();
        await mountSender(tester, sender);
        sender.fail();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('retry-uncommitted-transfer')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('retry-uncommitted-transfer'),
        );
        expect(find.text('Retry the uncommitted batch?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(sender.sequence, 2);
      },
    );
    testWidgets(
      'uncertain result never offers automatic retry or invented counts',
      (tester) async {
        final p = ProgressProbe()
          ..start()
          ..finishBytes();
        p.step(TransferPhase.verifying, commit: true);
        p.controller.finishFailure(
          p.epoch,
          const TransferException(
            'Receipt unavailable.',
            outcomeUncertain: true,
          ),
        );
        p.controller.settle(p.epoch);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TransferResultPanel(
                  activity: p.state,
                  onDone: () {},
                  onRetry: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('Successful files: Unknown'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('retry-uncommitted-transfer')),
          findsNothing,
        );
      },
    );
  });
}

DateTime get coinFixtureTime => DateTime.utc(2026, 9, 8, 12);

ShareCoinBalance coinFixtureBalance({
  String user = 'user-1',
  int available = 10000,
  int pending = 200,
}) => ShareCoinBalance(
  userId: user,
  available: available,
  pending: pending,
  lifetimeEarned: 12000,
  lifetimeWithdrawn: 1000,
  lifetimeSpent: 800,
  updatedAt: coinFixtureTime,
  version: 'wallet-v1',
);

ShareCoinUser coinFixtureUser({
  String id = 'user-1',
  AccountStatus status = AccountStatus.active,
}) => ShareCoinUser(
  userId: id,
  displayName: 'Test account',
  username: 'test_user',
  status: status,
  createdAt: coinFixtureTime.subtract(const Duration(days: 20)),
  lastActiveAt: coinFixtureTime,
  version: 'user-v1',
  referralCode: 'REF-TEST',
  features: const {'rewards': true},
);

CoinConversionRate coinFixtureRate() =>
    CoinConversionRate(coinUnits: 1000, minorUnits: 100, currency: 'BDT');
WithdrawalPolicy coinFixturePolicy({
  String user = 'user-1',
  List<String> active = const [],
  bool connected = true,
}) => WithdrawalPolicy(
  userId: user,
  version: 'policy-v1',
  minimumCoins: 1000,
  rate: coinFixtureRate(),
  methods: <PayoutMethodConfig>[
    PayoutMethodConfig(
      method: PayoutMethod.bkash,
      enabled: true,
      providerConnected: connected,
      feeMinor: 10,
      destinationReference: 'destination-1',
      maskedDestination: '****1234',
    ),
  ],
  activeRequestIds: active,
);

WithdrawalIntent coinFixtureIntent({
  String user = 'user-1',
  int coins = 1000,
  String key = 'withdraw-key-1',
}) => WithdrawalIntent(
  userId: user,
  coins: coins,
  method: PayoutMethod.bkash,
  destinationReference: 'destination-1',
  policyVersion: 'policy-v1',
  expectedFeeMinor: 10,
  expectedFinalMinor: coinFixtureRate().grossMinor(coins) - 10,
  idempotencyKey: key,
);

WithdrawalRequest coinFixtureWithdrawal({
  String user = 'user-1',
  String key = 'withdraw-key-1',
  int coins = 1000,
  WithdrawalStatus status = WithdrawalStatus.requested,
}) => WithdrawalRequest(
  withdrawalId: 'withdrawal-1',
  userId: user,
  requestedCoins: coins,
  rate: coinFixtureRate(),
  feeMinor: 10,
  finalPayoutMinor: coinFixtureRate().grossMinor(coins) - 10,
  method: PayoutMethod.bkash,
  maskedDestination: '****1234',
  status: status,
  requestedAt: coinFixtureTime,
  updatedAt: coinFixtureTime.add(const Duration(minutes: 2)),
  idempotencyKey: key,
  serverReference: status == WithdrawalStatus.paid
      ? 'provider-reference-1'
      : null,
  rejectionReason: status == WithdrawalStatus.rejected
      ? 'Provider rejected this test request.'
      : null,
);

RewardEvent coinFixtureReward({
  String event = 'event-1',
  String key = 'reward-key-1',
  String providerEvent = 'provider-event-1',
  int coins = 250,
  String user = 'user-1',
  RewardEventStatus status = RewardEventStatus.created,
}) => RewardEvent(
  eventId: event,
  userId: user,
  source: CoinSource.adReward,
  provider: 'test-provider',
  providerEventId: providerEvent,
  targetId: 'placement-1',
  requestedCoins: coins,
  occurredAt: coinFixtureTime,
  status: status,
  idempotencyKey: key,
  transactionId: status == RewardEventStatus.approved
      ? 'reward-transaction-1'
      : null,
  metadata: const {'placement': 'test-placement'},
);

Offer coinFixtureOffer({
  String id = 'offer-1',
  OfferStatus status = OfferStatus.available,
  bool expired = false,
}) => Offer(
  offerId: id,
  title: 'Test offer',
  shortDescription: 'Lightweight test data',
  description: 'This is not a production advertiser offer.',
  publisher: 'Test publisher',
  category: OfferCategory.education,
  rewardCoins: 250,
  estimatedMinutes: 10,
  platforms: const [OfferPlatform.android, OfferPlatform.ios],
  countries: const ['BD'],
  status: status,
  startsAt: coinFixtureTime.subtract(const Duration(days: 1)),
  expiresAt: expired
      ? coinFixtureTime.subtract(const Duration(hours: 1))
      : coinFixtureTime.add(const Duration(days: 2)),
  provider: 'test-provider',
  iconUrl: Uri.parse('https://assets.example.org/icon.png'),
  instructions: const ['Complete the provider task.'],
  terms: const ['Backend verification required.'],
  rewardTransactionId: status == OfferStatus.completed
      ? 'offer-transaction-1'
      : null,
);

ShareCoinTransaction coinFixtureTransaction({
  CoinSource source = CoinSource.adReward,
  CoinDirection direction = CoinDirection.credit,
  CoinTransactionStatus status = CoinTransactionStatus.completed,
}) => ShareCoinTransaction(
  transactionId: 'transaction-1',
  userId: 'user-1',
  amount: 250,
  direction: direction,
  source: source,
  status: status,
  description: 'A test ledger record.',
  createdAt: coinFixtureTime,
  completedAt: status == CoinTransactionStatus.completed
      ? coinFixtureTime
      : null,
  referenceId: 'reference-1',
  idempotencyKey: 'transaction-key-1',
);

Promotion coinFixturePromotion() => Promotion(
  campaignId: 'campaign-1',
  title: 'Test campaign',
  description: 'Test data only.',
  advertiser: 'Test advertiser',
  cta: 'View campaign',
  rewardCoins: 100,
  startsAt: coinFixtureTime.subtract(const Duration(days: 1)),
  endsAt: coinFixtureTime.add(const Duration(days: 1)),
  status: PromotionStatus.active,
  trackingId: 'tracking-1',
);

class TestShareCoinBackend implements ShareCoinBackend {
  TestShareCoinBackend()
    : _scope = AccountScope(userId: 'user-1', sessionId: 'session-1');
  final StreamController<AccountScope?> events =
      StreamController<AccountScope?>.broadcast();
  final Map<ShareCoinOperation, int> calls = <ShareCoinOperation, int>{};
  AccountScope? _scope;
  CoinServiceState serviceState = CoinServiceState.reachable;
  AccountStatus accountStatus = AccountStatus.active;
  int balance = 10000;
  List<String> activeWithdrawals = <String>[];
  bool expiredOffer = false;
  Future<Map<String, dynamic>> Function(
    ShareCoinOperation,
    AccountScope,
    Map<String, Object?>,
  )?
  handler;
  @override
  bool get configured => true;
  @override
  AccountScope? get scope => _scope;
  @override
  Stream<AccountScope?> get accountChanges => events.stream;
  @override
  Future<CoinServiceState> checkService() async => serviceState;
  void switchAccount(AccountScope? value) {
    _scope = value;
    events.add(value);
  }

  Future<void> close() => events.close();
  Map<String, dynamic> envelope(
    AccountScope owner,
    Map<String, Object?> data,
  ) => <String, dynamic>{
    'userId': owner.userId,
    'serverTime': coinFixtureTime.toIso8601String(),
    'version': 'reply-v1',
    'data': data,
  };
  Map<String, Object?> page(
    List<Map<String, Object?>> items,
    Map<String, Object?> args,
  ) => <String, Object?>{
    'items': items,
    'page': PageInfo(
      page: args['page'] as int,
      pageSize: args['pageSize'] as int,
      total: items.length,
      hasNext: false,
    ).toJson(),
  };
  Map<String, Object?> dataFor(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> args,
  ) => switch (operation) {
    ShareCoinOperation.currentUser => coinFixtureUser(
      id: owner.userId,
      status: accountStatus,
    ).toJson(),
    ShareCoinOperation.wallet => coinFixtureBalance(
      user: owner.userId,
      available: balance,
    ).toJson(),
    ShareCoinOperation.transactions => page([
      coinFixtureTransaction(
        status: CoinTransactionStatus.reversed,
        source: CoinSource.reversal,
        direction: CoinDirection.debit,
      ).toJson(),
    ], args),
    ShareCoinOperation.submitReward => Map<String, Object?>.from(
      args,
    )..['status'] = RewardEventStatus.pending.name,
    ShareCoinOperation.rewardStatus => coinFixtureReward(
      event: args['eventId'] as String,
      user: owner.userId,
      status: RewardEventStatus.pending,
    ).toJson(),
    ShareCoinOperation.rewardHistory => page([
      coinFixtureReward(
        user: owner.userId,
        status: RewardEventStatus.pending,
      ).toJson(),
    ], args),
    ShareCoinOperation.offers => page([coinFixtureOffer().toJson()], args),
    ShareCoinOperation.offer ||
    ShareCoinOperation.offerStatus => coinFixtureOffer(
      id: args['offerId'] as String,
      expired: expiredOffer,
    ).toJson(),
    ShareCoinOperation.startOffer => OfferStart(
      startId: 'start-1',
      offerId: args['offerId'] as String,
      userId: owner.userId,
      idempotencyKey: args['idempotencyKey'] as String,
      status: OfferStatus.started,
      updatedAt: coinFixtureTime,
    ).toJson(),
    ShareCoinOperation.promotions => page([
      coinFixturePromotion().toJson(),
    ], args),
    ShareCoinOperation.withdrawalPolicy => coinFixturePolicy(
      user: owner.userId,
      active: activeWithdrawals,
    ).toJson(),
    ShareCoinOperation.requestWithdrawal => coinFixtureWithdrawal(
      user: owner.userId,
      key: args['idempotencyKey'] as String,
      coins: args['coins'] as int,
    ).toJson(),
    ShareCoinOperation.withdrawals => page([], args),
    ShareCoinOperation.withdrawalStatus => coinFixtureWithdrawal(
      user: owner.userId,
      status: WithdrawalStatus.paid,
    ).toJson(),
    ShareCoinOperation.withdrawalByKey => coinFixtureWithdrawal(
      user: owner.userId,
      key: args['idempotencyKey'] as String,
      status: WithdrawalStatus.paid,
    ).toJson(),
    ShareCoinOperation.referral => ReferralSummary(
      userId: owner.userId,
      referralCode: 'REF-TEST',
      invitedCount: 3,
      pendingCount: 1,
      qualifiedCount: 1,
      earnedCoins: 100,
      status: ReferralStatus.active,
      referralUrl: Uri.parse('https://example.org/referral/REF-TEST'),
      updatedAt: coinFixtureTime,
    ).toJson(),
    ShareCoinOperation.adsConfiguration => AdConfiguration.disabled().toJson(),
    ShareCoinOperation.dailyConfiguration => DailyRewardConfiguration(
      dayRewards: const [1, 2, 3, 4, 5, 6, 7],
      streakDay: 3,
      eligible: false,
      nextEligibleAt: coinFixtureTime.add(const Duration(days: 1)),
      version: 'daily-v1',
    ).toJson(),
  };
  @override
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> arguments,
  ) async {
    calls[operation] = (calls[operation] ?? 0) + 1;
    final custom = handler;
    if (custom != null) return custom(operation, owner, arguments);
    return envelope(owner, dataFor(operation, owner, arguments));
  }
}

class CoinServiceFixture {
  CoinServiceFixture() {
    connectivity = ConnectivityService(
      localProbe: () async => <String>['192.168.5.2'],
      internetProbe: () async => internet,
      serviceProbe: backend.checkService,
    );
    service = ShareCoinService(backend: backend, connectivity: connectivity);
    addTearDown(() async {
      service.dispose();
      connectivity.dispose();
      await backend.close();
    });
  }
  final TestShareCoinBackend backend = TestShareCoinBackend();
  InternetState internet = InternetState.available;
  late final ConnectivityService connectivity;
  late final ShareCoinService service;
  void goOffline() {
    internet = InternetState.offline;
    backend.serviceState = CoinServiceState.unreachable;
  }
}

Matcher coinError(CoinErrorCode code) =>
    isA<ShareCoinException>().having((error) => error.code, 'code', code);

Future<void> mountCoinDashboard(
  WidgetTester tester,
  ShareCoinService service, {
  ValueChanged<ShareCoinFileAction>? action,
  Size size = const Size(390, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ShareCoinHomeScreen(service: service, onFileAction: action),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapCoinKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void registerPart5Tests() {
  group('Part 5 immutable domain', () {
    test('01 wallet serialization preserves all server fields', () {
      final wallet = coinFixtureBalance();
      expect(
        ShareCoinBalance.fromJson(wallet.toJson()).toJson(),
        wallet.toJson(),
      );
    });
    test('02 wallet rejects negative non-integer and overflowing values', () {
      for (final value in <Object>[
        -1,
        1.5,
        double.nan,
        double.infinity,
        maxShareCoinInteger + 1,
        '1000',
      ]) {
        final json = coinFixtureBalance().toJson()..['available'] = value;
        expect(
          () => ShareCoinBalance.fromJson(json),
          throwsA(isA<CoinModelException>()),
        );
      }
      expect(
        () => coinFixtureBalance(available: maxShareCoinInteger, pending: 1),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('03 transaction round trip', () {
      final transaction = coinFixtureTransaction();
      expect(
        ShareCoinTransaction.fromJson(transaction.toJson()).toJson(),
        transaction.toJson(),
      );
    });
    test(
      '04 direction produces signed display without negative stored amounts',
      () {
        expect(coinFixtureTransaction().signedAmount, '+250 ShareCoin');
        expect(
          coinFixtureTransaction(direction: CoinDirection.debit).signedAmount,
          '-250 ShareCoin',
        );
      },
    );
    test(
      '05 every ledger status including rejected and reversed is preserved',
      () {
        for (final status in CoinTransactionStatus.values) {
          expect(
            ShareCoinTransaction.fromJson(
              coinFixtureTransaction(status: status).toJson(),
            ).status,
            status,
          );
        }
      },
    );
    test('06 unsafe transaction IDs and unknown statuses are rejected', () {
      for (final entry in <MapEntry<String, Object>>[
        const MapEntry('transactionId', '../escape'),
        const MapEntry('status', 'creditedLocally'),
      ]) {
        final json = coinFixtureTransaction().toJson()
          ..[entry.key] = entry.value;
        expect(
          () => ShareCoinTransaction.fromJson(json),
          throwsA(isA<CoinModelException>()),
        );
      }
    });
    test('07 reward claims cannot use withdrawal/admin sources or malformed timestamps', () {
      final json = coinFixtureReward().toJson()
        ..['source'] = CoinSource.administrativeAdjustment.name;
      expect(
        () => RewardEvent.fromJson(json),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime('2026-02-31T12:00:00Z', 'date'),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime('2026-09-08T12:00:00', 'date'),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime(DateTime.utc(2500), 'date'),
        throwsA(isA<CoinModelException>()),
      );
    });
    test(
      '10 withdrawal JSON validates rational quote and masked destination',
      () {
        final request = coinFixtureWithdrawal();
        expect(
          WithdrawalRequest.fromJson(request.toJson()).toJson(),
          request.toJson(),
        );
        final bad = request.toJson()..['finalPayoutMinor'] = 999;
        expect(
          () => WithdrawalRequest.fromJson(bad),
          throwsA(isA<CoinModelException>()),
        );
        bad['finalPayoutMinor'] = 90;
        bad['maskedDestination'] = '01712345678';
        expect(
          () => WithdrawalRequest.fromJson(bad),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test(
      '14 payout polling may skip forward but cannot reverse terminal states',
      () {
        expect(
          coinFixtureWithdrawal().canTransitionTo(WithdrawalStatus.paid),
          isTrue,
        );
        expect(
          coinFixtureWithdrawal(status: WithdrawalStatus.paid)
              .canTransitionTo(WithdrawalStatus.processing),
          isFalse,
        );
        expect(
          coinFixtureWithdrawal(status: WithdrawalStatus.rejected)
              .canTransitionTo(WithdrawalStatus.paid),
          isFalse,
        );
      },
    );
    test('15 user serialization contains no credential fields', () {
      final user = coinFixtureUser();
      expect(ShareCoinUser.fromJson(user.toJson()).toJson(), user.toJson());
      expect(user.toJson().keys, isNot(contains('password')));
      expect(user.toJson().keys, isNot(contains('accessToken')));
      expect(() => user.features['other'] = true, throwsUnsupportedError);
    });
    test('16 only active accounts may request rewards', () {
      for (final status in AccountStatus.values) {
        expect(
          coinFixtureUser(status: status).mayRequestRewards,
          status == AccountStatus.active,
        );
      }
    });
    test('17 referral counts and earned coins are validated', () {
      final record = ReferralSummary(
        userId: 'u1',
        referralCode: 'R123',
        invitedCount: 4,
        pendingCount: 1,
        qualifiedCount: 2,
        earnedCoins: 100,
        status: ReferralStatus.active,
        updatedAt: coinFixtureTime,
      );
      expect(
        ReferralSummary.fromJson(record.toJson()).toJson(),
        record.toJson(),
      );
      expect(
        () => ReferralSummary(
          userId: 'u1',
          referralCode: 'R123',
          invitedCount: 1,
          pendingCount: 1,
          qualifiedCount: 2,
          earnedCoins: 100,
          status: ReferralStatus.active,
          updatedAt: coinFixtureTime,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test(
      '18 offer model freezes arrays and keeps country/platform availability',
      () {
        final offer = coinFixtureOffer();
        expect(Offer.fromJson(offer.toJson()).toJson(), offer.toJson());
        expect(offer.countries, <String>['BD']);
        expect(() => offer.countries.add('US'), throwsUnsupportedError);
        final bad = offer.toJson()
          ..['destinationUrl'] = 'http://example.org/app';
        expect(() => Offer.fromJson(bad), throwsA(isA<CoinModelException>()));
      },
    );
    test('19 completed offer needs a transaction reference and expiry uses supplied server time', () {
      for (final status in OfferStatus.values) {
        expect(
          Offer.fromJson(coinFixtureOffer(status: status).toJson()).status,
          status,
        );
      }
      final bad = coinFixtureOffer(status: OfferStatus.completed).toJson()
        ..['rewardTransactionId'] = null;
      expect(() => Offer.fromJson(bad), throwsA(isA<CoinModelException>()));
      expect(
        coinFixtureOffer(expired: true).availableAt(coinFixtureTime),
        isFalse,
      );
      expect(coinFixtureOffer().availableAt(coinFixtureTime), isTrue);
    });
    test(
      '20 pagination is scalable and rejects duplicate IDs or overfull pages',
      () {
        final info = PageInfo(
          page: 1,
          pageSize: 20,
          total: 1000,
          hasNext: true,
          nextCursor: 'next-token',
        );
        expect(PageInfo.fromJson(info.toJson()).total, 1000);
        final item = coinFixtureOffer();
        expect(
          () => CoinPage<Offer>(
            items: [item, item],
            info: info,
            id: (offer) => offer.offerId,
          ),
          throwsA(isA<CoinModelException>()),
        );
        expect(
          () => PageInfo(page: 1, pageSize: 101, total: 1000, hasNext: true),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('21 promotion expiry never implies coin credit', () {
      final item = coinFixturePromotion();
      expect(Promotion.fromJson(item.toJson()).toJson(), item.toJson());
      expect(item.availableAt(item.endsAt), isFalse);
      expect(item.availableAt(coinFixtureTime), isTrue);
    });
    test(
      '22 ad configuration starts disabled and validates SDK-free policy',
      () {
        final config = AdConfiguration.disabled();
        expect(config.adsAllowed, isFalse);
        expect(config.units, isEmpty);
        expect(
          AdConfiguration.fromJson(config.toJson()).toJson(),
          config.toJson(),
        );
        expect(
          () => AdConfiguration(
            rewardedEnabled: true,
            bannerEnabled: false,
            interstitialEnabled: false,
            cooldownSeconds: 30,
            dailyLimit: 5,
            premium: false,
          ),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('29 negative and overflow reward amounts cannot become claims', () {
      for (final amount in <int>[-1, 0, maxShareCoinInteger + 1]) {
        expect(
          () => coinFixtureReward(coins: amount),
          throwsA(isA<CoinModelException>()),
        );
      }
      expect(
        () => CoinConversionRate(
          coinUnits: 1,
          minorUnits: maxShareCoinInteger,
          currency: 'BDT',
        ).grossMinor(2),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        CoinConversionRate(
          coinUnits: 3,
          minorUnits: 2,
          currency: 'BDT',
        ).grossMinor(4),
        2,
      );
    });
    test(
      'metadata whitelist refuses credentials and mutable nested values',
      () {
        expect(
          () => coinMetadata({'accessToken': 'secret'}),
          throwsA(isA<CoinModelException>()),
        );
        expect(
          () => coinMetadata({
            'placement': {'secret': 'value'},
          }),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('daily configuration uses a backend-provided seven-day policy', () {
      final config = DailyRewardConfiguration(
        dayRewards: const [1, 2, 3, 4, 5, 6, 7],
        streakDay: 2,
        eligible: false,
        nextEligibleAt: coinFixtureTime,
        version: 'daily-v1',
      );
      expect(
        DailyRewardConfiguration.fromJson(config.toJson()).eligible,
        isFalse,
      );
      expect(() => config.dayRewards.add(1000), throwsUnsupportedError);
    });
  });

  group('Part 5 server-authoritative service', () {
    test('08 duplicate reward submissions share one backend event', () async {
      final f = CoinServiceFixture();
      final event = coinFixtureReward();
      final results = await Future.wait([
        f.service.submitRewardEvent(event),
        f.service.submitRewardEvent(event),
      ]);
      expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      expect(
        results.every(
          (result) => result.data.status == RewardEventStatus.pending,
        ),
        isTrue,
      );
    });
    test('09 repeated provider callback with new client IDs does not produce another reward', () async {
      final f = CoinServiceFixture();
      await f.service.submitRewardEvent(coinFixtureReward());
      final result = await f.service.submitRewardEvent(
        coinFixtureReward(event: 'event-2', key: 'key-2'),
      );
      expect(result.data.eventId, 'event-1');
      expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward(coins: 999)),
        throwsA(coinError(CoinErrorCode.conflict)),
      );
    });
    test(
      '11 minimum withdrawal is checked without a backend debit request',
      () async {
        final f = CoinServiceFixture();
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(coins: 500)),
          throwsA(coinError(CoinErrorCode.minimum)),
        );
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
        expect((await f.service.getCurrentWallet()).data.available, 10000);
      },
    );
    test('12 insufficient funds does not locally subtract a balance', () async {
      final f = CoinServiceFixture();
      await expectLater(
        f.service.requestWithdrawal(coinFixtureIntent(coins: 11000)),
        throwsA(coinError(CoinErrorCode.insufficientBalance)),
      );
      expect(f.backend.balance, 10000);
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      '13 withdrawal idempotency and conflicting requests are protected',
      () async {
        final f = CoinServiceFixture();
        final intent = coinFixtureIntent();
        final results = await Future.wait([
          f.service.requestWithdrawal(intent),
          f.service.requestWithdrawal(intent),
        ]);
        expect(results.first.data.status, WithdrawalStatus.requested);
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(key: 'another-key')),
          throwsA(coinError(CoinErrorCode.conflict)),
        );
        expect((await f.service.getCurrentWallet()).data.available, 10000);
      },
    );
    test('23 offline wallet is explicitly cached, never invented', () async {
      final f = CoinServiceFixture();
      final online = await f.service.getCurrentWallet();
      expect(online.cached, isFalse);
      f.goOffline();
      final cached = await f.service.getCurrentWallet();
      expect(cached.cached, isTrue);
      expect(cached.data.available, online.data.available);
      await expectLater(
        f.service.getCurrentWallet(allowCached: false),
        throwsA(coinError(CoinErrorCode.offline)),
      );
    });
    test(
      '27 safe backend error mapping does not expose raw provider errors',
      () {
        expect(
          ShareCoinException.fromServerCode('insufficient_balance').code,
          CoinErrorCode.insufficientBalance,
        );
        expect(
          ShareCoinException.fromServerCode('raw-private-stack').message,
          isNot(contains('raw-private-stack')),
        );
      },
    );
    test(
      '28 malformed or cross-account backend payloads are not wallet balances',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async => f.backend.envelope(
          scope,
          coinFixtureBalance(user: 'another-user').toJson(),
        );
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.malformed)),
        );
        expect(f.service.cachedWallet, isNull);
      },
    );
    test('30 backend pending rewards never add local coins', () async {
      final f = CoinServiceFixture();
      final before = (await f.service.getCurrentWallet()).data.available;
      final result = await f.service.submitRewardEvent(coinFixtureReward());
      expect(result.data.status, RewardEventStatus.pending);
      expect((await f.service.getCurrentWallet()).data.available, before);
    });
    test(
      'client cannot submit an already-approved reward as evidence',
      () async {
        final f = CoinServiceFixture();
        await expectLater(
          f.service.submitRewardEvent(
            coinFixtureReward(status: RewardEventStatus.approved),
          ),
          throwsA(coinError(CoinErrorCode.invalidRequest)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test(
      'unconfigured backend and missing account are honest unavailable states',
      () async {
        final empty = ShareCoinService();
        addTearDown(empty.dispose);
        await expectLater(
          empty.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.notConfigured)),
        );
        expect(empty.cachedWallet, isNull);
        final f = CoinServiceFixture();
        f.backend.switchAccount(null);
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.unauthenticated)),
        );
      },
    );
    test('restricted accounts cannot submit claims', () async {
      final f = CoinServiceFixture();
      f.backend.accountStatus = AccountStatus.suspended;
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward()),
        throwsA(coinError(CoinErrorCode.restricted)),
      );
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      'offline reward claims are not queued as money or sent to backend',
      () async {
        final f = CoinServiceFixture()..goOffline();
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.offline)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        f.internet = InternetState.available;
        f.backend.serviceState = CoinServiceState.reachable;
        await f.service.submitRewardEvent(coinFixtureReward());
        expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      },
    );
    test(
      'offer starts are idempotent and cannot become completed rewards',
      () async {
        final f = CoinServiceFixture();
        final results = await Future.wait([
          f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
          f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
        ]);
        expect(results.first.data.status, OfferStatus.started);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test('expired offers are rejected using backend response time', () async {
      final f = CoinServiceFixture();
      f.backend.expiredOffer = true;
      await expectLater(
        f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
        throwsA(coinError(CoinErrorCode.invalidRequest)),
      );
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
    });
    test('server policy blocks an already-active withdrawal', () async {
      final f = CoinServiceFixture();
      f.backend.activeWithdrawals = ['other-request'];
      await expectLater(
        f.service.requestWithdrawal(coinFixtureIntent()),
        throwsA(coinError(CoinErrorCode.conflict)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test('changed quote is not silently accepted', () async {
      final f = CoinServiceFixture();
      final json = coinFixtureIntent().toJson()..['expectedFeeMinor'] = 11;
      await expectLater(
        f.service.requestWithdrawal(WithdrawalIntent.fromJson(json)),
        throwsA(coinError(CoinErrorCode.policyChanged)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      'uncertain withdrawal keeps its key and prevents blind replay',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.requestWithdrawal) {
            throw TimeoutException('test transport timeout');
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(key: 'new-key')),
          throwsA(coinError(CoinErrorCode.conflict)),
        );
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        final status = await f.service.getWithdrawalByKey('withdraw-key-1');
        expect(status.data.status, WithdrawalStatus.paid);
        expect(f.service.hasPendingWithdrawal, isFalse);
      },
    );
    test(
      'malformed write confirmation is uncertain, not a refund or payout',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.submitReward) {
            return f.backend.envelope(scope, {'invalid': true});
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        expect(f.backend.balance, 10000);
      },
    );
    test(
      'account switch hides cached wallet and rejects late results',
      () async {
        final f = CoinServiceFixture();
        final pending = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.wallet) {
            started.complete();
            return pending.future;
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        final oldScope = f.backend.scope!;
        final request = f.service.getCurrentWallet();
        final expectation = expectLater(
          request,
          throwsA(coinError(CoinErrorCode.accountChanged)),
        );
        await started.future;
        f.backend.switchAccount(
          AccountScope(userId: 'user-2', sessionId: 'session-2'),
        );
        pending.complete(
          f.backend.envelope(oldScope, coinFixtureBalance().toJson()),
        );
        await expectation;
        expect(f.service.cachedWallet, isNull);
      },
    );
    test(
      'status and cache reads cannot invent local approval or transactions',
      () async {
        final f = CoinServiceFixture();
        final history = await f.service.getTransactionHistory();
        expect(
          history.data.items.single.status,
          CoinTransactionStatus.reversed,
        );
        final daily = await f.service.getDailyRewardConfiguration();
        expect(daily.data.eligible, isFalse);
        final offers = await f.service.getOffers();
        f.goOffline();
        final cached = await f.service.getOffers();
        expect(cached.cached, isTrue);
        expect(
          cached.data.items.single.offerId,
          offers.data.items.single.offerId,
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test('pagination metadata must agree with the request size', () async {
      final f = CoinServiceFixture();
      f.backend.handler = (op, scope, args) async {
        final data = f.backend.dataFor(op, scope, args);
        if (op == ShareCoinOperation.offers) {
          data['page'] = PageInfo(
            page: 1,
            pageSize: 100,
            total: 1,
            hasNext: false,
          ).toJson();
        }
        return f.backend.envelope(scope, data);
      };
      await expectLater(
        f.service.getOffers(query: OfferQuery(pageSize: 20)),
        throwsA(coinError(CoinErrorCode.malformed)),
      );
    });
    test(
      'suspension before provider submission prevents a background mutation',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.currentUser) f.service.suspend();
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.offline)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
  });

  group('Part 5 late-response safeguards', () {
    test('a pre-mutation wallet response cannot become a fresh post-mutation balance', () async {
      final f = CoinServiceFixture();
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      f.backend.handler = (op, scope, args) async {
        if (op == ShareCoinOperation.wallet) {
          started.complete();
          return pending.future;
        }
        return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
      };
      final wallet = f.service.getCurrentWallet(allowCached: false);
      final rejected = expectLater(
        wallet,
        throwsA(coinError(CoinErrorCode.unavailable)),
      );
      await started.future;
      await f.service.submitRewardEvent(coinFixtureReward());
      pending.complete(
        f.backend.envelope(f.backend.scope!, coinFixtureBalance().toJson()),
      );
      await rejected;
      expect(f.service.cachedWallet, isNull);
    });
    test('an account change during mutation notification cannot post for the old user', () async {
      final f = CoinServiceFixture();
      var switched = false;
      f.service.addListener(() {
        if (!switched) {
          switched = true;
          f.backend.switchAccount(
            AccountScope(userId: 'user-2', sessionId: 'session-2'),
          );
        }
      });
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward()),
        throwsA(coinError(CoinErrorCode.uncertain)),
      );
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    testWidgets(
      'uncertain withdrawal UI checks its original key without a second submission',
      (tester) async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.requestWithdrawal) {
            throw TimeoutException('test timeout');
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await mountCoinDashboard(tester, f.service);
        await tapCoinKey(tester, 'coin-withdraw');
        await tester.tap(find.byKey(const ValueKey('submit-coin-withdrawal')));
        await tester.pumpAndSettle();
        expect(find.text('Check request status'), findsOneWidget);
        final submit = tester.widget<FilledButton>(
          find.byKey(const ValueKey('submit-coin-withdrawal')),
        );
        expect(submit.onPressed, isNull);
        await tester.tap(
          find.byKey(const ValueKey('check-coin-withdrawal-status')),
        );
        await tester.pumpAndSettle();
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        expect(find.textContaining('Backend status: paid'), findsOneWidget);
      },
    );
  });

  group('Part 5 connectivity', () {
    test('24 initial state does not assume internet or a backend', () {
      final service = ConnectivityService(localProbe: () async => []);
      addTearDown(service.dispose);
      expect(service.value.internet, InternetState.unknown);
      expect(service.value.shareCoin, CoinServiceState.unconfigured);
    });
    test('25 local IPv4 and offline internet are independent', () async {
      final service = ConnectivityService(
        localProbe: () async => ['192.168.2.2', '8.8.8.8'],
        internetProbe: () async => InternetState.offline,
        serviceProbe: () async => CoinServiceState.unreachable,
      );
      addTearDown(service.dispose);
      final state = await service.refresh();
      expect(state.hasLocalCandidate, isTrue);
      expect(state.internet, InternetState.offline);
      expect(state.canRequestRewards, isFalse);
      expect(state.localAddresses, ['192.168.2.2']);
    });
    test(
      '26 disposal ignores late probes without publishing new state',
      () async {
        final probe = Completer<List<String>>();
        final service = ConnectivityService(localProbe: () => probe.future);
        var calls = 0;
        service.addListener(() => calls += 1);
        final request = service.refresh();
        final before = calls;
        service.dispose();
        probe.complete(['192.168.2.2']);
        await request;
        expect(calls, before);
      },
    );
    test('simultaneous refreshes use one set of probes', () async {
      final probe = Completer<List<String>>();
      var calls = 0;
      final service = ConnectivityService(
        localProbe: () {
          calls += 1;
          return probe.future;
        },
      );
      addTearDown(service.dispose);
      final first = service.refresh();
      final second = service.refresh();
      expect(identical(first, second), isTrue);
      probe.complete(['192.168.2.2']);
      await Future.wait([first, second]);
      expect(calls, 1);
    });
    test(
      'suspended old checks cannot overwrite a newer resumed check',
      () async {
        final old = Completer<List<String>>();
        var calls = 0;
        final service = ConnectivityService(
          localProbe: () =>
              ++calls == 1 ? old.future : Future.value(['10.0.0.2']),
        );
        addTearDown(service.dispose);
        final previous = service.refresh();
        service.suspend();
        service.resume();
        await service.refresh();
        old.complete(['192.168.1.2']);
        await previous;
        expect(service.value.localAddresses, ['10.0.0.2']);
      },
    );
    test(
      'probe failure is limited/error, not a fabricated reachable service',
      () async {
        final service = ConnectivityService(
          localProbe: () async => throw StateError('test failure'),
          internetProbe: () async => throw TimeoutException('test'),
          serviceProbe: () async => CoinServiceState.limited,
        );
        addTearDown(service.dispose);
        final state = await service.refresh();
        expect(state.localNetwork, LocalNetworkState.error);
        expect(state.internet, InternetState.error);
        expect(state.shareCoin, CoinServiceState.limited);
        expect(state.canRequestRewards, isFalse);
      },
    );
    test('a listener may dispose connectivity during publication', () async {
      final service = ConnectivityService(localProbe: () async => []);
      service.addListener(service.dispose);
      await service.refresh();
      expect(await service.changes.isEmpty, isTrue);
    });
  });

  group('Part 5 dashboard and navigation', () {
    testWidgets('new local user sees setup and no invented zero balance', (
      tester,
    ) async {
      final connection = ConnectivityService(localProbe: () async => []);
      final service = ShareCoinService(connectivity: connection);
      addTearDown(service.dispose);
      addTearDown(connection.dispose);
      await mountCoinDashboard(tester, service);
      expect(find.text('Wallet unavailable'), findsOneWidget);
      expect(find.textContaining('Account setup required'), findsOneWidget);
      expect(find.text('0 ShareCoin'), findsNothing);
      await tapCoinKey(tester, 'coin-withdraw');
      expect(find.text('Withdrawals unavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('submit-coin-withdrawal')),
        findsNothing,
      );
    });
    testWidgets('validated wallet and offline cache labels are distinct', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      await mountCoinDashboard(tester, f.service);
      expect(find.text('10,000 ShareCoin'), findsOneWidget);
      f.goOffline();
      await tester.tap(find.byKey(const ValueKey('refresh-share-coin')));
      await tester.pumpAndSettle();
      expect(find.textContaining('CACHED'), findsOneWidget);
      expect(find.text('10,000 ShareCoin'), findsOneWidget);
    });
    testWidgets('file actions remain enabled while reward service is offline', (
      tester,
    ) async {
      final f = CoinServiceFixture()..goOffline();
      ShareCoinFileAction? action;
      await mountCoinDashboard(
        tester,
        f.service,
        action: (value) => action = value,
      );
      await tapCoinKey(tester, 'coin-send-files');
      expect(action, ShareCoinFileAction.send);
      await tapCoinKey(tester, 'coin-receive-files');
      expect(action, ShareCoinFileAction.receive);
      await tapCoinKey(tester, 'coin-saved-files');
      expect(action, ShareCoinFileAction.saved);
      await tapCoinKey(tester, 'coin-file-history');
      expect(action, ShareCoinFileAction.history);
    });
    testWidgets('dashboard handles small screens and enlarged text', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await mountCoinDashboard(tester, f.service, size: const Size(320, 740));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('coin-file-history')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'disposal during wallet load does not update a dead dashboard',
      (tester) async {
        final f = CoinServiceFixture();
        final pending = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.wallet) {
            started.complete();
            return pending.future;
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await tester.pumpWidget(
          MaterialApp(home: ShareCoinHomeScreen(service: f.service)),
        );
        for (var i = 0; i < 50 && !started.isCompleted; i += 1) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(started.isCompleted, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete(
          f.backend.envelope(f.backend.scope!, coinFixtureBalance().toJson()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '31 existing home opens ShareCoin without losing selected files',
      (tester) async {
        final f = CoinServiceFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async =>
                  FileSelection(files: [baseline.sampleFile()]),
              onToggleTheme: () {},
              shareCoinScreenBuilder: (_) =>
                  ShareCoinHomeScreen(service: f.service),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await baseline.tapSelect(tester);
        await baseline.tapNavigation(tester, 'nav-home');
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('share-coin-home')), findsOneWidget);
        await tapCoinKey(tester, 'coin-send-files');
        expect(
          find.byKey(const ValueKey('send-selected-button')),
          findsOneWidget,
        );
        expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      },
    );
    testWidgets(
      '32 receiver and saved-history routes still use original screens',
      (tester) async {
        final f = CoinServiceFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async => FileSelection(files: []),
              onToggleTheme: () {},
              historyScreenBuilder: (_) => HistoryScreen(
                service: baseline.FakeHistoryService(
                  HistorySnapshot(transfers: []),
                ),
              ),
              shareCoinScreenBuilder: (_) =>
                  ShareCoinHomeScreen(service: f.service),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await tapCoinKey(tester, 'coin-receive-files');
        expect(
          find.byKey(const ValueKey('start-receiving-button')),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await tapCoinKey(tester, 'coin-file-history');
        expect(find.byKey(const ValueKey('history-scaffold')), findsOneWidget);
      },
    );
    testWidgets('account changes remove previously displayed wallet values', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      await mountCoinDashboard(tester, f.service);
      f.backend.switchAccount(
        AccountScope(userId: 'user-2', sessionId: 'new-session'),
      );
      await tester.pumpAndSettle();
      expect(find.text('10,000 ShareCoin'), findsNothing);
      expect(find.text('Wallet unavailable'), findsOneWidget);
    });
  });
}
