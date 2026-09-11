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
