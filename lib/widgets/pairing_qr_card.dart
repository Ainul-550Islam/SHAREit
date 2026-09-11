import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/transfer_models.dart';

class PairingQrCard extends StatefulWidget {
  const PairingQrCard({
    super.key,
    required this.code,
    required this.expiresAt,
    this.clock = DateTime.now,
  });

  final PairingCode code;
  final DateTime expiresAt;
  final DateTime Function() clock;

  @override
  State<PairingQrCard> createState() => _PairingQrCardState();
}

class _PairingQrCardState extends State<PairingQrCard> {
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _synchronize();
  }

  @override
  void didUpdateWidget(PairingQrCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  void _synchronize() {
    _remaining = widget.expiresAt.difference(widget.clock()).inSeconds;
    _timer?.cancel();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        final next = widget.expiresAt.difference(widget.clock()).inSeconds;
        if (next != _remaining) {
          setState(() => _remaining = next);
        }
        if (next <= 0) {
          _timer?.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _remaining > 0;
    final time =
        '${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}';
    return Container(
      key: const ValueKey('pairing-qr-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            active ? 'Let the sender scan this' : 'This invitation expired',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (active)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(260.0, constraints.maxWidth);
                return Center(
                  child: RepaintBoundary(
                    key: const ValueKey('pairing-qr-image-boundary'),
                    child: QrImageView(
                      key: const ValueKey('pairing-qr-image'),
                      data: widget.code.encode(),
                      size: size,
                      padding: const EdgeInsets.all(24),
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      semanticsLabel:
                          'Private ShareBondhu receiver pairing QR code',
                      errorStateBuilder: (context, error) => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'QR display is unavailable. Use Copy code below.',
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Icon(
                Icons.timer_off_outlined,
                size: 44,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            active
                ? 'New requests allowed for $time'
                : 'Stop receiving, then start a new session for a fresh QR.',
            key: const ValueKey('pairing-qr-expiry'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This QR contains the same private SB1 code as Copy code. '
            'Show it only to your intended sender. You still approve each batch.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
