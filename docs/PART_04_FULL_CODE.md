# Part 4 — File 16–20

Complete source based on Part 3. New files are first, in order. The complete required integration replacements follow; apply them as well, or use the full project ZIP.

## File 16 — `lib/models/transfer_activity.dart` — NEW

```dart
import 'transfer_models.dart';

enum TransferRole { sender, receiver }

// A UI projection of the existing engine model, not a second transfer protocol.
class TransferActivity {
  const TransferActivity({
    this.role = TransferRole.sender,
    this.progress = const TransferProgress(
      phase: TransferPhase.idle,
      message: 'No active transfer.',
    ),
    this.receipt,
    this.cancelRequested = false,
    this.settled = false,
    this.outcomeUncertain = false,
    this.errorMessage,
    this.warning,
    this.measuredBytesPerSecond,
    this.estimatedRemaining,
  });

  final TransferRole role;
  final TransferProgress progress;
  final TransferReceipt? receipt;
  final bool cancelRequested;
  final bool settled;
  final bool outcomeUncertain;
  final String? errorMessage;
  final String? warning;
  final double? measuredBytesPerSecond;
  final Duration? estimatedRemaining;

  bool get hasBatch => progress.attemptId != null;
  bool get confirmed => receipt != null;
  TransferPhase get phase =>
      progress.phase == TransferPhase.completed && !confirmed
      ? TransferPhase.verifying
      : progress.phase;
  int get totalFiles => progress.totalFiles.clamp(0, TransferLimits.maxFiles);
  int get completedFiles => progress.completedFiles.clamp(0, totalFiles);
  int get verifiedFiles => progress.verifiedFiles.clamp(0, totalFiles);
  int get totalBytes =>
      progress.totalBytes.clamp(0, TransferLimits.maxBatchBytes);
  int get batchBytes => progress.processedBytes.clamp(0, totalBytes);
  int? get currentFileNumber {
    final index = progress.currentFileIndex;
    return index == null || index < 0 || index >= totalFiles ? null : index + 1;
  }

  String? get fileName => currentFileNumber == null ? null : progress.fileName;
  int? get fileTotalBytes => currentFileNumber == null
      ? null
      : progress.currentFileTotalBytes?.clamp(0, TransferLimits.maxFileBytes);
  int? get fileBytes => fileTotalBytes == null
      ? null
      : progress.currentFileBytes?.clamp(0, fileTotalBytes!);
  double get fraction => totalBytes > 0
      ? (batchBytes / totalBytes).clamp(0.0, 1.0)
      : totalFiles > 0 && completedFiles == totalFiles
      ? 1
      : 0;
  double get percentage => fraction * 100;
  double? get bytesPerSecond {
    final speed = measuredBytesPerSecond;
    return speed != null && speed.isFinite && speed >= 0 ? speed : null;
  }

  Duration? get eta {
    final remaining = estimatedRemaining;
    return remaining != null && !remaining.isNegative ? remaining : null;
  }

  bool get moving =>
      phase == TransferPhase.sending || phase == TransferPhase.receiving;
  bool get terminal =>
      confirmed ||
      <TransferPhase>{
        TransferPhase.failed,
        TransferPhase.canceled,
        TransferPhase.rejected,
      }.contains(phase);
  bool get canCancel => hasBatch && !terminal && !cancelRequested;
  bool get canRetry =>
      role == TransferRole.sender &&
      terminal &&
      settled &&
      !confirmed &&
      !outcomeUncertain &&
      !progress.commitStarted;
  int? get successfulFiles =>
      outcomeUncertain && !confirmed ? null : receipt?.files.length ?? 0;
  int? get unsuccessfulFiles => outcomeUncertain && !confirmed
      ? null
      : terminal && !confirmed
      ? totalFiles
      : 0;

  String get phaseLabel {
    if (cancelRequested && !terminal) {
      return 'Cancellation requested';
    }
    return switch (phase) {
      TransferPhase.idle => 'Idle',
      TransferPhase.waiting => 'Waiting for a sender',
      TransferPhase.connecting => 'Connecting',
      TransferPhase.awaitingApproval => 'Waiting for approval',
      TransferPhase.approved => 'Approved',
      TransferPhase.preparing => 'Preparing',
      TransferPhase.sending => 'Sending',
      TransferPhase.receiving => 'Receiving',
      TransferPhase.verifying => 'Verifying and confirming',
      TransferPhase.completed => 'Completed',
      TransferPhase.rejected => 'Declined or expired',
      TransferPhase.canceled => 'Cancelled',
      TransferPhase.failed =>
        outcomeUncertain ? 'Outcome not confirmed' : 'Failed',
    };
  }

  String get verificationLabel => confirmed
      ? 'SHA-256 verified; complete batch confirmed'
      : verifiedFiles == totalFiles && totalFiles > 0
      ? 'File hashes matched; final receipt not confirmed'
      : terminal
      ? 'Complete-batch verification not confirmed'
      : '$verifiedFiles / $totalFiles file hashes checked';
  String get receiptLabel => confirmed
      ? role == TransferRole.sender
            ? 'Receiver delivery receipt validated'
            : 'Saved receipt available in app documents'
      : outcomeUncertain
      ? 'Receipt missing; check the receiving phone'
      : 'No confirmed saved-batch receipt';
}
```

## File 17 — `lib/services/transfer_progress_controller.dart` — NEW

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/transfer_activity.dart';
import '../models/transfer_models.dart';

