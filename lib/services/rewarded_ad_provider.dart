import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../screens/reward_center_screen.dart' show RewardedAdAdapter;
import 'share_coin_service.dart'
    show ShareCoinException, CoinErrorCode, newCoinRequestId;

enum AdProviderState {
  unavailable,
  loading,
  ready,
  showing,
  completed,
  dismissed,
  failed,
}

enum AdEvidenceResult { loaded, shown, completed, dismissed, failed }

class AdLoadContext {
  AdLoadContext({
    required this.attemptId,
    required this.rewardSessionId,
    required this.userId,
    required this.provider,
    required this.adUnit,
  });
  final String attemptId, rewardSessionId, userId, provider, adUnit;
  // A real SDK driver must bind userId + rewardSessionId to provider SSV
  // custom data and send verification evidence to the backend, not this UI.
  @override
  String toString() =>
      'AdLoadContext(provider: $provider, session identifiers redacted)';
}

class AdProviderEvidence {
  AdProviderEvidence({
    required String attemptId,
    required String rewardSessionId,
    required String provider,
    required String adUnit,
    required int sequence,
    required this.result,
    required DateTime timestamp,
    String? providerEventId,
  }) : attemptId = coinId(attemptId, 'attemptId'),
       rewardSessionId = coinId(rewardSessionId, 'rewardSessionId'),
       provider = coinId(provider, 'provider'),
       adUnit = coinText(adUnit, 'adUnit', max: 160),
       sequence = coinInt(sequence, 'sequence', min: 1),
       timestamp = coinTime(timestamp, 'evidence timestamp'),
       providerEventId = coinOptionalId(providerEventId, 'providerEventId') {
    if (result == AdEvidenceResult.completed && providerEventId == null) {
      throw const CoinModelException('provider completion reference');
    }
  }
  final String attemptId, rewardSessionId, provider, adUnit;
  final String? providerEventId;
  final int sequence;
  final AdEvidenceResult result;
  final DateTime timestamp;
  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'rewardSessionId': rewardSessionId,
    'provider': provider,
    'adUnit': adUnit,
    'providerEventId': providerEventId,
    'sequence': sequence,
    'result': result.name,
    'timestamp': timestamp.toIso8601String(),
  };
  @override
  String toString() =>
      'AdProviderEvidence(${result.name}, no trusted coin amount)';
}

abstract interface class RewardedAdSdkDriver {
  bool get configured;
  String? get provider;
  Stream<AdProviderEvidence> get evidence;
  Future<void> load(AdLoadContext context);
  Future<void> show(AdLoadContext context);
  Future<void> dismiss();
  Future<void> dispose();
}

class UnavailableRewardedAdSdkDriver implements RewardedAdSdkDriver {
  const UnavailableRewardedAdSdkDriver();
  @override
  bool get configured => false;
  @override
  String? get provider => null;
  @override
  Stream<AdProviderEvidence> get evidence =>
      const Stream<AdProviderEvidence>.empty();
  @override
  Future<void> load(AdLoadContext context) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> show(AdLoadContext context) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> dismiss() async {}
  @override
  Future<void> dispose() async {}
}

RewardedAdAdapter createSafeRewardedAdProvider() => RewardedAdProvider();

