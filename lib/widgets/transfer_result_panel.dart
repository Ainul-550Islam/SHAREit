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
