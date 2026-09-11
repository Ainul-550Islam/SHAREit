import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_file.dart';
import 'nearby_screen.dart';
import 'history_screen.dart';
import 'share_coin_home_screen.dart';

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

Widget buildDefaultShareCoinScreen(BuildContext context) =>
    const ShareCoinHomeScreen();

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.pickFiles,
    required this.onToggleTheme,
    this.historyScreenBuilder = buildDefaultHistoryScreen,
    this.shareCoinScreenBuilder = buildDefaultShareCoinScreen,
  });

  final PickShareFiles pickFiles;
  final VoidCallback onToggleTheme;
  final WidgetBuilder historyScreenBuilder;
  final WidgetBuilder shareCoinScreenBuilder;

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

  Future<void> _openShareCoin() async {
    if (_isPicking) return;
    final action = await Navigator.of(context).push<ShareCoinFileAction>(
      MaterialPageRoute<ShareCoinFileAction>(
        builder: widget.shareCoinScreenBuilder,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ShareCoinFileAction.send:
        _changePage(1);
        if (_files.isEmpty) await _selectFiles();
      case ShareCoinFileAction.receive:
        await _openNearby(NearbyMode.receive);
      case ShareCoinFileAction.saved:
      case ShareCoinFileAction.history:
        await _openHistory();
    }
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
            key: const ValueKey('open-share-coin'),
            tooltip: 'ShareCoin rewards foundation',
            onPressed: _isPicking ? null : _openShareCoin,
            icon: const Icon(Icons.toll_outlined),
          ),
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
