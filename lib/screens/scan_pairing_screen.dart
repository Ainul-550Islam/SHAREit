import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/transfer_models.dart';

class PairingCameraException implements Exception {
  const PairingCameraException(this.message);

  final String message;
}

abstract class PairingCamera {
  Stream<String> get codes;
  bool get isRunning;
  bool get hasPermission;
  bool get canToggleTorch;
  bool get torchIsOn;
  Widget buildPreview(BuildContext context);
  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  Future<void> dispose();
}

PairingCamera createPairingCamera() => MobilePairingCamera();

PairingCameraException cameraFailure(Object error) {
  if (error is PairingCameraException) {
    return error;
  }
  if (error is MobileScannerException) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => const PairingCameraException(
        'Camera access was not allowed. Review ShareBondhu camera permission '
        'in device Settings, or use the manual code.',
      ),
      MobileScannerErrorCode.unsupported => const PairingCameraException(
        'No supported camera is available. Use the manual pairing code instead.',
      ),
      _ => const PairingCameraException(
        'The camera could not start. Try again, or use the manual code.',
      ),
    };
  }
  return const PairingCameraException(
    'The camera is unavailable. Rebuild the app or use the manual code.',
  );
}

class MobilePairingCamera implements PairingCamera {
  MobilePairingCamera() {
    _subscription = _controller.barcodes.listen(
      (capture) {
        if (_disposed) {
          return;
        }
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null) {
            _codes.add(raw);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_disposed) {
          _codes.addError(cameraFailure(error));
        }
      },
    );
  }

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 300,
    returnImage: false,
  );
  final StreamController<String> _codes = StreamController<String>.broadcast(
    sync: true,
  );
  late final StreamSubscription<BarcodeCapture> _subscription;
  Future<void>? _starting;
  Future<void>? _disposing;
  bool _disposed = false;

  @override
  Stream<String> get codes => _codes.stream;
  @override
  bool get isRunning => !_disposed && _controller.value.isRunning;
  @override
  bool get hasPermission => !_disposed && _controller.value.hasCameraPermission;
  @override
  bool get canToggleTorch =>
      !_disposed && _controller.value.torchState != TorchState.unavailable;
  @override
  bool get torchIsOn =>
      !_disposed && _controller.value.torchState == TorchState.on;

  @override
  Widget buildPreview(BuildContext context) => MobileScanner(
    controller: _controller,
    useAppLifecycleState: false,
    tapToFocus: true,
    placeholderBuilder: (context) => const ColoredBox(color: Color(0xFF10291F)),
    errorBuilder: (context, error) => ColoredBox(
      color: const Color(0xFF10291F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            cameraFailure(error).message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  @override
  Future<void> start() async {
    if (_disposed) {
      throw const PairingCameraException('This camera session is closed.');
    }
    if (_starting != null) {
      await _starting;
      return;
    }
    final operation = _controller.start();
    _starting = operation;
    try {
      await operation;
      if (_disposed) {
        return;
      }
      final error = _controller.value.error;
      if (error != null || !_controller.value.isRunning) {
        throw cameraFailure(
          error ??
              const PairingCameraException(
                'The camera did not become ready. Try again.',
              ),
        );
      }
    } catch (error) {
      throw cameraFailure(error);
    } finally {
      _starting = null;
    }
  }

  @override
  Future<void> stop() async {
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    if (!_disposed) {
      await _controller.stop();
    }
  }

  @override
  Future<void> toggleTorch() async {
    if (isRunning && canToggleTorch) {
      await _controller.toggleTorch();
    }
  }

  @override
  Future<void> dispose() => _disposing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    await _subscription.cancel();
    final pending = _starting;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    try {
      await _controller.dispose();
    } finally {
      await _codes.close();
    }
  }
}

Future<String?> scanReceiverCode(BuildContext context) => Navigator.of(context)
    .push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const ScanPairingScreen(),
      ),
    );

class ScanPairingScreen extends StatefulWidget {
  const ScanPairingScreen({
    super.key,
    this.cameraFactory = createPairingCamera,
  });

  final PairingCamera Function() cameraFactory;

  @override
  State<ScanPairingScreen> createState() => _ScanPairingScreenState();
}