// Implements the existing Part 6 adapter. No financial amount is emitted.
// The default driver cannot load, play or complete an ad.
class RewardedAdProvider extends ValueNotifier<AdProviderState>
    implements RewardedAdAdapter {
  RewardedAdProvider({
    RewardedAdSdkDriver? driver,
    this.loadTimeout = const Duration(seconds: 30),
  }) : driver = driver ?? const UnavailableRewardedAdSdkDriver(),
       super(AdProviderState.unavailable) {
    if (loadTimeout <= Duration.zero ||
        loadTimeout > const Duration(minutes: 2)) {
      throw ArgumentError('Invalid ad timeout.');
    }
    _subscription = this.driver.evidence.listen(
      _evidence,
      onError: (Object error, StackTrace stack) {
        if (!_closed && !_completed) _fail();
      },
    );
  }
  final RewardedAdSdkDriver driver;
  final Duration loadTimeout;
  final StreamController<RewardedAdEvent> _events =
      StreamController<RewardedAdEvent>.broadcast();
  final StreamController<AdProviderEvidence> _evidenceEvents =
      StreamController<AdProviderEvidence>.broadcast();
  late final StreamSubscription<AdProviderEvidence> _subscription;
  AdLoadContext? _context;
  Completer<void>? _ready;
  Future<void>? _loading;
  int _generation = 0, _sequence = 0;
  bool _closed = false,
      _showRequested = false,
      _shown = false,
      _completed = false;
  AdProviderEvidence? _lastEvidence;
  @override
  bool get configured =>
      !_closed && driver.configured && driver.provider != null;
  @override
  String? get provider => driver.provider;
  @override
  Stream<RewardedAdEvent> get events => _events.stream;
  Stream<AdProviderEvidence> get completionEvidence => _evidenceEvents.stream;
  AdProviderEvidence? get lastEvidence => _lastEvidence;

  void _state(AdProviderState state) {
    if (!_closed) value = state;
  }

  void _emitEvent(RewardedAdEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  void _fail() {
    if (_closed || _completed) return;
    _state(AdProviderState.failed);
    final pending = _ready;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const ShareCoinException(CoinErrorCode.unavailable),
      );
    }
    final context = _context;
    if (context != null && !_events.isClosed) {
      _emitEvent(
        RewardedAdEvent(
          sessionId: context.rewardSessionId,
          type: RewardedAdEventType.failed,
        ),
      );
    }
  }

  @override
  Future<void> load(RewardSession session, AdConfiguration configuration) {
    if (!configured) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.notConfigured),
      );
    }
    if (_loading != null && _context?.rewardSessionId == session.sessionId) {
      return _loading!;
    }
    if (_loading != null || _showRequested && !_completed) {
      return Future.error(const ShareCoinException(CoinErrorCode.conflict));
    }
    if (session.source != CoinSource.adReward ||
        session.provider != provider ||
        configuration.provider != provider ||
        !configuration.rewardedEnabled ||
        configuration.premium ||
        configuration.units['rewarded'] == null) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final context = AdLoadContext(
      attemptId: newCoinRequestId(),
      rewardSessionId: session.sessionId,
      userId: session.userId,
      provider: session.provider,
      adUnit: configuration.units['rewarded']!,
    );
    final generation = ++_generation;
    _context = context;
    _sequence = 0;
    _shown = false;
    _showRequested = false;
    _completed = false;
    _lastEvidence = null;
    final ready = Completer<void>();
    _ready = ready;
    unawaited(
      ready.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    final complete = Completer<void>();
    _loading = complete.future;
    _state(AdProviderState.loading);
    Future<void>(() async {
      try {
        await driver.load(context).timeout(loadTimeout);
        await ready.future.timeout(loadTimeout);
        if (_closed ||
            generation != _generation ||
            value != AdProviderState.ready) {
          throw const ShareCoinException(CoinErrorCode.disposed);
        }
        complete.complete();
      } catch (_) {
        if (!_closed && generation == _generation) _fail();
        complete.completeError(
          const ShareCoinException(CoinErrorCode.unavailable),
        );
      } finally {
        if (identical(_loading, complete.future)) _loading = null;
      }
    });
    return complete.future;
  }

  @override
  Future<void> show(String sessionId) async {
    final context = _context;
    if (_closed ||
        context == null ||
        context.rewardSessionId != sessionId ||
        value != AdProviderState.ready ||
        _showRequested) {
      throw const ShareCoinException(CoinErrorCode.invalidRequest);
    }
    _showRequested = true;
    try {
      await driver.show(context);
    } catch (_) {
      _fail();
      throw const ShareCoinException(CoinErrorCode.unavailable);
    }
  }

  void _evidence(AdProviderEvidence evidence) {
    final context = _context;
    if (_closed ||
        context == null ||
        evidence.attemptId != context.attemptId ||
        evidence.rewardSessionId != context.rewardSessionId ||
        evidence.provider != context.provider ||
        evidence.adUnit != context.adUnit ||
        evidence.sequence <= _sequence ||
        _completed) {
      return;
    }
    switch (evidence.result) {
      case AdEvidenceResult.loaded:
        if (value != AdProviderState.loading) return;
        _sequence = evidence.sequence;
        _state(AdProviderState.ready);
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.ready,
          ),
        );
      case AdEvidenceResult.shown:
        if (!_showRequested || _shown || value != AdProviderState.ready) return;
        _sequence = evidence.sequence;
        _shown = true;
        _state(AdProviderState.showing);
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.shown,
          ),
        );
      case AdEvidenceResult.completed:
        if (!_shown ||
            !_showRequested ||
            value != AdProviderState.showing ||
            evidence.providerEventId == null) {
          return;
        }
        _sequence = evidence.sequence;
        _completed = true;
        _lastEvidence = evidence;
        _state(AdProviderState.completed);
        if (!_closed && !_evidenceEvents.isClosed) {
          _evidenceEvents.add(evidence);
        }
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.completed,
            providerEventId: evidence.providerEventId,
          ),
        );
      case AdEvidenceResult.dismissed:
        if (!_shown) {
          _fail();
          return;
        }
        _sequence = evidence.sequence;
        _state(AdProviderState.dismissed);
        _showRequested = false;
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.skipped,
          ),
        );
      case AdEvidenceResult.failed:
        _fail();
    }
  }

  @override
  Future<void> dismiss() async {
    if (_closed) return;
    _generation += 1;
    _context = null;
    _showRequested = false;
    _shown = false;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const ShareCoinException(CoinErrorCode.disposed));
    }
    _state(AdProviderState.dismissed);
    try {
      await driver.dismiss();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    _context = null;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const ShareCoinException(CoinErrorCode.disposed));
    }
    await _subscription.cancel();
    try {
      await driver.dispose();
    } catch (_) {}
    await _events.close();
    await _evidenceEvents.close();
    super.dispose();
  }
}
