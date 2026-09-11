import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/transfer_models.dart' show isLocalIpv4;
import 'local_transfer_service.dart' show localIpv4Addresses;

enum InternetState { unknown, checking, offline, available, limited, error }

enum LocalNetworkState { unknown, checking, unavailable, available, error }

enum CoinServiceState {
  unconfigured,
  unknown,
  checking,
  reachable,
  unreachable,
  limited,
  error,
}

class ConnectivitySnapshot {
  ConnectivitySnapshot({
    this.internet = InternetState.unknown,
    this.localNetwork = LocalNetworkState.unknown,
    this.shareCoin = CoinServiceState.unconfigured,
    Iterable<String> localAddresses = const [],
    this.checkedAt,
    this.stale = false,
  }) : localAddresses = List<String>.unmodifiable(localAddresses);
  final InternetState internet;
  final LocalNetworkState localNetwork;
  final CoinServiceState shareCoin;
  final List<String> localAddresses;
  final DateTime? checkedAt;
  final bool stale;
  bool get canRequestRewards =>
      !stale && shareCoin == CoinServiceState.reachable;
  bool get hasLocalCandidate => localNetwork == LocalNetworkState.available;
  String get internetLabel => switch (internet) {
    InternetState.unknown => 'Not independently checked',
    InternetState.checking => 'Checking',
    InternetState.offline => 'Offline',
    InternetState.available => 'Available',
    InternetState.limited => 'Limited access',
    InternetState.error => 'Check failed',
  };
  String get localLabel => switch (localNetwork) {
    LocalNetworkState.unknown => 'Not checked',
    LocalNetworkState.checking => 'Checking interfaces',
    LocalNetworkState.unavailable => 'No private IPv4 found',
    LocalNetworkState.available => 'Private IPv4 candidate found',
    LocalNetworkState.error => 'Interface check failed',
  };
  String get serviceLabel => switch (shareCoin) {
    CoinServiceState.unconfigured => 'Backend not configured',
    CoinServiceState.unknown => 'Not checked',
    CoinServiceState.checking => 'Checking service',
    CoinServiceState.reachable => 'Reachable',
    CoinServiceState.unreachable => 'Unavailable',
    CoinServiceState.limited => 'Limited service',
    CoinServiceState.error => 'Service check failed',
  };
}

class ConnectivityService extends ValueNotifier<ConnectivitySnapshot> {
  ConnectivityService({
    this.localProbe = localIpv4Addresses,
    this.internetProbe,
    this.serviceProbe,
    this.timeout = const Duration(seconds: 5),
  }) : super(ConnectivitySnapshot()) {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Connectivity timeout must be positive.');
    }
  }
  final Future<List<String>> Function() localProbe;
  final Future<InternetState> Function()? internetProbe;
  final Future<CoinServiceState> Function()? serviceProbe;
  final Duration timeout;
  final StreamController<ConnectivitySnapshot> _changes =
      StreamController<ConnectivitySnapshot>.broadcast();
  Future<ConnectivitySnapshot>? _inFlight;
  int _generation = 0;
  bool _closed = false;
  bool _suspended = false;
  Stream<ConnectivitySnapshot> get changes => _changes.stream;

  Future<ConnectivitySnapshot> refresh() {
    if (_closed || _suspended) return Future<ConnectivitySnapshot>.value(value);
    final current = _inFlight;
    if (current != null) return current;
    final generation = ++_generation;
    final completion = Completer<ConnectivitySnapshot>();
    _inFlight = completion.future;
    _publish(
      ConnectivitySnapshot(
        internet: internetProbe == null
            ? InternetState.unknown
            : InternetState.checking,
        localNetwork: LocalNetworkState.checking,
        shareCoin: serviceProbe == null
            ? CoinServiceState.unconfigured
            : CoinServiceState.checking,
        localAddresses: value.localAddresses,
        checkedAt: value.checkedAt,
        stale: true,
      ),
    );
    unawaited(
      _check()
          .then(
            (snapshot) {
              if (!_closed && !_suspended && generation == _generation) {
                _publish(snapshot);
              }
              completion.complete(snapshot);
            },
            onError: (Object error, StackTrace stack) {
              final snapshot = ConnectivitySnapshot(
                internet: InternetState.error,
                localNetwork: LocalNetworkState.error,
                shareCoin: CoinServiceState.error,
                stale: true,
              );
              if (!_closed && !_suspended && generation == _generation) {
                _publish(snapshot);
              }
              completion.complete(snapshot);
            },
          )
          .whenComplete(() {
            if (identical(_inFlight, completion.future)) _inFlight = null;
          }),
    );
    return completion.future;
  }

  Future<ConnectivitySnapshot> _check() async {
    final localFuture = _local();
    final internetFuture = _internet();
    final serviceFuture = _service();
    final local = await localFuture;
    return ConnectivitySnapshot(
      internet: await internetFuture,
      localNetwork: local.$1,
      localAddresses: local.$2,
      shareCoin: await serviceFuture,
      checkedAt: DateTime.now().toUtc(),
    );
  }

  Future<(LocalNetworkState, List<String>)> _local() async {
    try {
      final found = await localProbe().timeout(timeout);
      final addresses = found.where(isLocalIpv4).toSet().toList()..sort();
      return (
        addresses.isEmpty
            ? LocalNetworkState.unavailable
            : LocalNetworkState.available,
        addresses,
      );
    } catch (_) {
      return (LocalNetworkState.error, <String>[]);
    }
  }

  Future<InternetState> _internet() async {
    final probe = internetProbe;
    if (probe == null) return InternetState.unknown;
    try {
      final state = await probe().timeout(timeout);
      return state == InternetState.checking ? InternetState.unknown : state;
    } catch (_) {
      return InternetState.error;
    }
  }

  Future<CoinServiceState> _service() async {
    final probe = serviceProbe;
    if (probe == null) return CoinServiceState.unconfigured;
    try {
      final state = await probe().timeout(timeout);
      return state == CoinServiceState.checking
          ? CoinServiceState.unknown
          : state;
    } catch (_) {
      return CoinServiceState.error;
    }
  }

  void _publish(ConnectivitySnapshot snapshot) {
    if (_closed) return;
    value = snapshot;
    if (!_closed) _changes.add(snapshot);
  }

  void suspend() {
    if (_closed) return;
    _suspended = true;
    _generation += 1;
    _inFlight = null;
    _publish(
      ConnectivitySnapshot(
        internet: value.internet,
        localNetwork: value.localNetwork,
        shareCoin: value.shareCoin,
        localAddresses: value.localAddresses,
        checkedAt: value.checkedAt,
        stale: true,
      ),
    );
  }

  void resume() {
    if (!_closed) _suspended = false;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    _inFlight = null;
    unawaited(_changes.close());
    super.dispose();
  }
}