class TransferProgressController extends ValueNotifier<TransferActivity> {
  TransferProgressController({this.clock, this.autoRefresh = true})
    : super(const TransferActivity());

  final Duration Function()? clock;
  final bool autoRefresh;
  final Stopwatch _watch = Stopwatch()..start();
  final List<({Duration time, int bytes})> _samples = [];
  final Set<String> _seenAttempts = <String>{};
  List<OfferedFile> _manifest = const <OfferedFile>[];
  Timer? _ticker;
  Duration? _lastPayload;
  Duration _lastTime = Duration.zero;
  int _epoch = 0;
  int _sequence = 0;
  bool _closed = false;
  bool _cancelRequested = false;
  bool _settled = false;
  bool _uncertain = false;
  String? _error;
  String? _warning;
  TransferReceipt? _receipt;
  TransferRole _role = TransferRole.sender;

  int open(TransferRole role) {
    if (_closed) return _epoch;
    _epoch += 1;
    _role = role;
    _sequence = 0;
    _seenAttempts.clear();
    _manifest = const <OfferedFile>[];
    _resetBatch();
    _publish(
      const TransferProgress(
        phase: TransferPhase.idle,
        message: 'No active transfer.',
      ),
    );
    return _epoch;
  }

  void _resetBatch() {
    _ticker?.cancel();
    _ticker = null;
    _samples.clear();
    _lastPayload = null;
    _receipt = null;
    _error = null;
    _warning = null;
    _cancelRequested = false;
    _settled = false;
    _uncertain = false;
  }

  Duration _now() {
    final next = clock?.call() ?? _watch.elapsed;
    if (next < _lastTime) {
      _samples.clear();
      _lastPayload = null;
      return _lastTime;
    }
    _lastTime = next;
    return next;
  }

