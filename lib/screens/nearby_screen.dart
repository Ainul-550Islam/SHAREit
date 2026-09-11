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
