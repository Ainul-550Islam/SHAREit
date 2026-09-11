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
