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