  bool addEngineEvent(int epoch, TransferProgress event) {
    if (_closed || epoch != _epoch || event.sequence <= _sequence) return false;
    final initial =
        event.phase == TransferPhase.connecting ||
        event.phase == TransferPhase.awaitingApproval;
    if (event.attemptId == null) {
      if (!value.hasBatch && event.phase == TransferPhase.waiting) {
        _sequence = event.sequence;
        _publish(event);
        return true;
      }
      return false;
    }
    final changed = value.progress.attemptId != event.attemptId;
    if (changed) {
      if (!initial ||
          (value.hasBatch && !value.terminal) ||
          _seenAttempts.contains(event.attemptId)) {
        return false;
      }
      try {
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(event.attemptId!)) {
          throw const FormatException();
        }
        final offer = IncomingOffer(
          id: event.transferId ?? '',
          senderName: 'Progress metadata',
          remoteAddress: '',
          files: event.manifest ?? const <OfferedFile>[],
        );
        if (event.totalBytes != offer.totalBytes ||
            event.totalFiles != offer.files.length) {
          throw const FormatException();
        }
        if (event.processedBytes != 0 ||
            event.completedFiles != 0 ||
            event.verifiedFiles != 0 ||
            event.currentFileIndex != null ||
            event.currentFileBytes != null ||
            event.currentFileTotalBytes != null ||
            event.receipt != null ||
            event.commitStarted) {
          throw const FormatException();
        }
        _manifest = offer.files;
      } catch (_) {
        return _reject('Progress metadata was invalid; update ignored.');
      }
      _resetBatch();
      _seenAttempts.add(event.attemptId!);
    } else if (event.transferId != value.progress.transferId ||
        value.terminal) {
      return false;
    }
    final total = _manifest.fold<int>(0, (sum, file) => sum + file.size);
    if (event.totalBytes != total || event.totalFiles != _manifest.length) {
      return _reject('Inconsistent progress totals were ignored.');
    }
    final previous = changed
        ? const TransferProgress(phase: TransferPhase.idle, message: '')
        : value.progress;
    if (!_transition(previous.phase, event.phase)) {
      return _reject('An out-of-order transfer state was ignored.');
    }
    final bytes = event.processedBytes.clamp(0, total);
    final done = event.completedFiles.clamp(0, _manifest.length);
    final checked = event.verifiedFiles >= 0 && event.verifiedFiles <= done
        ? event.verifiedFiles
        : previous.verifiedFiles;
    if (bytes < previous.processedBytes ||
        done < previous.completedFiles ||
        checked < previous.verifiedFiles) {
      return _reject('Regressing transfer counters were ignored.');
    }
    if (done == _manifest.length && bytes != total) {
      return _reject('Completed-file and byte counters disagreed.');
    }
    if (<TransferPhase>{
          TransferPhase.connecting,
          TransferPhase.awaitingApproval,
          TransferPhase.approved,
        }.contains(event.phase) &&
        (bytes != 0 || done != 0)) {
      return _reject('Bytes reported before transfer activity were ignored.');
    }
    final index = event.currentFileIndex ?? previous.currentFileIndex;
    if (index != null && (index < 0 || index >= _manifest.length)) {
      return _reject('An invalid current-file index was ignored.');
    }
    final fileTotal = index == null ? null : _manifest[index].size;
    if (event.currentFileTotalBytes != null &&
        event.currentFileTotalBytes != fileTotal) {
      return _reject('An inconsistent file size was ignored.');
    }
    final rawFileBytes =
        event.currentFileBytes ??
        (index == previous.currentFileIndex ? previous.currentFileBytes : null);
    final fileBytes = fileTotal == null
        ? null
        : rawFileBytes?.clamp(0, fileTotal);
    if (index == previous.currentFileIndex &&
        fileBytes != null &&
        previous.currentFileBytes != null &&
        fileBytes < previous.currentFileBytes!) {
      return _reject('Regressing current-file bytes were ignored.');
    }
    if (fileBytes != null && fileBytes > bytes) {
      return _reject('File bytes exceeded batch bytes; update ignored.');
    }
    if (bytes != event.processedBytes ||
        done != event.completedFiles ||
        checked != event.verifiedFiles ||
        fileBytes != rawFileBytes) {
      _warning = 'Invalid counters were bounded to the approved batch. No delivery is inferred.';
    }
    final phase = event.phase == TransferPhase.completed
        ? TransferPhase.verifying
        : event.phase == TransferPhase.rejected && _cancelRequested
        ? TransferPhase.canceled
        : event.phase;
    if (phase == TransferPhase.verifying &&
        (bytes != total || done != _manifest.length)) {
      return _reject('Verification arrived before complete byte counters.');
    }
    final normalized = TransferProgress(
      phase: phase,
      message: _message(event.message),
      transferId: event.transferId,
      attemptId: event.attemptId,
      sequence: event.sequence,
      manifest: _manifest,
      totalBytes: total,
      processedBytes: bytes,
      totalFiles: _manifest.length,
      completedFiles: done,
      verifiedFiles: checked,
      currentFileIndex: index,
      currentFileBytes: fileBytes,
      currentFileTotalBytes: fileTotal,
      fileName: index == null ? null : _manifest[index].name,
      commitStarted: previous.commitStarted || event.commitStarted,
    );
    final time = _now();
    if (phase == TransferPhase.sending || phase == TransferPhase.receiving) {
      if (_samples.isEmpty) {
        _samples.add((time: time, bytes: previous.processedBytes));
      }
      if (bytes > previous.processedBytes) {
        _lastPayload = time;
        _samples.add((time: time, bytes: bytes));
        if (_samples.length > 128) _samples.removeAt(0);
      }
      if (autoRefresh) {
        _ticker ??= Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => refreshEstimates(),
        );
      }
    }
    if (<TransferPhase>{
      TransferPhase.failed,
      TransferPhase.canceled,
      TransferPhase.rejected,
    }.contains(phase)) {
      _error = normalized.message;
      _uncertain = _role == TransferRole.sender && normalized.commitStarted;
    }
    _sequence = event.sequence;
    _publish(normalized);
    if (event.phase == TransferPhase.completed && event.receipt != null) {
      return completeFromReceipt(epoch, event.attemptId!, event.receipt!);
    }
    return true;
  }

  bool completeFromReceipt(
    int epoch,
    String attemptId,
    TransferReceipt receipt,
  ) {
    if (_closed ||
        epoch != _epoch ||
        attemptId != value.progress.attemptId ||
        receipt.id != value.progress.transferId) {
      return false;
    }
    if (_receipt != null) return false;
    final byId = <String, ReceivedFile>{
      for (final file in receipt.files) file.id: file,
    };
    if (receipt.files.length != _manifest.length ||
        byId.length != _manifest.length ||
        _manifest.any((file) {
          final actual = byId[file.id];
          return actual == null ||
              actual.name != file.name ||
              actual.size != file.size ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(actual.digest);
        })) {
      return _reject('The completion receipt did not match this attempt.');
    }
    _receipt = receipt;
    _error = null;
    _uncertain = false;
    final index = value.progress.currentFileIndex ?? _manifest.length - 1;
    _publish(
      value.progress.copyWith(
        phase: TransferPhase.completed,
        message: _role == TransferRole.sender
            ? 'Receiver confirmed every file.'
            : 'The complete batch is saved and verified.',
        processedBytes: receipt.totalBytes,
        completedFiles: receipt.files.length,
        verifiedFiles: receipt.files.length,
        currentFileIndex: index,
        currentFileTotalBytes: _manifest[index].size,
        currentFileBytes: _manifest[index].size,
        fileName: _manifest[index].name,
        receipt: receipt,
      ),
    );
    return true;
  }

  bool requestCancellation(int epoch) {
    if (_closed || epoch != _epoch || !value.canCancel) return false;
    _cancelRequested = true;
    _publish(value.progress);
    return true;
  }

  void finishFailure(int epoch, TransferException error) {
    if (_closed || epoch != _epoch || !value.hasBatch || _receipt != null) {
      return;
    }
    _error = _message(error.message);
    _uncertain =
        error.outcomeUncertain ||
        (_role == TransferRole.sender && value.progress.commitStarted);
    _publish(
      value.progress.copyWith(
        phase: error is TransferCancelled && !_uncertain
            ? TransferPhase.canceled
            : TransferPhase.failed,
        message: _error,
      ),
    );
  }

  void settle(int epoch) {
    if (_closed || epoch != _epoch) return;
    _settled = true;
    _publish(value.progress);
  }

  void refreshEstimates() {
    if (!_closed && value.moving && !value.terminal) _publish(value.progress);
  }

  bool _reject(String message) {
    _warning = message;
    _publish(value.progress);
    return false;
  }

  String _message(String input) {
    final text = input.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return text.length <= 500 ? text : text.substring(0, 500);
  }

  void _publish(TransferProgress progress) {
    if (_closed) return;
    double? speed;
    Duration? eta;
    final time = _now();
    final moving =
        progress.phase == TransferPhase.sending ||
        progress.phase == TransferPhase.receiving;
    if (moving && _samples.isNotEmpty) {
      final cutoff = time - const Duration(seconds: 3);
      while (_samples.length > 1 && _samples[1].time < cutoff) {
        _samples.removeAt(0);
      }
      final elapsed = time - _samples.first.time;
      if (_lastPayload != null &&
          time - _lastPayload! > const Duration(seconds: 3)) {
        speed = 0;
      } else if (elapsed.inMicroseconds > 0) {
        speed =
            (progress.processedBytes - _samples.first.bytes) *
            Duration.microsecondsPerSecond /
            elapsed.inMicroseconds;
      }
      if (speed != null && speed.isFinite && speed > 0) {
        eta = Duration(
          seconds: ((progress.totalBytes - progress.processedBytes) / speed)
              .ceil(),
        );
      }
    }
    value = TransferActivity(
      role: _role,
      progress: progress,
      receipt: _receipt,
      cancelRequested: _cancelRequested,
      settled: _settled,
      outcomeUncertain: _uncertain,
      errorMessage: _error,
      warning: _warning,
      measuredBytesPerSecond: speed,
      estimatedRemaining: eta,
    );
    if (value.terminal) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  bool _transition(TransferPhase from, TransferPhase to) {
    if (from == to) return true;
    if (<TransferPhase>{
      TransferPhase.failed,
      TransferPhase.rejected,
      TransferPhase.canceled,
    }.contains(to)) {
      return true;
    }
    return switch (from) {
      TransferPhase.idle || TransferPhase.waiting =>
        to == TransferPhase.connecting || to == TransferPhase.awaitingApproval,
      TransferPhase.connecting => to == TransferPhase.awaitingApproval,
      TransferPhase.awaitingApproval => to == TransferPhase.approved,
      TransferPhase.approved =>
        to == TransferPhase.preparing ||
            to == TransferPhase.receiving ||
            to == TransferPhase.sending,
      TransferPhase.preparing =>
        to == TransferPhase.sending || to == TransferPhase.receiving,
      TransferPhase.sending || TransferPhase.receiving =>
        to == TransferPhase.preparing ||
            to == TransferPhase.verifying ||
            to == TransferPhase.completed,
      TransferPhase.verifying => to == TransferPhase.completed,
      TransferPhase.completed ||
      TransferPhase.failed ||
      TransferPhase.canceled ||
      TransferPhase.rejected => false,
    };
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _ticker?.cancel();
    _watch.stop();
    super.dispose();
  }
}
```

## File 18 — `lib/widgets/transfer_progress_panel.dart` — NEW

```dart
import 'package:flutter/material.dart';

