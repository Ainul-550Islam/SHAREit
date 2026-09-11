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