class _ScanPairingScreenState extends State<ScanPairingScreen>
    with WidgetsBindingObserver {
  late final PairingCamera _camera;
  late final StreamSubscription<String> _subscription;
  PairingCode? _candidate;
  String? _error;
  String? _notice;
  bool _starting = false;
  bool _stopping = false;
  bool _running = false;
  bool _wantRunning = false;
  bool _foreground = true;
  bool _disposing = false;
  bool _accepting = false;

  bool get _canUpdate => mounted && !_disposing;

  @override
  void initState() {
    super.initState();
    _camera = widget.cameraFactory();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
    _subscription = _camera.codes.listen(
      _detected,
      onError: (Object error, StackTrace stack) {
        if (_canUpdate) {
          setState(() => _error = cameraFailure(error).message);
          unawaited(_stopCamera());
        }
      },
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Restart is explicit. Returning to the app does not turn on the camera.
      return;
    }
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (background) {
      _foreground = false;
    }
    if (background ||
        (state == AppLifecycleState.inactive &&
            _running &&
            _camera.hasPermission)) {
      _wantRunning = false;
      if (_canUpdate) {
        setState(
          () => _notice = 'Camera paused. Tap Start camera when you are ready.',
        );
      }
      unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _wantRunning = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    unawaited(
      _camera.dispose().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_starting ||
        _stopping ||
        _running ||
        _candidate != null ||
        !_foreground) {
      return;
    }
    _wantRunning = true;
    setState(() {
      _starting = true;
      _error = null;
      _notice = null;
    });
    try {
      await _camera.start();
      if (!_canUpdate || !_foreground || !_wantRunning) {
        await _camera.stop();
        return;
      }
      setState(() => _running = _camera.isRunning);
    } catch (error) {
      if (_canUpdate && _foreground && _wantRunning) {
        setState(() => _error = cameraFailure(error).message);
      }
    } finally {
      if (_canUpdate) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopCamera() async {
    _wantRunning = false;
    if (_stopping) {
      return;
    }
    if (_canUpdate) {
      setState(() {
        _stopping = true;
        _running = false;
      });
    }
    try {
      await _camera.stop();
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _notice =
              'Close this screen if the camera does not stop normally.',
        );
      }
    } finally {
      if (_canUpdate) {
        setState(() => _stopping = false);
      }
    }
  }

  void _detected(String value) {
    if (!_canUpdate ||
        !_foreground ||
        !_wantRunning ||
        _candidate != null ||
        _accepting) {
      return;
    }
    PairingCode parsed;
    try {
      parsed = PairingCode.parse(value);
    } on TransferException {
      const message =
          'Not a supported ShareBondhu receiver code. URLs and other QR content are ignored.';
      if (_error != message) {
        setState(() => _error = message);
      }
      return;
    }
    _wantRunning = false;
    setState(() {
      _candidate = parsed;
      _error = null;
      _notice = null;
    });
    unawaited(_stopCamera());
  }

  Future<void> _accept() async {
    final code = _candidate;
    if (code == null || _accepting || !_foreground) {
      return;
    }
    setState(() => _accepting = true);
    await _stopCamera();
    if (mounted && !_disposing && _foreground) {
      Navigator.of(context).pop(code.encode());
    } else if (_canUpdate) {
      setState(() => _accepting = false);
    }
  }

  Future<void> _scanAgain() async {
    await _stopCamera();
    if (_canUpdate) {
      setState(() {
        _candidate = null;
        _error = null;
      });
      await _startCamera();
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _camera.toggleTorch();
      if (_canUpdate) {
        setState(() {});
      }
    } catch (_) {
      if (_canUpdate) {
        setState(
          () => _notice = 'The flashlight is unavailable on this device.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = _candidate;
    return Scaffold(
      key: const ValueKey('scan-pairing-scaffold'),
      appBar: AppBar(title: const Text('Scan receiver QR'), toolbarHeight: 70),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: <Widget>[
                Text(
                  'Point. Check. Connect.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Scan the QR shown inside ShareBondhu on the receiving phone. '
                  'Both phones must still use the same private Wi-Fi or hotspot.',
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 1.15,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _camera.buildPreview(context),
                        if (!_running)
                          ColoredBox(
                            color: const Color(0xFF10291F),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    candidate == null
                                        ? Icons.qr_code_scanner_rounded
                                        : Icons.qr_code_rounded,
                                    color: const Color(0xFFD5F391),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    candidate == null
                                        ? 'Camera is off'
                                        : 'Code captured · camera stopped',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_running)
                          IgnorePointer(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.72,
                                heightFactor: 0.72,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFD5F391),
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) _ScannerNote(message: _error!, error: true),
                if (_notice != null) _ScannerNote(message: _notice!),
                if (candidate == null)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        key: const ValueKey('start-camera-button'),
                        onPressed: _starting || _stopping || _running
                            ? null
                            : _startCamera,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _starting ? 'Starting camera' : 'Start camera',
                        ),
                      ),
                      if (_running)
                        OutlinedButton(
                          key: const ValueKey('pause-camera-button'),
                          onPressed: _stopCamera,
                          child: const Text('Pause'),
                        ),
                      if (_running && _camera.canToggleTorch)
                        OutlinedButton.icon(
                          key: const ValueKey('camera-torch-button'),
                          onPressed: _toggleTorch,
                          icon: Icon(
                            _camera.torchIsOn
                                ? Icons.flash_off_rounded
                                : Icons.flash_on_rounded,
                          ),
                          label: Text(
                            _camera.torchIsOn ? 'Light off' : 'Light on',
                          ),
                        ),
                    ],
                  )
                else
                  Container(
                    key: const ValueKey('scanned-code-confirmation'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Pairing code found',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Receiver: ${candidate.host}:${candidate.port}'),
                        const SizedBox(height: 8),
                        const Text(
                          'The format is valid; a connection has not been verified yet. '
                          'Confirm this is the device you intend to use. Expired codes may still scan.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Certificate SHA-256',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          candidate.fingerprint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            FilledButton(
                              key: const ValueKey('use-scanned-code-button'),
                              onPressed: _accepting || _stopping
                                  ? null
                                  : _accept,
                              child: const Text('Use this code'),
                            ),
                            OutlinedButton(
                              key: const ValueKey('scan-again-button'),
                              onPressed: _accepting || _stopping
                                  ? null
                                  : _scanAgain,
                              child: const Text('Scan again'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const ValueKey('manual-pairing-fallback-button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Use manual code instead'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Camera access is optional. This screen does not send files, open scanned links, '
                  'save camera images, or approve transfers. You still tap Ask to send afterwards.',
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
    );
  }
}

class _ScannerNote extends StatelessWidget {
  const _ScannerNote({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? colors.onErrorContainer : colors.onSurface,
        ),
      ),
    );
  }
}