import '../models/share_file.dart';
import '../models/transfer_activity.dart';
import '../models/transfer_models.dart';
import '../services/transfer_progress_controller.dart';

class TransferProgressPanel extends StatelessWidget {
  const TransferProgressPanel({
    super.key,
    required this.controller,
    this.onCancel,
  });

  final TransferProgressController controller;
  final VoidCallback? onCancel;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TransferActivity>(
    valueListenable: controller,
    builder: (context, state, child) {
      final theme = Theme.of(context);
      final busy = <TransferPhase>{
        TransferPhase.connecting,
        TransferPhase.awaitingApproval,
        TransferPhase.approved,
        TransferPhase.preparing,
      }.contains(state.phase);
      final percent = (state.percentage * 10).floor() / 10;
      final speed = state.bytesPerSecond;
      return Container(
        key: const ValueKey('detailed-transfer-progress'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${state.role == TransferRole.sender ? 'SENDER' : 'RECEIVER'} · LIVE TRANSFER',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.phaseLabel,
              key: const ValueKey('transfer-state-label'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(state.progress.message),
            if (state.phase == TransferPhase.awaitingApproval)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Receiver approval is required. No file bytes are sent before acceptance.',
                ),
              ),
            const SizedBox(height: 16),
            Text(
              state.fileName ?? 'No file is currently open',
              key: const ValueKey('transfer-current-file'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              state.currentFileNumber == null
                  ? '${state.totalFiles} files in this batch'
                  : 'File ${state.currentFileNumber} of ${state.totalFiles}',
              key: const ValueKey('transfer-file-number'),
            ),
            if (state.fileBytes != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Current file: ${formatBytes(state.fileBytes!)} / ${formatBytes(state.fileTotalBytes!)}',
                ),
              ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const ValueKey('transfer-byte-progress'),
              value: busy ? null : state.fraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              semanticsLabel: 'Payload bytes, not delivery confirmation',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: <Widget>[
                Text(
                  '${percent.toStringAsFixed(1)}% bytes',
                  key: const ValueKey('transfer-percent'),
                ),
                Text(
                  '${formatBytes(state.batchBytes)} / ${formatBytes(state.totalBytes)}',
                  key: const ValueKey('transfer-byte-count'),
                ),
                Text(
                  '${state.completedFiles} / ${state.totalFiles} staged files',
                  key: const ValueKey('transfer-staged-count'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: <Widget>[
                Text(
                  'Payload rate: ${!state.moving
                      ? 'Not active'
                      : speed == null
                      ? 'Measuring'
                      : '${formatBytes(speed.floor())}/s'}',
                  key: const ValueKey('transfer-speed'),
                ),
                Text(
                  'Byte ETA: ${_eta(state.eta)}',
                  key: const ValueKey('transfer-eta'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rate uses recent local payload writes. ETA excludes approval, verification and final saving.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Text(
              state.verificationLabel,
              key: const ValueKey('transfer-verification'),
            ),
            if (state.phase == TransferPhase.verifying)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Awaiting final verification and receipt',
                ),
              ),
            if (!state.confirmed)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '100% bytes is not a delivery receipt. Wait for complete-batch confirmation.',
                ),
              ),
            if (state.cancelRequested && !state.terminal)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Stopping the real transfer. A commit already in progress may still finish.',
                ),
              ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (state.warning != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(state.warning!),
              ),
            if (!state.terminal && state.hasBatch)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  key: const ValueKey('cancel-transfer-progress'),
                  onPressed: state.canCancel ? onCancel : null,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(
                    state.cancelRequested
                        ? 'Cancellation requested'
                        : 'Cancel transfer',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  String _eta(Duration? duration) {
    if (duration == null) return 'Not available';
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    if (seconds < 86400) {
      return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
    }
    return 'Over 24 hours';
  }
}
```

## File 19 — `lib/widgets/transfer_result_panel.dart` — NEW

```dart
import 'package:flutter/material.dart';

import '../models/share_file.dart';
import '../models/transfer_activity.dart';
import '../models/transfer_models.dart';

class TransferResultPanel extends StatelessWidget {
  const TransferResultPanel({
    super.key,
    required this.activity,
    required this.onDone,
    this.onRetry,
    this.onViewSavedFiles,
    this.details,
  });

  final TransferActivity activity;
  final VoidCallback onDone;
  final VoidCallback? onRetry;
  final VoidCallback? onViewSavedFiles;
  // The existing receipt/export panel is embedded, not replaced.
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final state = activity;
    if (!state.terminal) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('transfer-result-panel'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: state.confirmed
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            state.confirmed
                ? Icons.verified_outlined
                : Icons.info_outline_rounded,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            'Transfer result',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.role == TransferRole.sender ? 'Sender' : 'Receiver'} · ${state.phaseLabel}',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: <Widget>[
              Text(
                'Successful files: ${state.successfulFiles ?? 'Unknown'}',
                key: const ValueKey('result-successful-files'),
              ),
              Text(
                'Unsuccessful files: ${state.unsuccessfulFiles ?? 'Unknown'}',
                key: const ValueKey('result-unsuccessful-files'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Payload transferred: ${formatBytes(state.batchBytes)} / ${formatBytes(state.totalBytes)}',
          ),
          if (state.confirmed)
            Text(
              'Confirmed saved size: ${formatBytes(state.receipt!.totalBytes)}',
            ),
          const SizedBox(height: 10),
          Text(state.verificationLabel),
          const SizedBox(height: 6),
          Text(
            state.receiptLabel,
            key: const ValueKey('result-receipt-status'),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(state.errorMessage!),
            ),
          if (state.outcomeUncertain)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Do not retry blindly. Check the receiving phone and its saved history; the batch may already be saved.',
              ),
            ),
          if (state.cancelRequested && state.confirmed)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'The engine confirmed completion before cancellation could take effect. Saved copies are kept.',
              ),
            ),
          if (state.phase == TransferPhase.canceled)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Cancelled without a confirmed commit. Original selected files are unchanged.',
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'This protocol commits the whole batch atomically. Unsuccessful includes files not attempted or rolled back, not only a file that raised an error.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton(
                key: const ValueKey('transfer-result-done'),
                onPressed: onDone,
                child: const Text('Done'),
              ),
              if (state.canRetry && onRetry != null)
                OutlinedButton.icon(
                  key: const ValueKey('retry-uncommitted-transfer'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry uncommitted batch'),
                ),
              if (state.role == TransferRole.receiver &&
                  state.confirmed &&
                  onViewSavedFiles != null)
                OutlinedButton.icon(
                  key: const ValueKey('result-view-saved-files'),
                  onPressed: onViewSavedFiles,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('View Saved Files'),
                ),
            ],
          ),
          if (details != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: details),
        ],
      ),
    );
  }
}
```

## File 20 — `test/transfer_progress_test.dart` — NEW

```dart
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
```

## Required integration replacements — full files

These replace the numbered files in the existing project. None is a patch or an abbreviated implementation.

## File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.4.0+4

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

## File 6 — `lib/models/transfer_models.dart` — UPDATED

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
  idle,
  approved,
  preparing,
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
    this.transferId,
    this.attemptId,
    this.sequence = 0,
    this.manifest,
    this.currentFileIndex,
    this.currentFileBytes,
    this.currentFileTotalBytes,
    this.verifiedFiles = 0,
    this.commitStarted = false,
    this.receipt,
  });

  final TransferPhase phase;
  final String message;
  final int totalBytes;
  final int processedBytes;
  final int totalFiles;
  final int completedFiles;
  final String? fileName;
  // Local telemetry only. These fields are never added to the wire protocol.
  final String? transferId;
  final String? attemptId;
  final int sequence;
  final List<OfferedFile>? manifest;
  final int? currentFileIndex;
  final int? currentFileBytes;
  final int? currentFileTotalBytes;
  final int verifiedFiles;
  final bool commitStarted;
  final TransferReceipt? receipt;

  TransferProgress copyWith({
    TransferPhase? phase,
    String? message,
    int? totalBytes,
    int? processedBytes,
    int? totalFiles,
    int? completedFiles,
    String? fileName,
    String? transferId,
    String? attemptId,
    int? sequence,
    List<OfferedFile>? manifest,
    int? currentFileIndex,
    int? currentFileBytes,
    int? currentFileTotalBytes,
    int? verifiedFiles,
    bool? commitStarted,
    TransferReceipt? receipt,
  }) => TransferProgress(
    phase: phase ?? this.phase,
    message: message ?? this.message,
    totalBytes: totalBytes ?? this.totalBytes,
    processedBytes: processedBytes ?? this.processedBytes,
    totalFiles: totalFiles ?? this.totalFiles,
    completedFiles: completedFiles ?? this.completedFiles,
    fileName: fileName ?? this.fileName,
    transferId: transferId ?? this.transferId,
    attemptId: attemptId ?? this.attemptId,
    sequence: sequence ?? this.sequence,
    manifest: manifest ?? this.manifest,
    currentFileIndex: currentFileIndex ?? this.currentFileIndex,
    currentFileBytes: currentFileBytes ?? this.currentFileBytes,
    currentFileTotalBytes: currentFileTotalBytes ?? this.currentFileTotalBytes,
    verifiedFiles: verifiedFiles ?? this.verifiedFiles,
    commitStarted: commitStarted ?? this.commitStarted,
    receipt: receipt ?? this.receipt,
  );

  double get fraction {
    if (phase == TransferPhase.completed) {
      return 1;
    }
    return totalBytes == 0 ? 0 : (processedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get indeterminate =>
      phase == TransferPhase.connecting ||
      phase == TransferPhase.awaitingApproval ||
      phase == TransferPhase.preparing ||
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

## File 7 — `lib/services/local_transfer_service.dart` — UPDATED

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
    required this.progressId,
  });

  final IncomingOffer offer;
  final String token;
  final Directory directory;
  final String progressId;
  int? currentFileIndex;
  int currentFileBytes = 0;
  int verifiedFiles = 0;
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
  int _progressSequence = 0;

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

  void _emit(TransferProgress progress) =>
      onProgress?.call(progress.copyWith(sequence: ++_progressSequence));

  void _emitOffer(
    IncomingOffer offer,
    String progressId,
    TransferPhase phase,
    String message,
  ) {
    _emit(
      TransferProgress(
        phase: phase,
        message: message,
        transferId: offer.id,
        attemptId: progressId,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        totalFiles: offer.files.length,
      ),
    );
  }

  void _emitBatch(_ReceivingBatch batch, TransferProgress progress) {
    final index = batch.currentFileIndex;
    final file = index == null ? null : batch.offer.files[index];
    _emit(
      progress.copyWith(
        transferId: batch.offer.id,
        attemptId: batch.progressId,
        manifest: batch.offer.files,
        totalBytes: batch.offer.totalBytes,
        processedBytes: batch.bytesReceived,
        totalFiles: batch.offer.files.length,
        completedFiles: batch.digests.length,
        currentFileIndex: index,
        currentFileBytes: index == null ? null : batch.currentFileBytes,
        currentFileTotalBytes: file?.size,
        fileName: file?.name,
        verifiedFiles: batch.verifiedFiles,
        commitStarted: batch.committing || batch.committed,
      ),
    );
  }

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
        _emitBatch(
          batch,
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
    IncomingOffer? progressOffer;
    String? progressAttempt;
    var decisionEnded = false;
    try {
      final offer = IncomingOffer.fromJson(
        await readBoundedJson(request),
        remoteAddress: remote,
      );
      if (!isRunning || !_invitationValid) {
        throw const _HttpFailure(410, 'The receiving session has ended.');
      }
      final progressId = randomTransferId();
      progressOffer = offer;
      progressAttempt = progressId;
      _emitOffer(
        offer,
        progressId,
        TransferPhase.awaitingApproval,
        'An incoming batch is waiting for your decision.',
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
        decisionEnded = true;
        _emitOffer(
          offer,
          progressId,
          TransferPhase.rejected,
          'The request was declined, expired, or closed.',
        );
        throw const _HttpFailure(
          403,
          'The receiver declined the request or it expired.',
        );
      }
      _emitOffer(
        offer,
        progressId,
        TransferPhase.approved,
        'Receiver approval granted.',
      );
      _emitOffer(
        offer,
        progressId,
        TransferPhase.preparing,
        'Preparing private staging storage.',
      );
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
        progressId: progressId,
      );
      _batch = batch;
      _armBatchIdleTimer(batch);
      batch.timer = Timer(batchTimeout, () {
        unawaited(
          _discardBatch(batch).then((_) {
            _emitBatch(
              batch,
              const TransferProgress(
                phase: TransferPhase.failed,
                message: 'Transfer deadline exceeded. Start again.',
              ),
            );
          }),
        );
      });
      _emitBatch(
        batch,
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
    } catch (_) {
      if (!decisionEnded &&
          progressOffer != null &&
          progressAttempt != null &&
          _batch == null &&
          isRunning) {
        _emitOffer(
          progressOffer,
          progressAttempt,
          TransferPhase.failed,
          'The receiving batch could not be prepared. Check available storage.',
        );
      }
      rethrow;
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
            _emitBatch(
              batch,
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
    batch.currentFileIndex = batch.offer.files.indexOf(file);
    batch.currentFileBytes = 0;
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
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.preparing,
          message: 'Opening the receiving file.',
        ),
      );
      output = await File('${batch.directory.path}/${file.id}.part')
          .open(mode: FileMode.write);
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.receiving,
          message: 'Receiving encrypted file bytes.',
        ),
      );
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
        batch.currentFileBytes = count;
        _emitBatch(
          batch,
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
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.receiving,
          message: 'File staged. Final batch verification is still required.',
        ),
      );
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
          _emitBatch(
            batch,
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
      _emitBatch(
        batch,
        const TransferProgress(
          phase: TransferPhase.verifying,
          message: 'Comparing the sender and receiver SHA-256 values.',
        ),
      );
      for (final file in batch.offer.files) {
        if (hashes[file.id] is! String ||
            !secretEquals(hashes[file.id] as String, batch.digests[file.id]!)) {
          throw const TransferException(
            'A file checksum did not match. Nothing was committed.',
          );
        }
        batch.verifiedFiles += 1;
        _emitBatch(
          batch,
          const TransferProgress(
            phase: TransferPhase.verifying,
            message: 'Checking file hashes before saving the complete batch.',
          ),
        );
      }
      if (batch.canceled || !isRunning) {
        throw const TransferCancelled();
      }
      _emitBatch(
        batch,
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
      _emitBatch(
        batch,
        TransferProgress(
          phase: TransferPhase.completed,
          message: 'Files saved. SHA-256 checksums match the sender.',
          receipt: receipt,
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
          _emitBatch(
            batch,
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
        _emitBatch(
          batch,
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
    var sequence = 0;
    TransferProgress? latest;
    void emitProgress(TransferProgress progress) {
      final enriched = progress.copyWith(
        transferId: offer.id,
        attemptId: offer.id,
        sequence: ++sequence,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        processedBytes: sentBytes,
        totalFiles: offer.files.length,
        completedFiles: digests.length,
        verifiedFiles: digests.length,
        currentFileIndex: progress.currentFileIndex ?? latest?.currentFileIndex,
        currentFileBytes: progress.currentFileBytes ?? latest?.currentFileBytes,
        currentFileTotalBytes:
            progress.currentFileTotalBytes ?? latest?.currentFileTotalBytes,
        fileName: progress.fileName ?? latest?.fileName,
        commitStarted: commitStarted,
      );
      latest = enriched;
      onProgress?.call(enriched);
    }

    try {
      emitProgress(
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
      emitProgress(
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
      emitProgress(
        const TransferProgress(
          phase: TransferPhase.approved,
          message: 'The receiver approved this batch.',
        ),
      );
      for (var index = 0; index < selected.length; index += 1) {
        final source = selected[index];
        final descriptor = offer.files[index];
        emitProgress(
          TransferProgress(
            phase: TransferPhase.preparing,
            message: 'Preparing the next selected file.',
            currentFileIndex: index,
            currentFileBytes: 0,
            currentFileTotalBytes: descriptor.size,
            fileName: descriptor.name,
          ),
        );
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
        emitProgress(
          TransferProgress(
            phase: TransferPhase.sending,
            message: 'Streaming encrypted file bytes.',
            currentFileIndex: index,
            currentFileBytes: 0,
            currentFileTotalBytes: descriptor.size,
            fileName: descriptor.name,
          ),
        );
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
            emitProgress(
              TransferProgress(
                phase: TransferPhase.sending,
                message: 'Streaming encrypted bytes. Waiting for final confirmation.',
                totalBytes: offer.totalBytes,
                processedBytes: sentBytes,
                totalFiles: offer.files.length,
                completedFiles: index,
                currentFileIndex: index,
                currentFileBytes: fileBytes,
                currentFileTotalBytes: descriptor.size,
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
          emitProgress(
            TransferProgress(
              phase: TransferPhase.sending,
              message: 'Staged file checksum matched. Final receipt is still required.',
              currentFileIndex: index,
              currentFileBytes: fileBytes,
              currentFileTotalBytes: descriptor.size,
              fileName: descriptor.name,
            ),
          );
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
      emitProgress(
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
      _checkCanceled();
      // Conservatively mark the commit boundary before queuing its body.
      commitStarted = true;
      emitProgress(
        const TransferProgress(
          phase: TransferPhase.verifying,
          message:
              'Commit requested. Waiting for a validated delivery receipt.',
        ),
      );
      commit.add(body);
      _checkCanceled();
      commitStarted = true;
      final receipt = _verifyReceipt(
        await _response(commit, idleTimeout),
        offer,
        digests,
      );
      _emitCompleted(receipt, emitProgress);
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
          _emitCompleted(recovered, emitProgress);
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
        receipt: receipt,
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

## File 8 — `lib/screens/nearby_screen.dart` — UPDATED

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/share_file.dart';
import '../models/transfer_models.dart';
import '../models/transfer_activity.dart';
import '../services/transfer_progress_controller.dart';
import '../widgets/transfer_progress_panel.dart';
import '../widgets/transfer_result_panel.dart';
import 'history_screen.dart';
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
    this.senderFactory = LocalSender.new,
  });

  final NearbyMode mode;
  final List<ShareFile> files;
  final Future<Directory> Function() documentsDirectory;
  final Future<String?> Function(BuildContext context) scanCode;
  final LocalSender Function() senderFactory;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with WidgetsBindingObserver {
  final TextEditingController _codeController = TextEditingController();
  final ScrollController _bodyScroll = ScrollController();
  late final TextEditingController _nameController;
  final TransferProgressController _tracker = TransferProgressController();
  int _run = 0;
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
    _run = _tracker.open(
      _isReceiver ? TransferRole.receiver : TransferRole.sender,
    );
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
      _tracker.requestCancellation(_run);
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
    _tracker.dispose();
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
    if (!_tracker.addEngineEvent(_run, progress)) {
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
    final run = _tracker.open(TransferRole.receiver);
    _run = run;
    LocalReceiver? receiver;
    try {
      final documents = await widget.documentsDirectory();
      if (!_canUpdate || !_foreground) {
        return;
      }
      receiver = LocalReceiver(
        storageRoot: Directory('${documents.path}/ShareBondhu/Received'),
        onOffer: (offer) => run == _run && _canUpdate
            ? _askForApproval(offer)
            : Future<bool>.value(false),
        onProgress: (progress) {
          if (run == _run && _canUpdate) {
            _receiveProgress(progress);
          }
        },
        onReceived: (receipt) {
          if (_canUpdate && run == _run) {
            setState(() => _receipt = receipt);
          }
        },
        onStopped: (reason) {
          if (_canUpdate && run == _run) {
            if (_tracker.value.hasBatch && !_tracker.value.terminal) {
              _tracker.finishFailure(run, const TransferCancelled());
            }
            _tracker.settle(run);
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
      _tracker.requestCancellation(_run);
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
    if (_tracker.value.outcomeUncertain && !_tracker.value.confirmed) {
      final checked = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Check the receiver first'),
          content: const Text(
            'The last batch may already be saved. Continue only after checking the receiving phone to avoid duplicate copies.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('I checked the receiver'),
            ),
          ],
        ),
      );
      if (checked != true || !mounted || !_foreground || _sending) {
        return;
      }
    }
    if (!mounted || !_foreground) {
      return;
    }
    final run = _tracker.open(TransferRole.sender);
    _run = run;
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
    final sender = widget.senderFactory();
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
          if (_canUpdate &&
              run == _run &&
              identical(_sender, sender) &&
              _tracker.addEngineEvent(run, progress)) {
            setState(() => _progress = progress);
          }
        },
      );
      if (_canUpdate && run == _run) {
        final attempt = _tracker.value.progress.attemptId;
        if (attempt != null) {
          _tracker.completeFromReceipt(run, attempt, receipt);
        }
        setState(() => _receipt = receipt);
      }
    } on TransferException catch (error) {
      if (_canUpdate && run == _run) {
        _tracker.finishFailure(run, error);
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
      if (_canUpdate && run == _run) {
        _tracker.finishFailure(
          run,
          const TransferException(
            'Sending stopped. Check the receiver before trying again.',
            outcomeUncertain: true,
          ),
        );
        setState(
          () => _error =
              'Sending stopped. Check the receiver before trying again.',
        );
      }
    } finally {
      _tracker.settle(run);
      if (identical(_sender, sender)) {
        _sender = null;
      }
      if (_canUpdate) {
        setState(() => _sending = false);
      }
    }
  }

  void _cancelTransfer() {
    if (_tracker.value.cancelRequested) return;
    _tracker.requestCancellation(_run);
    if (_isReceiver) {
      unawaited(
        _stopReceiving(
          reason: 'Receiving cancelled. Confirmed copies are kept.',
        ),
      );
    } else {
      _sender?.cancel();
    }
    if (_canUpdate) setState(() {});
  }

  Future<void> _retryUncommitted() async {
    if (!_tracker.value.canRetry || _sending || !_foreground) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retry the uncommitted batch?'),
        content: const Text(
          'All files in this atomic batch need a new attempt and receiver approval. Reselect any source files that have changed. No partial upload is resumed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ask again'),
          ),
        ],
      ),
    );
    if (approved == true && _canUpdate && _tracker.value.canRetry) {
      await _send();
    }
  }

  void _done() {
    if (_active) {
      unawaited(_confirmLeave());
    } else if (_canUpdate) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _viewSavedFiles() async {
    if (!_isReceiver || !_tracker.value.confirmed || _starting || _stopping) {
      return;
    }
    if (_session != null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Open saved files?'),
          content: const Text(
            'This stops the receiving session and any new incoming request. Already confirmed copies are kept.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stop and view'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
      await _stopReceiving();
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            HistoryScreen(documentsDirectory: widget.documentsDirectory),
      ),
    );
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
    _tracker.requestCancellation(_run);
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
                  if (_tracker.value.hasBatch)
                    TransferProgressPanel(
                      controller: _tracker,
                      onCancel: _cancelTransfer,
                    )
                  else if (_progress != null &&
                      _progress!.phase != TransferPhase.waiting)
                    _ProgressPanel(progress: _progress!),
                  if (_tracker.value.terminal)
                    TransferResultPanel(
                      activity: _tracker.value,
                      onDone: _done,
                      onRetry: _retryUncommitted,
                      onViewSavedFiles: _viewSavedFiles,
                      details: _tracker.value.receipt == null
                          ? null
                          : _buildReceipt(theme, _tracker.value.receipt!),
                    )
                  else if (_receipt != null)
                    _buildReceipt(theme, _receipt!),
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
                        'Part 4: private IPv4 Wi-Fi/hotspot only. Keep both apps open. '
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
                  'PART 04 · LOCAL TLS',
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
                  onPressed: _tracker.value.cancelRequested
                      ? null
                      : _cancelTransfer,
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
