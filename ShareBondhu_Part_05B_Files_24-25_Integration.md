# Part 5 — File 21–25

## Part 5B — File 24–25 + required integration files

## File 24 — `lib/services/connectivity_service.dart` — NEW

```dart
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
```

## File 25 — `lib/screens/share_coin_home_screen.dart` — NEW

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../services/connectivity_service.dart';
import '../services/share_coin_service.dart';

enum ShareCoinFileAction { send, receive, saved, history }

class ShareCoinHomeScreen extends StatefulWidget {
  const ShareCoinHomeScreen({super.key, this.service, this.onFileAction});
  final ShareCoinService? service;
  final ValueChanged<ShareCoinFileAction>? onFileAction;
  @override
  State<ShareCoinHomeScreen> createState() => _ShareCoinHomeScreenState();
}

class _ShareCoinHomeScreenState extends State<ShareCoinHomeScreen>
    with WidgetsBindingObserver {
  late final ShareCoinService _service;
  late final bool _ownsService;
  CoinData<ShareCoinBalance>? _wallet;
  CoinData<ShareCoinUser>? _user;
  String? _scopeKey;
  String? _notice;
  String? _busyAction;
  bool _loading = false;
  bool _closed = false;
  int _generation = 0;
  bool get _canUpdate => mounted && !_closed;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? ShareCoinService();
    _scopeKey = _service.accountKey;
    _service.addListener(_serviceChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _serviceChanged() {
    if (!_canUpdate) return;
    final next = _service.accountKey;
    if (next != _scopeKey) {
      _generation += 1;
      setState(() {
        _scopeKey = next;
        _wallet = null;
        _user = null;
        _busyAction = null;
        _loading = false;
        _notice = 'Account changed. Refresh to load this account.';
      });
    } else if (_service.cachedWallet == null && _wallet != null) {
      setState(() => _wallet = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      _service.suspend();
      if (_canUpdate) {
        setState(() {
          _loading = false;
          _busyAction = null;
          _notice =
              'ShareCoin refresh paused. File sharing has its own lifecycle.';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _service.resume();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_serviceChanged);
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || _busyAction != null) return;
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      await _service.connectivity.refresh();
      if (!_service.backendConfigured) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Backend and sign-in integration are not configured. No real funds are shown.',
          );
        }
        return;
      }
      if (!_service.hasAccount) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Account setup required. No authentication provider is integrated in this foundation.',
          );
        }
        return;
      }
      final user = await _service.getCurrentUser();
      final wallet = await _service.getCurrentWallet();
      if (_canUpdate &&
          generation == _generation &&
          scope == _service.accountKey) {
        setState(() {
          _user = user;
          _wallet = wallet;
          _scopeKey = scope;
        });
      }
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        setState(() {
          _wallet = _service.cachedWallet;
          _notice = _errorText(error);
        });
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _errorText(Object error) => error is ShareCoinException
      ? error.message
      : 'ShareCoin could not load this information. No local reward or payout was created.';
  String _time(DateTime date) => date.toLocal().toString().split('.').first;
  String _coins(int coins) => coins.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );

  void _fileAction(ShareCoinFileAction action) {
    final callback = widget.onFileAction;
    if (callback != null) {
      callback(action);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(action);
    }
  }

  Future<void> _info(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _details(
    String title,
    Future<List<Widget>> Function() load,
  ) async {
    if (_busyAction != null || _loading) return;
    final scope = _service.accountKey;
    final generation = ++_generation;
    setState(() => _busyAction = title);
    try {
      final rows = await load();
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: _service,
          builder: (context, child) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: scope != _service.accountKey
                  ? const Text('Account changed. Close this view and refresh.')
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                      ),
                      child: ListView(shrinkWrap: true, children: rows),
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info(title, _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
      }
    }
  }

  Widget _origin<T>(CoinData<T> data) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      '${data.cached ? 'Cached data' : 'Backend response'} · ${_time(data.serverTime)}',
      style: const TextStyle(fontSize: 12),
    ),
  );

  Future<void> _ads() => _details('Watch Ads', () async {
    final data = await _service.getAdConfiguration();
    return <Widget>[
      _origin(data),
      Text('Provider: ${data.data.provider ?? 'Not configured'}'),
      Text(
        'Rewarded ads: ${data.data.rewardedEnabled && !data.data.premium ? 'Enabled in backend configuration' : 'Disabled'}',
      ),
      Text(
        'Cooldown: ${data.data.cooldownSeconds}s · Daily limit: ${data.data.dailyLimit}',
      ),
      Text('Premium/no-ads: ${data.data.premium ? 'Yes' : 'No'}'),
      const SizedBox(height: 12),
      const Text(
        'No ad SDK is connected in Part 5. A future provider completion is only an event claim; the backend must verify it before crediting ShareCoin.',
      ),
    ];
  });

  Future<void> _offers() => _details('Offers', () async {
    final data = await _service.getOffers(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text(
        'Catalog foundation. Starting/installing an app is not proof of earning a reward.',
      ),
      if (data.data.items.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('No offers returned for this account.'),
        ),
      for (final offer in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.apps_rounded),
          title: Text(offer.title),
          subtitle: Text(
            '${offer.publisher} · ${offer.category.name}\nPotential reward: ${offer.rewardCoins} ShareCoin · ${offer.status.name}',
          ),
        ),
      if (data.data.info.hasNext)
        Text(
          'Showing ${data.data.items.length} of ${data.data.info.total}. The service supports paginated queries; this dashboard is a bounded catalog preview.',
        ),
    ];
  });

  Future<void> _promotions() => _details('Promotions', () async {
    final data = await _service.getPromotions(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text('Opening a campaign never credits coins in this client.'),
      if (data.data.items.isEmpty) const Text('No promotions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined),
          title: Text(item.title),
          subtitle: Text(
            '${item.advertiser}\nPotential reward: ${item.rewardCoins} ShareCoin · ${item.status.name}\nEnds ${_time(item.endsAt)}',
          ),
        ),
    ];
  });

  Future<void> _daily() => _details('Daily Reward', () async {
    final data = await _service.getDailyRewardConfiguration();
    return <Widget>[
      _origin(data),
      Text('Backend streak day: ${data.data.streakDay}'),
      Text(
        'Backend eligibility: ${data.data.eligible ? 'Eligible according to this response' : 'Not eligible'}',
      ),
      for (var index = 0; index < data.data.dayRewards.length; index += 1)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Day ${index + 1}'),
          trailing: Text('${data.data.dayRewards[index]} ShareCoin'),
        ),
      Text('Next eligible: ${_time(data.data.nextEligibleAt)}'),
      const SizedBox(height: 12),
      const Text(
        'This is the server-configured policy view, not a local claim button. Device date does not award money.',
      ),
    ];
  });

  Future<void> _referral() => _details('Referral', () async {
    final data = await _service.getReferral();
    return <Widget>[
      _origin(data),
      SelectableText(
        data.data.referralCode,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      Text(
        'Invited: ${data.data.invitedCount} · Pending: ${data.data.pendingCount} · Qualified: ${data.data.qualifiedCount}',
      ),
      Text('Backend referral earnings: ${data.data.earnedCoins} ShareCoin'),
      Text('Status: ${data.data.status.name}'),
      if (data.data.referralUrl != null)
        SelectableText(data.data.referralUrl.toString()),
      const SizedBox(height: 12),
      const Text(
        'Referrals require backend qualification and anti-abuse checks. Multiple local accounts do not earn rewards.',
      ),
      TextButton(
        onPressed: () async {
          if (data.accountKey == _service.accountKey) {
            await Clipboard.setData(
              ClipboardData(text: data.data.referralCode),
            );
          }
        },
        child: const Text('Copy referral code'),
      ),
    ];
  });

  Future<void> _transactions() => _details('Transactions', () async {
    final data = await _service.getTransactionHistory(
      query: OfferQuery(pageSize: 30),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty) const Text('No transactions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          isThreeLine: true,
          title: Text(item.signedAmount),
          subtitle: Text(
            '${item.source.name} · ${item.status.name}\n${_time(item.createdAt)} · ${item.transactionId}\n${item.description}',
          ),
        ),
      if (data.data.info.hasNext)
        const Text(
          'More transactions are available through the paginated service. Rejected and reversed entries are not hidden.',
        ),
    ];
  });

  Future<void> _withdrawals() => _details('Withdrawal History', () async {
    final data = await _service.getWithdrawalHistory(
      query: OfferQuery(pageSize: 20),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty)
        const Text('No withdrawal records returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${item.requestedCoins} ShareCoin · ${item.status.name}'),
          subtitle: Text(
            '${item.method.name} · ${item.maskedDestination}\n${item.rate.formatMinor(item.finalPayoutMinor)} · ${item.withdrawalId}\n${item.rejectionReason ?? 'Status provided by the backend'}',
          ),
        ),
    ];
  });

  Future<void> _withdraw() async {
    if (_busyAction != null || _loading) return;
    if (!_service.backendConfigured ||
        !_service.hasAccount ||
        !_service.connectivity.value.canRequestRewards) {
      await _info(
        'Withdrawals unavailable',
        'A backend-authenticated account, reachable ShareCoin service, fresh balance, payout policy and connected saved destination are required. No submission was made. bKash, Nagad, Rocket, PayPal and Bank are configuration options only, not connected providers.',
      );
      return;
    }
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() => _busyAction = 'Withdraw');
    try {
      final user = await _service.getCurrentUser(allowCached: false);
      if (!user.data.mayRequestRewards) {
        throw const ShareCoinException(CoinErrorCode.restricted);
      }
      final wallet = await _service.getCurrentWallet(allowCached: false);
      final policy = await _service.getWithdrawalPolicy(allowCached: false);
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _WithdrawalDialog(
          service: _service,
          wallet: wallet,
          policy: policy,
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info('Withdraw', _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('share-coin-home'),
      appBar: AppBar(
        title: const Text('ShareCoin'),
        toolbarHeight: 70,
        actions: <Widget>[
          IconButton(
            key: const ValueKey('refresh-share-coin'),
            onPressed: _loading || _busyAction != null ? null : _refresh,
            tooltip: 'Refresh ShareCoin status',
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
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  _balance(theme),
                  if (_loading || _busyAction != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_notice != null) _CoinNotice(message: _notice!),
                  const SizedBox(height: 22),
                  _section('Earn', 'Actions create claims, not local money.'),
                  _grid(<Widget>[
                    _tile(
                      'Watch Ads',
                      Icons.play_circle_outline_rounded,
                      _ads,
                      'SDK not connected',
                      key: 'coin-watch-ads',
                    ),
                    _tile(
                      'Offers',
                      Icons.apps_rounded,
                      _offers,
                      'Provider verification',
                      key: 'coin-offers',
                    ),
                    _tile(
                      'Promotions',
                      Icons.campaign_outlined,
                      _promotions,
                      'Campaign policy',
                      key: 'coin-promotions',
                    ),
                    _tile(
                      'Daily Reward',
                      Icons.calendar_today_outlined,
                      _daily,
                      'Server eligibility',
                      key: 'coin-daily',
                    ),
                    _tile(
                      'Referral',
                      Icons.people_outline_rounded,
                      _referral,
                      'Qualified invites',
                      key: 'coin-referral',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Wallet',
                    'Only backend-confirmed records are displayed.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Transactions',
                      Icons.receipt_long_outlined,
                      _transactions,
                      'Credits, debits, reversals',
                      key: 'coin-transactions',
                    ),
                    _tile(
                      'Withdraw',
                      Icons.account_balance_outlined,
                      _withdraw,
                      'Backend/provider required',
                      key: 'coin-withdraw',
                    ),
                    _tile(
                      'Withdrawal History',
                      Icons.history_rounded,
                      _withdrawals,
                      'Server payout status',
                      key: 'coin-withdrawal-history',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'File Sharing',
                    'Internet rewards never block your nearby files.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Send Files',
                      Icons.upload_rounded,
                      () => _fileAction(ShareCoinFileAction.send),
                      'Original file flow',
                      key: 'coin-send-files',
                      local: true,
                    ),
                    _tile(
                      'Receive Files',
                      Icons.download_rounded,
                      () => _fileAction(ShareCoinFileAction.receive),
                      'QR or manual pairing',
                      key: 'coin-receive-files',
                      local: true,
                    ),
                    _tile(
                      'Saved Files',
                      Icons.folder_copy_outlined,
                      () => _fileAction(ShareCoinFileAction.saved),
                      'Your received copies',
                      key: 'coin-saved-files',
                      local: true,
                    ),
                    _tile(
                      'History',
                      Icons.fact_check_outlined,
                      () => _fileAction(ShareCoinFileAction.history),
                      'Existing history & SHA-256',
                      key: 'coin-file-history',
                      local: true,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Status',
                    'Local interfaces, internet and backend are separate.',
                  ),
                  ValueListenableBuilder<ConnectivitySnapshot>(
                    valueListenable: _service.connectivity,
                    builder: (context, status, child) => Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Internet: ${status.internetLabel}',
                            key: const ValueKey('coin-internet-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Wi-Fi/local network: ${status.localLabel}',
                            key: const ValueKey('coin-local-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'ShareCoin service: ${status.serviceLabel}',
                            key: const ValueKey('coin-service-status'),
                          ),
                          if (status.stale)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('Status is stale or checking.'),
                            ),
                          const SizedBox(height: 12),
                          const Text(
                            'An IPv4 interface does not prove Wi-Fi type or peer reachability. No public internet probe is configured by default.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Foundation only. No ad attribution, login provider, advertiser payout or cash withdrawal provider is connected by this build. '
                    'ShareCoin is not locally redeemable money. File sharing keeps its existing TLS and approval rules.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
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

  Widget _balance(ThemeData theme) {
    final wallet = _wallet;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF164D3C),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.toll_outlined, color: Color(0xFFD5F391)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SHAREBONDHU REWARDS',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'ShareCoin Balance',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            wallet == null
                ? 'Wallet unavailable'
                : '${_coins(wallet.data.available)} ShareCoin',
            key: const ValueKey('share-coin-balance'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (wallet == null)
            Text(
              !_service.hasAccount
                  ? 'Account setup required. A backend-confirmed wallet is needed before any funds can be shown.'
                  : 'Connect to the ShareCoin service and refresh to confirm the current balance.',
              style: TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pending: ${_coins(wallet.data.pending)} ShareCoin',
                  style: const TextStyle(color: Color(0xFFE0EDE5)),
                ),
                const SizedBox(height: 8),
                Text(
                  '${wallet.cached ? 'CACHED · not a live spendable-balance check' : 'Backend response'}\nLast updated: ${_time(wallet.data.updatedAt)}',
                  style: const TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
                ),
              ],
            ),
          if (_user != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${_user!.data.displayName} · ${_user!.data.status.name}',
                style: const TextStyle(color: Color(0xFFD5F391)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _grid(List<Widget> tiles) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560
          ? 3
          : constraints.maxWidth >= 340 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tiles
            .map((tile) => SizedBox(width: width, child: tile))
            .toList(),
      );
    },
  );

  Widget _tile(
    String title,
    IconData icon,
    VoidCallback action,
    String description, {
    required String key,
    bool local = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(18),
        onTap: local || !_loading && _busyAction == null ? action : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colors.primary, size: 26),
              const SizedBox(height: 13),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinNotice extends StatelessWidget {
  const _CoinNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(message),
  );
}

class _WithdrawalDialog extends StatefulWidget {
  const _WithdrawalDialog({
    required this.service,
    required this.wallet,
    required this.policy,
  });
  final ShareCoinService service;
  final CoinData<ShareCoinBalance> wallet;
  final CoinData<WithdrawalPolicy> policy;
  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final TextEditingController _amount = TextEditingController();
  PayoutMethodConfig? _method;
  String _idempotencyKey = newCoinRequestId();
  String? _error;
  bool _sending = false;
  bool _uncertain = false;
  WithdrawalRequest? _result;
  bool get _ownerMatches =>
      widget.wallet.accountKey == widget.service.accountKey;

  @override
  void initState() {
    super.initState();
    _method = widget.policy.data.methods
        .where((method) => method.usable)
        .firstOrNull;
    _amount.text = widget.policy.data.minimumCoins.toString();
    widget.service.addListener(_update);
    widget.service.connectivity.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_update);
    widget.service.connectivity.removeListener(_update);
    _amount.dispose();
    super.dispose();
  }

  int? get _coins {
    try {
      return coinInt(int.tryParse(_amount.text.trim()), 'coins', min: 1);
    } catch (_) {
      return null;
    }
  }

  int? get _finalMinor {
    final coins = _coins;
    final method = _method;
    if (coins == null || method == null) return null;
    try {
      final value = widget.policy.data.rate.grossMinor(coins) - method.feeMinor;
      return value >= 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _edited() {
    if (!_sending && !_uncertain && _result == null) {
      setState(() {
        _idempotencyKey = newCoinRequestId();
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    final coins = _coins;
    final method = _method;
    final payout = _finalMinor;
    if (_sending ||
        _uncertain ||
        _result != null ||
        !_ownerMatches ||
        !widget.service.connectivity.value.canRequestRewards) {
      return;
    }
    if (coins == null || method == null || payout == null) {
      setState(
        () => _error = 'Enter a valid whole-coin amount and choose a connected destination.',
      );
      return;
    }
    if (coins < widget.policy.data.minimumCoins) {
      setState(() => _error = 'Amount is below the withdrawal minimum.');
      return;
    }
    if (coins > widget.wallet.data.available) {
      setState(() => _error = 'Amount exceeds the displayed backend balance.');
      return;
    }
    setState(() => _sending = true);
    try {
      final response = await widget.service.requestWithdrawal(
        WithdrawalIntent(
          userId: widget.wallet.data.userId,
          coins: coins,
          method: method.method,
          destinationReference: method.destinationReference!,
          policyVersion: widget.policy.data.version,
          expectedFeeMinor: method.feeMinor,
          expectedFinalMinor: payout,
          idempotencyKey: _idempotencyKey,
        ),
      );
      if (mounted && _ownerMatches) setState(() => _result = response.data);
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(() {
          _error = error is ShareCoinException
              ? error.message
              : 'The request could not be confirmed.';
          _uncertain = error is! ShareCoinException || error.outcomeUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkRequest() async {
    if (_sending || !_uncertain || !_ownerMatches) return;
    setState(() => _sending = true);
    try {
      final result = await widget.service.getWithdrawalByKey(_idempotencyKey);
      if (mounted && _ownerMatches) {
        setState(() {
          _result = result.data;
          _uncertain = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(
          () => _error = error is ShareCoinException
              ? error.message
              : 'The request status is still unknown.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy.data;
    final method = _method;
    final payout = _finalMinor;
    final online = widget.service.connectivity.value.canRequestRewards;
    return AlertDialog(
      title: const Text('Withdrawal request'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: !_ownerMatches
              ? const Text('Account changed. Close this form and refresh.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Backend balance: ${widget.wallet.data.available} ShareCoin',
                    ),
                    Text('Minimum: ${policy.minimumCoins} ShareCoin'),
                    Text(
                      'Rate: ${policy.rate.coinUnits} ShareCoin = ${policy.rate.formatMinor(policy.rate.minorUnits)}',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('coin-withdraw-amount'),
                      controller: _amount,
                      enabled: !_sending && !_uncertain && _result == null,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _edited(),
                      decoration: const InputDecoration(
                        labelText: 'Requested ShareCoin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (policy.methods.isNotEmpty)
                      DropdownButtonFormField<PayoutMethod>(
                        initialValue: method?.method,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Payout method',
                          border: OutlineInputBorder(),
                        ),
                        items: policy.methods
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.method,
                                enabled: entry.usable,
                                child: Text(
                                  '${entry.method.name}${entry.usable ? '' : ' · not connected'}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sending || _uncertain || _result != null
                            ? null
                            : (value) {
                                setState(
                                  () => _method = policy.methods
                                      .where((entry) => entry.method == value)
                                      .firstOrNull,
                                );
                                _edited();
                              },
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Saved destination: ${method?.maskedDestination ?? 'Not configured'}',
                    ),
                    Text(
                      'Processing fee: ${method == null ? 'Unavailable' : policy.rate.formatMinor(method.feeMinor)}',
                    ),
                    Text(
                      'Estimated final payout: ${payout == null ? 'Unavailable' : policy.rate.formatMinor(payout)}',
                    ),
                    if (policy.activeRequestIds.isNotEmpty)
                      const Text(
                        'Another withdrawal is active. Submission is disabled.',
                      ),
                    if (!online)
                      const Text(
                        'Service unavailable. No offline withdrawal submission.',
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Submission requests backend validation; it is not proof of payout. The server must recheck the balance, fees, policy and destination.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!),
                      ),
                    if (_uncertain)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SelectableText(
                          'Check backend withdrawal history using request key: $_idempotencyKey. Do not create another request blindly.',
                        ),
                      ),
                    if (_result != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Backend status: ${_result!.status.name}\nReference: ${_result!.withdrawalId}\nBalance must be refreshed from the backend.',
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_uncertain)
          OutlinedButton(
            key: const ValueKey('check-coin-withdrawal-status'),
            onPressed: _sending || !_ownerMatches || !online
                ? null
                : _checkRequest,
            child: const Text('Check request status'),
          ),
        if (_result == null)
          FilledButton(
            key: const ValueKey('submit-coin-withdrawal'),
            onPressed:
                !_ownerMatches ||
                    _sending ||
                    _uncertain ||
                    !online ||
                    method == null ||
                    policy.activeRequestIds.isNotEmpty
                ? null
                : _submit,
            child: Text(_sending ? 'Submitting request' : 'Request withdrawal'),
          ),
      ],
    );
  }
}
```

## Required integration replacements — complete files

## File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.5.0+5

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: 12.2.0
  basic_utils: 5.8.2
  crypto: 3.0.7
  path_provider: 2.1.6
  share_plus: 13.3.0
  qr_flutter: 4.1.0
  mobile_scanner: 7.4.0
  path: 1.9.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0

flutter:
  uses-material-design: true
```

## File 4 — `lib/screens/home_screen.dart` — UPDATED

```dart
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
```

## File 20 — `test/transfer_progress_test.dart` — UPDATED

```dart
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/saved_transfer.dart';
import 'package:sharebondhu/models/transfer_activity.dart';
import 'package:sharebondhu/models/transfer_models.dart';
import 'package:sharebondhu/screens/history_screen.dart';
import 'package:sharebondhu/screens/nearby_screen.dart';
import 'package:sharebondhu/services/local_transfer_service.dart';
import 'package:sharebondhu/services/transfer_history_service.dart';
import 'package:sharebondhu/services/transfer_progress_controller.dart';
import 'package:sharebondhu/widgets/transfer_progress_panel.dart';
import 'package:sharebondhu/widgets/transfer_result_panel.dart';

import 'package:sharebondhu/models/share_coin_models.dart';
import 'package:sharebondhu/models/user_models.dart';
import 'package:sharebondhu/services/share_coin_service.dart';
import 'package:sharebondhu/services/connectivity_service.dart';
import 'package:sharebondhu/screens/share_coin_home_screen.dart';
import 'package:sharebondhu/screens/home_screen.dart';

import 'widget_test.dart' as baseline;

class ProgressProbe {
  ProgressProbe({
    List<int> sizes = const <int>[1000],
    this.role = TransferRole.sender,
  }) {
    files = List<OfferedFile>.generate(
      sizes.length,
      (i) => OfferedFile(
        id: randomTransferId(),
        name: 'file-$i.bin',
        size: sizes[i],
      ),
    );
    controller = TransferProgressController(
      clock: () => time,
      autoRefresh: false,
    );
    epoch = controller.open(role);
    addTearDown(controller.dispose);
  }
  final TransferRole role;
  final String id = randomTransferId();
  String attempt = randomTransferId();
  late List<OfferedFile> files;
  late TransferProgressController controller;
  late int epoch;
  int sequence = 0;
  Duration time = Duration.zero;
  TransferActivity get state => controller.value;

  TransferProgress frame(
    TransferPhase phase, {
    int? bytes,
    int? done,
    int? checked,
    int? index,
    int? fileBytes,
    bool commit = false,
    TransferReceipt? receipt,
  }) {
    final active = index ?? state.progress.currentFileIndex;
    return TransferProgress(
      phase: phase,
      message: 'Engine event: ${phase.name}',
      transferId: id,
      attemptId: attempt,
      sequence: ++sequence,
      manifest: files,
      totalBytes: files.fold<int>(0, (sum, file) => sum + file.size),
      totalFiles: files.length,
      processedBytes: bytes ?? state.batchBytes,
      completedFiles: done ?? state.completedFiles,
      verifiedFiles: checked ?? state.verifiedFiles,
      currentFileIndex: active,
      currentFileTotalBytes:
          active == null || active >= files.length || active < 0
          ? null
          : files[active].size,
      currentFileBytes: active == null
          ? null
          : fileBytes ?? state.fileBytes ?? 0,
      fileName: active == null || active >= files.length || active < 0
          ? null
          : files[active].name,
      commitStarted: commit,
      receipt: receipt,
    );
  }

  bool step(
    TransferPhase phase, {
    int? bytes,
    int? done,
    int? checked,
    int? index,
    int? fileBytes,
    bool commit = false,
    TransferReceipt? receipt,
  }) => controller.addEngineEvent(
    epoch,
    frame(
      phase,
      bytes: bytes,
      done: done,
      checked: checked,
      index: index,
      fileBytes: fileBytes,
      commit: commit,
      receipt: receipt,
    ),
  );

  void start() {
    if (role == TransferRole.sender) step(TransferPhase.connecting);
    step(TransferPhase.awaitingApproval);
    step(TransferPhase.approved);
    step(TransferPhase.preparing, index: 0, fileBytes: 0);
    step(
      role == TransferRole.sender
          ? TransferPhase.sending
          : TransferPhase.receiving,
    );
  }

  TransferReceipt receipt({String? digest}) => TransferReceipt(
    id: id,
    senderName: 'Test peer',
    completedAt: DateTime.utc(2026, 9, 8),
    files: files.map(
      (file) => ReceivedFile(
        id: file.id,
        name: file.name,
        size: file.size,
        digest: digest ?? sha256.convert(<int>[1]).toString(),
      ),
    ),
  );

  void finishBytes() {
    for (var index = 0; index < files.length; index += 1) {
      if (index > 0) step(TransferPhase.preparing, index: index, fileBytes: 0);
      final bytes = files
          .take(index + 1)
          .fold<int>(0, (sum, file) => sum + file.size);
      step(
        role == TransferRole.sender
            ? TransferPhase.sending
            : TransferPhase.receiving,
        index: index,
        fileBytes: files[index].size,
        bytes: bytes,
        done: index + 1,
        checked: role == TransferRole.sender ? index + 1 : 0,
      );
    }
  }
}

// Test-only sender: production NearbyScreen still defaults to LocalSender.new.
class ControlledSender extends LocalSender {
  final Completer<TransferReceipt> completion = Completer<TransferReceipt>();
  late IncomingOffer offer;
  void Function(TransferProgress)? callback;
  int sequence = 0;
  int cancellations = 0;
  @override
  Future<TransferReceipt> send({
    required PairingCode code,
    required List<ShareFile> files,
    required String senderName,
    void Function(TransferProgress)? onProgress,
  }) {
    offer = createOutgoingOffer(files, senderName);
    callback = onProgress;
    emit(TransferPhase.connecting);
    emit(TransferPhase.awaitingApproval);
    return completion.future;
  }

  void emit(
    TransferPhase phase, {
    bool full = false,
    TransferReceipt? receipt,
  }) {
    callback?.call(
      TransferProgress(
        phase: phase,
        message: 'Controlled UI-test event',
        transferId: offer.id,
        attemptId: offer.id,
        sequence: ++sequence,
        manifest: offer.files,
        totalBytes: offer.totalBytes,
        totalFiles: offer.files.length,
        processedBytes: full ? offer.totalBytes : 0,
        completedFiles: full ? offer.files.length : 0,
        verifiedFiles: full ? offer.files.length : 0,
        receipt: receipt,
      ),
    );
  }

  @override
  void cancel() {
    cancellations += 1;
    if (!completion.isCompleted) {
      completion.completeError(const TransferCancelled());
    }
  }

  void fail() {
    if (!completion.isCompleted) {
      completion.completeError(
        const TransferException('Test source became unreadable.'),
      );
    }
  }

  void confirm() {
    final receipt = TransferReceipt(
      id: offer.id,
      senderName: offer.senderName,
      completedAt: DateTime.utc(2026, 9, 8),
      files: offer.files.map(
        (file) => ReceivedFile(
          id: file.id,
          name: file.name,
          size: file.size,
          digest: sha256.convert(<int>[1]).toString(),
        ),
      ),
    );
    emit(TransferPhase.approved);
    emit(TransferPhase.sending, full: true);
    emit(TransferPhase.completed, full: true, receipt: receipt);
    completion.complete(receipt);
  }
}

Future<void> mountSender(WidgetTester tester, ControlledSender sender) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: NearbyScreen(
        mode: NearbyMode.send,
        files: <ShareFile>[baseline.sampleFile(size: 3)],
        senderFactory: () => sender,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pairing-code-field')),
    baseline.qrTestCode().encode(),
  );
  final button = find.byKey(const ValueKey('ask-to-send-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  registerPart5Tests();
  group('Part 4 controller', () {
    test('01 initial idle state', () {
      final p = ProgressProbe();
      expect(p.state.phase, TransferPhase.idle);
      expect(p.state.percentage, 0);
      expect(p.state.eta, isNull);
      expect(p.state.canCancel, isFalse);
    });
    test('02 connecting state', () {
      final p = ProgressProbe();
      expect(p.step(TransferPhase.connecting), isTrue);
      expect(p.state.phase, TransferPhase.connecting);
      expect(p.state.batchBytes, 0);
    });
    test('03 waiting for approval has no file bytes', () {
      final p = ProgressProbe();
      p.step(TransferPhase.connecting);
      p.step(TransferPhase.awaitingApproval);
      expect(p.state.phase, TransferPhase.awaitingApproval);
      expect(p.state.currentFileNumber, isNull);
    });
    test('04 approval is a distinct real-engine state', () {
      final p = ProgressProbe();
      p.step(TransferPhase.connecting);
      p.step(TransferPhase.awaitingApproval);
      p.step(TransferPhase.approved);
      expect(p.state.phase, TransferPhase.approved);
      expect(p.state.successfulFiles, 0);
    });
    test('05 sending counters come from events', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
      expect(p.state.phase, TransferPhase.sending);
      expect(p.state.batchBytes, 100);
      expect(p.state.fileBytes, 100);
    });
    test('06 receiver uses the same progress abstraction', () {
      final p = ProgressProbe(role: TransferRole.receiver)..start();
      p.step(TransferPhase.receiving, bytes: 80, fileBytes: 80);
      expect(p.state.phase, TransferPhase.receiving);
      expect(p.state.role, TransferRole.receiver);
    });
    test('07 verifying is not completed', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.verifying, commit: true);
      expect(p.state.phase, TransferPhase.verifying);
      expect(p.state.percentage, 100);
      expect(p.state.confirmed, isFalse);
    });
    test('08 completion requires an engine-validated receipt boundary', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed);
      expect(p.state.confirmed, isFalse);
      expect(p.state.terminal, isFalse);
      p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt());
      expect(p.state.phase, TransferPhase.completed);
      expect(p.state.successfulFiles, 1);
    });
    test('09 definitive failure preserves real byte counts', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 45, fileBytes: 45);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('File read failed.'),
      );
      expect(p.state.phase, TransferPhase.failed);
      expect(p.state.batchBytes, 45);
      expect(p.state.unsuccessfulFiles, 1);
    });
    test('10 requested cancellation is not prematurely terminal', () {
      final p = ProgressProbe()..start();
      p.controller.requestCancellation(p.epoch);
      expect(p.state.cancelRequested, isTrue);
      expect(p.state.terminal, isFalse);
      p.controller.finishFailure(p.epoch, const TransferCancelled());
      expect(p.state.phase, TransferPhase.canceled);
    });
    test(
      '11 zero-byte file uses staged-file completion without division by zero',
      () {
        final p = ProgressProbe(sizes: <int>[0])..start();
        expect(p.state.fraction, 0);
        p.finishBytes();
        expect(p.state.percentage, 100);
        expect(p.state.confirmed, isFalse);
        p.step(TransferPhase.completed, receipt: p.receipt());
        expect(p.state.confirmed, isTrue);
        expect(p.state.batchBytes, 0);
      },
    );
    test('12 single-file name index and byte totals', () {
      final p = ProgressProbe(sizes: <int>[72])..start();
      p.step(TransferPhase.sending, bytes: 20, fileBytes: 20);
      expect(p.state.fileName, 'file-0.bin');
      expect(p.state.currentFileNumber, 1);
      expect(p.state.fileTotalBytes, 72);
    });
    test('13 multiple files keep cumulative bytes and separate file bytes', () {
      final p = ProgressProbe(sizes: <int>[100, 200])..start();
      p.step(
        TransferPhase.sending,
        bytes: 100,
        fileBytes: 100,
        done: 1,
        checked: 1,
      );
      p.step(TransferPhase.preparing, index: 1, fileBytes: 0);
      p.step(TransferPhase.sending, bytes: 150, fileBytes: 50);
      expect(p.state.fileBytes, 50);
      expect(p.state.batchBytes, 150);
      expect(p.state.totalBytes, 300);
      expect(p.state.currentFileNumber, 2);
      expect(p.state.completedFiles, 1);
    });
    test('14 exactly 100 percent bytes does not imply delivery', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      expect(p.state.fraction, 1);
      expect(p.state.successfulFiles, 0);
      expect(p.state.receipt, isNull);
    });
    test('15 invalid over-range and negative counters are safely bounded', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: -30, fileBytes: -20, done: -4);
      expect(p.state.batchBytes, 0);
      expect(p.state.fileBytes, 0);
      p.step(TransferPhase.sending, bytes: 9999, fileBytes: 9999, done: 99);
      expect(p.state.percentage, 100);
      expect(p.state.completedFiles, 1);
      expect(p.state.confirmed, isFalse);
      expect(p.state.warning, isNotNull);
    });
    test(
      '16 cancellation during transfer rejects duplicate cancel requests',
      () {
        final p = ProgressProbe()..start();
        expect(p.controller.requestCancellation(p.epoch), isTrue);
        expect(p.controller.requestCancellation(p.epoch), isFalse);
        p.controller.finishFailure(p.epoch, const TransferCancelled());
        expect(p.state.successfulFiles, 0);
      },
    );
    test('17 a real completion receipt wins a cancellation race', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.controller.requestCancellation(p.epoch);
      p.controller.finishFailure(p.epoch, const TransferCancelled());
      expect(
        p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt()),
        isTrue,
      );
      expect(p.state.confirmed, isTrue);
      expect(p.state.cancelRequested, isTrue);
    });
    test('18 commit ambiguity never guesses success or failure counts', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.verifying, commit: true);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('Confirmation lost.', outcomeUncertain: true),
      );
      p.controller.settle(p.epoch);
      expect(p.state.successfulFiles, isNull);
      expect(p.state.unsuccessfulFiles, isNull);
      expect(p.state.canRetry, isFalse);
    });
    test('19 safe retry requires settled uncommitted work and a new epoch', () {
      final p = ProgressProbe()..start();
      final oldEpoch = p.epoch;
      final oldEvent = p.frame(TransferPhase.sending, bytes: 5, fileBytes: 5);
      p.controller.finishFailure(
        p.epoch,
        const TransferException('Connection failed.'),
      );
      expect(p.state.canRetry, isFalse);
      p.controller.settle(p.epoch);
      expect(p.state.canRetry, isTrue);
      p.epoch = p.controller.open(TransferRole.sender);
      expect(p.controller.addEngineEvent(oldEpoch, oldEvent), isFalse);
      expect(p.state.phase, TransferPhase.idle);
    });
    test('20 file-count progress cannot regress', () {
      final p = ProgressProbe(sizes: <int>[10, 20])..start();
      p.step(TransferPhase.sending, bytes: 10, fileBytes: 10, done: 1);
      expect(p.step(TransferPhase.sending, done: 0), isFalse);
      expect(p.state.completedFiles, 1);
    });
    test('21 byte-count progress cannot regress', () {
      final p = ProgressProbe()..start();
      p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
      expect(p.step(TransferPhase.sending, bytes: 80, fileBytes: 80), isFalse);
      expect(p.state.batchBytes, 100);
    });
    test(
      '22 speed is measured from monotonic elapsed time and actual bytes',
      () {
        final p = ProgressProbe()..start();
        p.time = const Duration(seconds: 2);
        p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
        expect(p.state.bytesPerSecond, closeTo(100, 0.001));
      },
    );
    test(
      '23 ETA estimates only the remaining payload and expires on stalls',
      () {
        final p = ProgressProbe()..start();
        p.time = const Duration(seconds: 2);
        p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
        expect(p.state.eta, const Duration(seconds: 8));
        p.time = const Duration(seconds: 6);
        p.controller.refreshEstimates();
        expect(p.state.bytesPerSecond, 0);
        expect(p.state.eta, isNull);
        expect(p.state.batchBytes, 200);
      },
    );
    test('24 malformed verification receipts cannot confirm delivery', () {
      final p = ProgressProbe()
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed, receipt: p.receipt(digest: 'not-a-hash'));
      expect(p.state.confirmed, isFalse);
      expect(p.state.warning, contains('receipt'));
    });
    test('29 duplicate and stale progress frames are ignored', () {
      final p = ProgressProbe()..start();
      final event = p.frame(TransferPhase.sending, bytes: 10, fileBytes: 10);
      expect(p.controller.addEngineEvent(p.epoch, event), isTrue);
      expect(p.controller.addEngineEvent(p.epoch, event), isFalse);
      expect(
        p.controller.addEngineEvent(
          p.epoch,
          event.copyWith(attemptId: randomTransferId(), sequence: 999),
        ),
        isFalse,
      );
      expect(p.state.batchBytes, 10);
    });
    test('30 inconsistent metadata indices totals and states do not corrupt progress', () {
      final p = ProgressProbe()..start();
      final wrongTotal = p
          .frame(TransferPhase.sending)
          .copyWith(totalBytes: 4000);
      expect(p.controller.addEngineEvent(p.epoch, wrongTotal), isFalse);
      expect(p.step(TransferPhase.sending, index: 8), isFalse);
      expect(p.step(TransferPhase.connecting), isFalse);
      expect(p.state.phase, TransferPhase.sending);
      expect(p.state.totalBytes, 1000);
    });
    test('repeated wire IDs have distinct receiver attempt identities', () {
      final p = ProgressProbe(role: TransferRole.receiver)
        ..start()
        ..finishBytes();
      p.step(TransferPhase.completed, receipt: p.receipt());
      final oldAttempt = p.attempt;
      p.attempt = randomTransferId();
      final event = TransferProgress(
        phase: TransferPhase.awaitingApproval,
        message: 'Next offer',
        transferId: p.id,
        attemptId: p.attempt,
        sequence: ++p.sequence,
        manifest: p.files,
        totalBytes: 1000,
        totalFiles: 1,
      );
      expect(p.controller.addEngineEvent(p.epoch, event), isTrue);
      expect(p.state.confirmed, isFalse);
      expect(
        p.controller.completeFromReceipt(p.epoch, oldAttempt, p.receipt()),
        isFalse,
      );
    });
    test(
      'public activity projection remains safe for malformed numerical inputs',
      () {
        final activity = TransferActivity(
          progress: const TransferProgress(
            phase: TransferPhase.sending,
            message: '',
            processedBytes: -10,
            totalBytes: -1,
            totalFiles: -5,
          ),
          measuredBytesPerSecond: double.nan,
          estimatedRemaining: const Duration(seconds: -1),
        );
        expect(activity.fraction, 0);
        expect(activity.totalFiles, 0);
        expect(activity.bytesPerSecond, isNull);
        expect(activity.eta, isNull);
      },
    );
    test('clock rollback and estimator refresh never create bytes', () {
      final p = ProgressProbe()..start();
      p.time = const Duration(seconds: 2);
      p.step(TransferPhase.sending, bytes: 200, fileBytes: 200);
      p.time = const Duration(seconds: 1);
      p.controller.refreshEstimates();
      expect(p.state.batchBytes, 200);
      expect(p.state.bytesPerSecond, isNull);
    });
    test(
      'disposed controller ignores queued progress receipts and cancellation',
      () {
        final p = ProgressProbe()..start();
        final event = p.frame(TransferPhase.sending, bytes: 1, fileBytes: 1);
        p.controller.dispose();
        expect(p.controller.addEngineEvent(p.epoch, event), isFalse);
        expect(
          p.controller.completeFromReceipt(p.epoch, p.attempt, p.receipt()),
          isFalse,
        );
        expect(p.controller.requestCancellation(p.epoch), isFalse);
      },
    );
  });

  group('Part 4 malformed-event regressions', () {
    test('a rejected high sequence cannot poison later valid telemetry', () {
      final p = ProgressProbe()..start();
      final bad = p
          .frame(TransferPhase.sending)
          .copyWith(sequence: 999999, totalBytes: 9000);
      expect(p.controller.addEngineEvent(p.epoch, bad), isFalse);
      expect(p.step(TransferPhase.sending, bytes: 30, fileBytes: 30), isTrue);
      expect(p.state.batchBytes, 30);
    });
    test(
      'current-file counters cannot go backwards while batch counters advance',
      () {
        final p = ProgressProbe()..start();
        p.step(TransferPhase.sending, bytes: 100, fileBytes: 100);
        expect(
          p.step(TransferPhase.sending, bytes: 110, fileBytes: 90),
          isFalse,
        );
        expect(p.state.fileBytes, 100);
      },
    );
    test('malformed hash-check counts cannot invent matched checksums', () {
      final p = ProgressProbe()..start();
      p.step(
        TransferPhase.sending,
        bytes: 1000,
        fileBytes: 1000,
        done: 1,
        checked: 999,
      );
      expect(p.state.verifiedFiles, 0);
      expect(p.state.confirmed, isFalse);
    });
  });

  group('Part 4 real TLS progress', () {
    late TlsIdentity identity;
    HttpOverrides? previous;
    setUpAll(() async {
      identity = await TlsIdentity.generate();
    });
    setUp(() {
      previous = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() {
      HttpOverrides.global = previous;
    });

    test(
      '25 receiver completion uses existing saved history and receipt',
      () async {
        final controller = TransferProgressController(autoRefresh: false);
        addTearDown(controller.dispose);
        final epoch = controller.open(TransferRole.receiver);
        final phases = <TransferPhase>{};
        final receiver = await baseline.startReceiverFixture(
          identity,
          progress: (event) {
            phases.add(event.phase);
            expect(controller.addEngineEvent(epoch, event), isTrue);
          },
        );
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('one.txt', <int>[1, 2]),
            baseline.bytesFile('empty.txt', <int>[]),
          ],
          senderName: 'Progress integration',
        );
        expect(controller.value.confirmed, isTrue);
        expect(controller.value.verifiedFiles, 2);
        expect(
          phases,
          containsAll(<TransferPhase>[
            TransferPhase.approved,
            TransferPhase.preparing,
            TransferPhase.receiving,
            TransferPhase.verifying,
            TransferPhase.completed,
          ]),
        );
        final history = await TransferHistoryService(receiver.root).load();
        expect(
          history.transfers.single.receipt.id,
          controller.value.receipt!.id,
        );
      },
    );
    test(
      '26 sender confirmation and counters use real TLS engine events',
      () async {
        final receiver = await baseline.startReceiverFixture(identity);
        final controller = TransferProgressController(autoRefresh: false);
        addTearDown(controller.dispose);
        final epoch = controller.open(TransferRole.sender);
        final stages = <int>[];
        final receipt = await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('a.txt', <int>[1]),
            baseline.bytesFile('b.txt', <int>[2, 3]),
          ],
          senderName: 'Sender',
          onProgress: (event) {
            expect(controller.addEngineEvent(epoch, event), isTrue);
            stages.add(event.completedFiles);
          },
        );
        expect(controller.value.receipt, same(receipt));
        expect(controller.value.batchBytes, 3);
        expect(stages, containsAll(<int>[0, 1, 2]));
      },
    );
    test('real approval denial reads no source and remains retryable only after settlement', () async {
      final receiver = await baseline.startReceiverFixture(
        identity,
        approve: (_) async => false,
      );
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      var reads = 0;
      try {
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.sampleFile(
              size: 3,
              openRead: () {
                reads += 1;
                return Stream<List<int>>.value(<int>[1, 2, 3]);
              },
            ),
          ],
          senderName: 'Denied',
          onProgress: (event) => controller.addEngineEvent(epoch, event),
        );
        fail('A declined batch must not complete.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      expect(reads, 0);
      expect(controller.value.canRetry, isFalse);
      controller.settle(epoch);
      expect(controller.value.canRetry, isTrue);
    });
    test('real streamed cancellation keeps original content and records no saved success', () async {
      final receiver = await baseline.startReceiverFixture(identity);
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      final sender = LocalSender();
      final source = ShareFile(
        name: 'cancel.bin',
        size: 4,
        sourceUri: Uri.file('/selected/cancel.bin'),
        readStream: () async* {
          yield <int>[1, 2];
          await Future<void>.delayed(const Duration(milliseconds: 30));
          yield <int>[3, 4];
        },
      );
      try {
        await sender.send(
          code: receiver.code,
          files: <ShareFile>[source],
          senderName: 'Cancel test',
          onProgress: (event) {
            controller.addEngineEvent(epoch, event);
            if (event.processedBytes > 0 && !controller.value.cancelRequested) {
              controller.requestCancellation(epoch);
              sender.cancel();
            }
          },
        );
        fail('Canceled streaming must not complete.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      controller.settle(epoch);
      expect(controller.value.phase, TransferPhase.canceled);
      expect(controller.value.successfulFiles, 0);
      expect(
        (await TransferHistoryService(receiver.root).load()).transfers,
        isEmpty,
      );
    });
    test('real source failure has no false successful-file count', () async {
      final receiver = await baseline.startReceiverFixture(identity);
      final controller = TransferProgressController(autoRefresh: false);
      addTearDown(controller.dispose);
      final epoch = controller.open(TransferRole.sender);
      try {
        await LocalSender().send(
          code: receiver.code,
          files: <ShareFile>[
            baseline.bytesFile('short.txt', <int>[1], declaredSize: 2),
          ],
          senderName: 'Short source',
          onProgress: (event) => controller.addEngineEvent(epoch, event),
        );
        fail('A short stream must fail.');
      } on TransferException catch (error) {
        controller.finishFailure(epoch, error);
      }
      expect(controller.value.phase, TransferPhase.failed);
      expect(controller.value.batchBytes, 1);
      expect(controller.value.successfulFiles, 0);
    });
  });

  group('Part 4 widgets and lifecycle', () {
    testWidgets('progress fits narrow screens with large system text', (
      tester,
    ) async {
      final p = ProgressProbe(sizes: <int>[10, 20])..start();
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransferProgressPanel(
                controller: p.controller,
                onCancel: () => p.controller.requestCancellation(p.epoch),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('File 1 of 2'), findsOneWidget);
    });
    testWidgets(
      '27 disposing progress widget detaches without owning the engine',
      (tester) async {
        final p = ProgressProbe()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TransferProgressPanel(controller: p.controller),
              ),
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        p.step(TransferPhase.sending, bytes: 10, fileBytes: 10);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(p.state.batchBytes, 10);
      },
    );
    testWidgets('28 backgrounding Nearby cancels its real sender interface', (
      tester,
    ) async {
      final sender = ControlledSender();
      await mountSender(tester, sender);
      expect(find.text('Waiting for approval'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(sender.cancellations, greaterThan(0));
      expect(find.text('Cancelled'), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Delivery confirmed'), findsNothing);
    });
    testWidgets('disposing Nearby cancels work and ignores late callbacks', (
      tester,
    ) async {
      final sender = ControlledSender();
      await mountSender(tester, sender);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sender.emit(TransferPhase.sending);
      await tester.pump();
      expect(sender.cancellations, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'a confirmed sender result retains the existing delivery receipt UI',
      (tester) async {
        final sender = ControlledSender();
        await mountSender(tester, sender);
        sender.confirm();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('transfer-result-panel')),
          findsOneWidget,
        );
        expect(find.text('Successful files: 1'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Delivery confirmed'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Delivery confirmed'), findsOneWidget);
      },
    );
    testWidgets(
      'receiver result opens the existing HistoryScreen instead of a second database',
      (tester) async {
        final p = ProgressProbe(role: TransferRole.receiver)
          ..start()
          ..finishBytes();
        p.step(TransferPhase.completed, receipt: p.receipt());
        final root = await tester.runAsync(
          () => Directory.systemTemp.createTemp('part4-history-ui-'),
        );
        addTearDown(() async {
          await root!.delete(recursive: true);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: SingleChildScrollView(
                  child: TransferResultPanel(
                    activity: p.state,
                    onDone: () => Navigator.pop(context),
                    onViewSavedFiles: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => HistoryScreen(
                          service: baseline.FakeHistoryService(
                            HistorySnapshot(transfers: []),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('result-view-saved-files'),
        );
        expect(find.byKey(const ValueKey('history-scaffold')), findsOneWidget);
      },
    );
    testWidgets(
      'safe retry is explicit and does not discard selected originals',
      (tester) async {
        final sender = ControlledSender();
        await mountSender(tester, sender);
        sender.fail();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('retry-uncommitted-transfer')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('retry-uncommitted-transfer'),
        );
        expect(find.text('Retry the uncommitted batch?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(sender.sequence, 2);
      },
    );
    testWidgets(
      'uncertain result never offers automatic retry or invented counts',
      (tester) async {
        final p = ProgressProbe()
          ..start()
          ..finishBytes();
        p.step(TransferPhase.verifying, commit: true);
        p.controller.finishFailure(
          p.epoch,
          const TransferException(
            'Receipt unavailable.',
            outcomeUncertain: true,
          ),
        );
        p.controller.settle(p.epoch);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TransferResultPanel(
                  activity: p.state,
                  onDone: () {},
                  onRetry: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('Successful files: Unknown'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('retry-uncommitted-transfer')),
          findsNothing,
        );
      },
    );
  });
}

DateTime get coinFixtureTime => DateTime.utc(2026, 9, 8, 12);

ShareCoinBalance coinFixtureBalance({
  String user = 'user-1',
  int available = 10000,
  int pending = 200,
}) => ShareCoinBalance(
  userId: user,
  available: available,
  pending: pending,
  lifetimeEarned: 12000,
  lifetimeWithdrawn: 1000,
  lifetimeSpent: 800,
  updatedAt: coinFixtureTime,
  version: 'wallet-v1',
);

ShareCoinUser coinFixtureUser({
  String id = 'user-1',
  AccountStatus status = AccountStatus.active,
}) => ShareCoinUser(
  userId: id,
  displayName: 'Test account',
  username: 'test_user',
  status: status,
  createdAt: coinFixtureTime.subtract(const Duration(days: 20)),
  lastActiveAt: coinFixtureTime,
  version: 'user-v1',
  referralCode: 'REF-TEST',
  features: const {'rewards': true},
);

CoinConversionRate coinFixtureRate() =>
    CoinConversionRate(coinUnits: 1000, minorUnits: 100, currency: 'BDT');
WithdrawalPolicy coinFixturePolicy({
  String user = 'user-1',
  List<String> active = const [],
  bool connected = true,
}) => WithdrawalPolicy(
  userId: user,
  version: 'policy-v1',
  minimumCoins: 1000,
  rate: coinFixtureRate(),
  methods: <PayoutMethodConfig>[
    PayoutMethodConfig(
      method: PayoutMethod.bkash,
      enabled: true,
      providerConnected: connected,
      feeMinor: 10,
      destinationReference: 'destination-1',
      maskedDestination: '****1234',
    ),
  ],
  activeRequestIds: active,
);

WithdrawalIntent coinFixtureIntent({
  String user = 'user-1',
  int coins = 1000,
  String key = 'withdraw-key-1',
}) => WithdrawalIntent(
  userId: user,
  coins: coins,
  method: PayoutMethod.bkash,
  destinationReference: 'destination-1',
  policyVersion: 'policy-v1',
  expectedFeeMinor: 10,
  expectedFinalMinor: coinFixtureRate().grossMinor(coins) - 10,
  idempotencyKey: key,
);

WithdrawalRequest coinFixtureWithdrawal({
  String user = 'user-1',
  String key = 'withdraw-key-1',
  int coins = 1000,
  WithdrawalStatus status = WithdrawalStatus.requested,
}) => WithdrawalRequest(
  withdrawalId: 'withdrawal-1',
  userId: user,
  requestedCoins: coins,
  rate: coinFixtureRate(),
  feeMinor: 10,
  finalPayoutMinor: coinFixtureRate().grossMinor(coins) - 10,
  method: PayoutMethod.bkash,
  maskedDestination: '****1234',
  status: status,
  requestedAt: coinFixtureTime,
  updatedAt: coinFixtureTime.add(const Duration(minutes: 2)),
  idempotencyKey: key,
  serverReference: status == WithdrawalStatus.paid
      ? 'provider-reference-1'
      : null,
  rejectionReason: status == WithdrawalStatus.rejected
      ? 'Provider rejected this test request.'
      : null,
);

RewardEvent coinFixtureReward({
  String event = 'event-1',
  String key = 'reward-key-1',
  String providerEvent = 'provider-event-1',
  int coins = 250,
  String user = 'user-1',
  RewardEventStatus status = RewardEventStatus.created,
}) => RewardEvent(
  eventId: event,
  userId: user,
  source: CoinSource.adReward,
  provider: 'test-provider',
  providerEventId: providerEvent,
  targetId: 'placement-1',
  requestedCoins: coins,
  occurredAt: coinFixtureTime,
  status: status,
  idempotencyKey: key,
  transactionId: status == RewardEventStatus.approved
      ? 'reward-transaction-1'
      : null,
  metadata: const {'placement': 'test-placement'},
);

Offer coinFixtureOffer({
  String id = 'offer-1',
  OfferStatus status = OfferStatus.available,
  bool expired = false,
}) => Offer(
  offerId: id,
  title: 'Test offer',
  shortDescription: 'Lightweight test data',
  description: 'This is not a production advertiser offer.',
  publisher: 'Test publisher',
  category: OfferCategory.education,
  rewardCoins: 250,
  estimatedMinutes: 10,
  platforms: const [OfferPlatform.android, OfferPlatform.ios],
  countries: const ['BD'],
  status: status,
  startsAt: coinFixtureTime.subtract(const Duration(days: 1)),
  expiresAt: expired
      ? coinFixtureTime.subtract(const Duration(hours: 1))
      : coinFixtureTime.add(const Duration(days: 2)),
  provider: 'test-provider',
  iconUrl: Uri.parse('https://assets.example.org/icon.png'),
  instructions: const ['Complete the provider task.'],
  terms: const ['Backend verification required.'],
  rewardTransactionId: status == OfferStatus.completed
      ? 'offer-transaction-1'
      : null,
);

ShareCoinTransaction coinFixtureTransaction({
  CoinSource source = CoinSource.adReward,
  CoinDirection direction = CoinDirection.credit,
  CoinTransactionStatus status = CoinTransactionStatus.completed,
}) => ShareCoinTransaction(
  transactionId: 'transaction-1',
  userId: 'user-1',
  amount: 250,
  direction: direction,
  source: source,
  status: status,
  description: 'A test ledger record.',
  createdAt: coinFixtureTime,
  completedAt: status == CoinTransactionStatus.completed
      ? coinFixtureTime
      : null,
  referenceId: 'reference-1',
  idempotencyKey: 'transaction-key-1',
);

Promotion coinFixturePromotion() => Promotion(
  campaignId: 'campaign-1',
  title: 'Test campaign',
  description: 'Test data only.',
  advertiser: 'Test advertiser',
  cta: 'View campaign',
  rewardCoins: 100,
  startsAt: coinFixtureTime.subtract(const Duration(days: 1)),
  endsAt: coinFixtureTime.add(const Duration(days: 1)),
  status: PromotionStatus.active,
  trackingId: 'tracking-1',
);

class TestShareCoinBackend implements ShareCoinBackend {
  TestShareCoinBackend()
    : _scope = AccountScope(userId: 'user-1', sessionId: 'session-1');
  final StreamController<AccountScope?> events =
      StreamController<AccountScope?>.broadcast();
  final Map<ShareCoinOperation, int> calls = <ShareCoinOperation, int>{};
  AccountScope? _scope;
  CoinServiceState serviceState = CoinServiceState.reachable;
  AccountStatus accountStatus = AccountStatus.active;
  int balance = 10000;
  List<String> activeWithdrawals = <String>[];
  bool expiredOffer = false;
  Future<Map<String, dynamic>> Function(
    ShareCoinOperation,
    AccountScope,
    Map<String, Object?>,
  )?
  handler;
  @override
  bool get configured => true;
  @override
  AccountScope? get scope => _scope;
  @override
  Stream<AccountScope?> get accountChanges => events.stream;
  @override
  Future<CoinServiceState> checkService() async => serviceState;
  void switchAccount(AccountScope? value) {
    _scope = value;
    events.add(value);
  }

  Future<void> close() => events.close();
  Map<String, dynamic> envelope(
    AccountScope owner,
    Map<String, Object?> data,
  ) => <String, dynamic>{
    'userId': owner.userId,
    'serverTime': coinFixtureTime.toIso8601String(),
    'version': 'reply-v1',
    'data': data,
  };
  Map<String, Object?> page(
    List<Map<String, Object?>> items,
    Map<String, Object?> args,
  ) => <String, Object?>{
    'items': items,
    'page': PageInfo(
      page: args['page'] as int,
      pageSize: args['pageSize'] as int,
      total: items.length,
      hasNext: false,
    ).toJson(),
  };
  Map<String, Object?> dataFor(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> args,
  ) => switch (operation) {
    ShareCoinOperation.currentUser => coinFixtureUser(
      id: owner.userId,
      status: accountStatus,
    ).toJson(),
    ShareCoinOperation.wallet => coinFixtureBalance(
      user: owner.userId,
      available: balance,
    ).toJson(),
    ShareCoinOperation.transactions => page([
      coinFixtureTransaction(
        status: CoinTransactionStatus.reversed,
        source: CoinSource.reversal,
        direction: CoinDirection.debit,
      ).toJson(),
    ], args),
    ShareCoinOperation.submitReward => Map<String, Object?>.from(
      args,
    )..['status'] = RewardEventStatus.pending.name,
    ShareCoinOperation.rewardStatus => coinFixtureReward(
      event: args['eventId'] as String,
      user: owner.userId,
      status: RewardEventStatus.pending,
    ).toJson(),
    ShareCoinOperation.rewardHistory => page([
      coinFixtureReward(
        user: owner.userId,
        status: RewardEventStatus.pending,
      ).toJson(),
    ], args),
    ShareCoinOperation.offers => page([coinFixtureOffer().toJson()], args),
    ShareCoinOperation.offer ||
    ShareCoinOperation.offerStatus => coinFixtureOffer(
      id: args['offerId'] as String,
      expired: expiredOffer,
    ).toJson(),
    ShareCoinOperation.startOffer => OfferStart(
      startId: 'start-1',
      offerId: args['offerId'] as String,
      userId: owner.userId,
      idempotencyKey: args['idempotencyKey'] as String,
      status: OfferStatus.started,
      updatedAt: coinFixtureTime,
    ).toJson(),
    ShareCoinOperation.promotions => page([
      coinFixturePromotion().toJson(),
    ], args),
    ShareCoinOperation.withdrawalPolicy => coinFixturePolicy(
      user: owner.userId,
      active: activeWithdrawals,
    ).toJson(),
    ShareCoinOperation.requestWithdrawal => coinFixtureWithdrawal(
      user: owner.userId,
      key: args['idempotencyKey'] as String,
      coins: args['coins'] as int,
    ).toJson(),
    ShareCoinOperation.withdrawals => page([], args),
    ShareCoinOperation.withdrawalStatus => coinFixtureWithdrawal(
      user: owner.userId,
      status: WithdrawalStatus.paid,
    ).toJson(),
    ShareCoinOperation.withdrawalByKey => coinFixtureWithdrawal(
      user: owner.userId,
      key: args['idempotencyKey'] as String,
      status: WithdrawalStatus.paid,
    ).toJson(),
    ShareCoinOperation.referral => ReferralSummary(
      userId: owner.userId,
      referralCode: 'REF-TEST',
      invitedCount: 3,
      pendingCount: 1,
      qualifiedCount: 1,
      earnedCoins: 100,
      status: ReferralStatus.active,
      referralUrl: Uri.parse('https://example.org/referral/REF-TEST'),
      updatedAt: coinFixtureTime,
    ).toJson(),
    ShareCoinOperation.adsConfiguration => AdConfiguration.disabled().toJson(),
    ShareCoinOperation.dailyConfiguration => DailyRewardConfiguration(
      dayRewards: const [1, 2, 3, 4, 5, 6, 7],
      streakDay: 3,
      eligible: false,
      nextEligibleAt: coinFixtureTime.add(const Duration(days: 1)),
      version: 'daily-v1',
    ).toJson(),
  };
  @override
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> arguments,
  ) async {
    calls[operation] = (calls[operation] ?? 0) + 1;
    final custom = handler;
    if (custom != null) return custom(operation, owner, arguments);
    return envelope(owner, dataFor(operation, owner, arguments));
  }
}

class CoinServiceFixture {
  CoinServiceFixture() {
    connectivity = ConnectivityService(
      localProbe: () async => <String>['192.168.5.2'],
      internetProbe: () async => internet,
      serviceProbe: backend.checkService,
    );
    service = ShareCoinService(backend: backend, connectivity: connectivity);
    addTearDown(() async {
      service.dispose();
      connectivity.dispose();
      await backend.close();
    });
  }
  final TestShareCoinBackend backend = TestShareCoinBackend();
  InternetState internet = InternetState.available;
  late final ConnectivityService connectivity;
  late final ShareCoinService service;
  void goOffline() {
    internet = InternetState.offline;
    backend.serviceState = CoinServiceState.unreachable;
  }
}

Matcher coinError(CoinErrorCode code) =>
    isA<ShareCoinException>().having((error) => error.code, 'code', code);

Future<void> mountCoinDashboard(
  WidgetTester tester,
  ShareCoinService service, {
  ValueChanged<ShareCoinFileAction>? action,
  Size size = const Size(390, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ShareCoinHomeScreen(service: service, onFileAction: action),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapCoinKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void registerPart5Tests() {
  group('Part 5 immutable domain', () {
    test('01 wallet serialization preserves all server fields', () {
      final wallet = coinFixtureBalance();
      expect(
        ShareCoinBalance.fromJson(wallet.toJson()).toJson(),
        wallet.toJson(),
      );
    });
    test('02 wallet rejects negative non-integer and overflowing values', () {
      for (final value in <Object>[
        -1,
        1.5,
        double.nan,
        double.infinity,
        maxShareCoinInteger + 1,
        '1000',
      ]) {
        final json = coinFixtureBalance().toJson()..['available'] = value;
        expect(
          () => ShareCoinBalance.fromJson(json),
          throwsA(isA<CoinModelException>()),
        );
      }
      expect(
        () => coinFixtureBalance(available: maxShareCoinInteger, pending: 1),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('03 transaction round trip', () {
      final transaction = coinFixtureTransaction();
      expect(
        ShareCoinTransaction.fromJson(transaction.toJson()).toJson(),
        transaction.toJson(),
      );
    });
    test(
      '04 direction produces signed display without negative stored amounts',
      () {
        expect(coinFixtureTransaction().signedAmount, '+250 ShareCoin');
        expect(
          coinFixtureTransaction(direction: CoinDirection.debit).signedAmount,
          '-250 ShareCoin',
        );
      },
    );
    test(
      '05 every ledger status including rejected and reversed is preserved',
      () {
        for (final status in CoinTransactionStatus.values) {
          expect(
            ShareCoinTransaction.fromJson(
              coinFixtureTransaction(status: status).toJson(),
            ).status,
            status,
          );
        }
      },
    );
    test('06 unsafe transaction IDs and unknown statuses are rejected', () {
      for (final entry in <MapEntry<String, Object>>[
        const MapEntry('transactionId', '../escape'),
        const MapEntry('status', 'creditedLocally'),
      ]) {
        final json = coinFixtureTransaction().toJson()
          ..[entry.key] = entry.value;
        expect(
          () => ShareCoinTransaction.fromJson(json),
          throwsA(isA<CoinModelException>()),
        );
      }
    });
    test('07 reward claims cannot use withdrawal/admin sources or malformed timestamps', () {
      final json = coinFixtureReward().toJson()
        ..['source'] = CoinSource.administrativeAdjustment.name;
      expect(
        () => RewardEvent.fromJson(json),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime('2026-02-31T12:00:00Z', 'date'),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime('2026-09-08T12:00:00', 'date'),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        () => coinTime(DateTime.utc(2500), 'date'),
        throwsA(isA<CoinModelException>()),
      );
    });
    test(
      '10 withdrawal JSON validates rational quote and masked destination',
      () {
        final request = coinFixtureWithdrawal();
        expect(
          WithdrawalRequest.fromJson(request.toJson()).toJson(),
          request.toJson(),
        );
        final bad = request.toJson()..['finalPayoutMinor'] = 999;
        expect(
          () => WithdrawalRequest.fromJson(bad),
          throwsA(isA<CoinModelException>()),
        );
        bad['finalPayoutMinor'] = 90;
        bad['maskedDestination'] = '01712345678';
        expect(
          () => WithdrawalRequest.fromJson(bad),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test(
      '14 payout polling may skip forward but cannot reverse terminal states',
      () {
        expect(
          coinFixtureWithdrawal().canTransitionTo(WithdrawalStatus.paid),
          isTrue,
        );
        expect(
          coinFixtureWithdrawal(status: WithdrawalStatus.paid)
              .canTransitionTo(WithdrawalStatus.processing),
          isFalse,
        );
        expect(
          coinFixtureWithdrawal(status: WithdrawalStatus.rejected)
              .canTransitionTo(WithdrawalStatus.paid),
          isFalse,
        );
      },
    );
    test('15 user serialization contains no credential fields', () {
      final user = coinFixtureUser();
      expect(ShareCoinUser.fromJson(user.toJson()).toJson(), user.toJson());
      expect(user.toJson().keys, isNot(contains('password')));
      expect(user.toJson().keys, isNot(contains('accessToken')));
      expect(() => user.features['other'] = true, throwsUnsupportedError);
    });
    test('16 only active accounts may request rewards', () {
      for (final status in AccountStatus.values) {
        expect(
          coinFixtureUser(status: status).mayRequestRewards,
          status == AccountStatus.active,
        );
      }
    });
    test('17 referral counts and earned coins are validated', () {
      final record = ReferralSummary(
        userId: 'u1',
        referralCode: 'R123',
        invitedCount: 4,
        pendingCount: 1,
        qualifiedCount: 2,
        earnedCoins: 100,
        status: ReferralStatus.active,
        updatedAt: coinFixtureTime,
      );
      expect(
        ReferralSummary.fromJson(record.toJson()).toJson(),
        record.toJson(),
      );
      expect(
        () => ReferralSummary(
          userId: 'u1',
          referralCode: 'R123',
          invitedCount: 1,
          pendingCount: 1,
          qualifiedCount: 2,
          earnedCoins: 100,
          status: ReferralStatus.active,
          updatedAt: coinFixtureTime,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test(
      '18 offer model freezes arrays and keeps country/platform availability',
      () {
        final offer = coinFixtureOffer();
        expect(Offer.fromJson(offer.toJson()).toJson(), offer.toJson());
        expect(offer.countries, <String>['BD']);
        expect(() => offer.countries.add('US'), throwsUnsupportedError);
        final bad = offer.toJson()
          ..['destinationUrl'] = 'http://example.org/app';
        expect(() => Offer.fromJson(bad), throwsA(isA<CoinModelException>()));
      },
    );
    test('19 completed offer needs a transaction reference and expiry uses supplied server time', () {
      for (final status in OfferStatus.values) {
        expect(
          Offer.fromJson(coinFixtureOffer(status: status).toJson()).status,
          status,
        );
      }
      final bad = coinFixtureOffer(status: OfferStatus.completed).toJson()
        ..['rewardTransactionId'] = null;
      expect(() => Offer.fromJson(bad), throwsA(isA<CoinModelException>()));
      expect(
        coinFixtureOffer(expired: true).availableAt(coinFixtureTime),
        isFalse,
      );
      expect(coinFixtureOffer().availableAt(coinFixtureTime), isTrue);
    });
    test(
      '20 pagination is scalable and rejects duplicate IDs or overfull pages',
      () {
        final info = PageInfo(
          page: 1,
          pageSize: 20,
          total: 1000,
          hasNext: true,
          nextCursor: 'next-token',
        );
        expect(PageInfo.fromJson(info.toJson()).total, 1000);
        final item = coinFixtureOffer();
        expect(
          () => CoinPage<Offer>(
            items: [item, item],
            info: info,
            id: (offer) => offer.offerId,
          ),
          throwsA(isA<CoinModelException>()),
        );
        expect(
          () => PageInfo(page: 1, pageSize: 101, total: 1000, hasNext: true),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('21 promotion expiry never implies coin credit', () {
      final item = coinFixturePromotion();
      expect(Promotion.fromJson(item.toJson()).toJson(), item.toJson());
      expect(item.availableAt(item.endsAt), isFalse);
      expect(item.availableAt(coinFixtureTime), isTrue);
    });
    test(
      '22 ad configuration starts disabled and validates SDK-free policy',
      () {
        final config = AdConfiguration.disabled();
        expect(config.adsAllowed, isFalse);
        expect(config.units, isEmpty);
        expect(
          AdConfiguration.fromJson(config.toJson()).toJson(),
          config.toJson(),
        );
        expect(
          () => AdConfiguration(
            rewardedEnabled: true,
            bannerEnabled: false,
            interstitialEnabled: false,
            cooldownSeconds: 30,
            dailyLimit: 5,
            premium: false,
          ),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('29 negative and overflow reward amounts cannot become claims', () {
      for (final amount in <int>[-1, 0, maxShareCoinInteger + 1]) {
        expect(
          () => coinFixtureReward(coins: amount),
          throwsA(isA<CoinModelException>()),
        );
      }
      expect(
        () => CoinConversionRate(
          coinUnits: 1,
          minorUnits: maxShareCoinInteger,
          currency: 'BDT',
        ).grossMinor(2),
        throwsA(isA<CoinModelException>()),
      );
      expect(
        CoinConversionRate(
          coinUnits: 3,
          minorUnits: 2,
          currency: 'BDT',
        ).grossMinor(4),
        2,
      );
    });
    test(
      'metadata whitelist refuses credentials and mutable nested values',
      () {
        expect(
          () => coinMetadata({'accessToken': 'secret'}),
          throwsA(isA<CoinModelException>()),
        );
        expect(
          () => coinMetadata({
            'placement': {'secret': 'value'},
          }),
          throwsA(isA<CoinModelException>()),
        );
      },
    );
    test('daily configuration uses a backend-provided seven-day policy', () {
      final config = DailyRewardConfiguration(
        dayRewards: const [1, 2, 3, 4, 5, 6, 7],
        streakDay: 2,
        eligible: false,
        nextEligibleAt: coinFixtureTime,
        version: 'daily-v1',
      );
      expect(
        DailyRewardConfiguration.fromJson(config.toJson()).eligible,
        isFalse,
      );
      expect(() => config.dayRewards.add(1000), throwsUnsupportedError);
    });
  });

  group('Part 5 server-authoritative service', () {
    test('08 duplicate reward submissions share one backend event', () async {
      final f = CoinServiceFixture();
      final event = coinFixtureReward();
      final results = await Future.wait([
        f.service.submitRewardEvent(event),
        f.service.submitRewardEvent(event),
      ]);
      expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      expect(
        results.every(
          (result) => result.data.status == RewardEventStatus.pending,
        ),
        isTrue,
      );
    });
    test('09 repeated provider callback with new client IDs does not produce another reward', () async {
      final f = CoinServiceFixture();
      await f.service.submitRewardEvent(coinFixtureReward());
      final result = await f.service.submitRewardEvent(
        coinFixtureReward(event: 'event-2', key: 'key-2'),
      );
      expect(result.data.eventId, 'event-1');
      expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward(coins: 999)),
        throwsA(coinError(CoinErrorCode.conflict)),
      );
    });
    test(
      '11 minimum withdrawal is checked without a backend debit request',
      () async {
        final f = CoinServiceFixture();
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(coins: 500)),
          throwsA(coinError(CoinErrorCode.minimum)),
        );
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
        expect((await f.service.getCurrentWallet()).data.available, 10000);
      },
    );
    test('12 insufficient funds does not locally subtract a balance', () async {
      final f = CoinServiceFixture();
      await expectLater(
        f.service.requestWithdrawal(coinFixtureIntent(coins: 11000)),
        throwsA(coinError(CoinErrorCode.insufficientBalance)),
      );
      expect(f.backend.balance, 10000);
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      '13 withdrawal idempotency and conflicting requests are protected',
      () async {
        final f = CoinServiceFixture();
        final intent = coinFixtureIntent();
        final results = await Future.wait([
          f.service.requestWithdrawal(intent),
          f.service.requestWithdrawal(intent),
        ]);
        expect(results.first.data.status, WithdrawalStatus.requested);
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(key: 'another-key')),
          throwsA(coinError(CoinErrorCode.conflict)),
        );
        expect((await f.service.getCurrentWallet()).data.available, 10000);
      },
    );
    test('23 offline wallet is explicitly cached, never invented', () async {
      final f = CoinServiceFixture();
      final online = await f.service.getCurrentWallet();
      expect(online.cached, isFalse);
      f.goOffline();
      final cached = await f.service.getCurrentWallet();
      expect(cached.cached, isTrue);
      expect(cached.data.available, online.data.available);
      await expectLater(
        f.service.getCurrentWallet(allowCached: false),
        throwsA(coinError(CoinErrorCode.offline)),
      );
    });
    test(
      '27 safe backend error mapping does not expose raw provider errors',
      () {
        expect(
          ShareCoinException.fromServerCode('insufficient_balance').code,
          CoinErrorCode.insufficientBalance,
        );
        expect(
          ShareCoinException.fromServerCode('raw-private-stack').message,
          isNot(contains('raw-private-stack')),
        );
      },
    );
    test(
      '28 malformed or cross-account backend payloads are not wallet balances',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async => f.backend.envelope(
          scope,
          coinFixtureBalance(user: 'another-user').toJson(),
        );
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.malformed)),
        );
        expect(f.service.cachedWallet, isNull);
      },
    );
    test('30 backend pending rewards never add local coins', () async {
      final f = CoinServiceFixture();
      final before = (await f.service.getCurrentWallet()).data.available;
      final result = await f.service.submitRewardEvent(coinFixtureReward());
      expect(result.data.status, RewardEventStatus.pending);
      expect((await f.service.getCurrentWallet()).data.available, before);
    });
    test(
      'client cannot submit an already-approved reward as evidence',
      () async {
        final f = CoinServiceFixture();
        await expectLater(
          f.service.submitRewardEvent(
            coinFixtureReward(status: RewardEventStatus.approved),
          ),
          throwsA(coinError(CoinErrorCode.invalidRequest)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test(
      'unconfigured backend and missing account are honest unavailable states',
      () async {
        final empty = ShareCoinService();
        addTearDown(empty.dispose);
        await expectLater(
          empty.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.notConfigured)),
        );
        expect(empty.cachedWallet, isNull);
        final f = CoinServiceFixture();
        f.backend.switchAccount(null);
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(coinError(CoinErrorCode.unauthenticated)),
        );
      },
    );
    test('restricted accounts cannot submit claims', () async {
      final f = CoinServiceFixture();
      f.backend.accountStatus = AccountStatus.suspended;
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward()),
        throwsA(coinError(CoinErrorCode.restricted)),
      );
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      'offline reward claims are not queued as money or sent to backend',
      () async {
        final f = CoinServiceFixture()..goOffline();
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.offline)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        f.internet = InternetState.available;
        f.backend.serviceState = CoinServiceState.reachable;
        await f.service.submitRewardEvent(coinFixtureReward());
        expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      },
    );
    test(
      'offer starts are idempotent and cannot become completed rewards',
      () async {
        final f = CoinServiceFixture();
        final results = await Future.wait([
          f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
          f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
        ]);
        expect(results.first.data.status, OfferStatus.started);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test('expired offers are rejected using backend response time', () async {
      final f = CoinServiceFixture();
      f.backend.expiredOffer = true;
      await expectLater(
        f.service.startOffer('offer-1', idempotencyKey: 'start-key'),
        throwsA(coinError(CoinErrorCode.invalidRequest)),
      );
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
    });
    test('server policy blocks an already-active withdrawal', () async {
      final f = CoinServiceFixture();
      f.backend.activeWithdrawals = ['other-request'];
      await expectLater(
        f.service.requestWithdrawal(coinFixtureIntent()),
        throwsA(coinError(CoinErrorCode.conflict)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test('changed quote is not silently accepted', () async {
      final f = CoinServiceFixture();
      final json = coinFixtureIntent().toJson()..['expectedFeeMinor'] = 11;
      await expectLater(
        f.service.requestWithdrawal(WithdrawalIntent.fromJson(json)),
        throwsA(coinError(CoinErrorCode.policyChanged)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      'uncertain withdrawal keeps its key and prevents blind replay',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.requestWithdrawal) {
            throw TimeoutException('test transport timeout');
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        await expectLater(
          f.service.requestWithdrawal(coinFixtureIntent(key: 'new-key')),
          throwsA(coinError(CoinErrorCode.conflict)),
        );
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        final status = await f.service.getWithdrawalByKey('withdraw-key-1');
        expect(status.data.status, WithdrawalStatus.paid);
        expect(f.service.hasPendingWithdrawal, isFalse);
      },
    );
    test(
      'malformed write confirmation is uncertain, not a refund or payout',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.submitReward) {
            return f.backend.envelope(scope, {'invalid': true});
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.uncertain)),
        );
        expect(f.backend.balance, 10000);
      },
    );
    test(
      'account switch hides cached wallet and rejects late results',
      () async {
        final f = CoinServiceFixture();
        final pending = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.wallet) {
            started.complete();
            return pending.future;
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        final oldScope = f.backend.scope!;
        final request = f.service.getCurrentWallet();
        final expectation = expectLater(
          request,
          throwsA(coinError(CoinErrorCode.accountChanged)),
        );
        await started.future;
        f.backend.switchAccount(
          AccountScope(userId: 'user-2', sessionId: 'session-2'),
        );
        pending.complete(
          f.backend.envelope(oldScope, coinFixtureBalance().toJson()),
        );
        await expectation;
        expect(f.service.cachedWallet, isNull);
      },
    );
    test(
      'status and cache reads cannot invent local approval or transactions',
      () async {
        final f = CoinServiceFixture();
        final history = await f.service.getTransactionHistory();
        expect(
          history.data.items.single.status,
          CoinTransactionStatus.reversed,
        );
        final daily = await f.service.getDailyRewardConfiguration();
        expect(daily.data.eligible, isFalse);
        final offers = await f.service.getOffers();
        f.goOffline();
        final cached = await f.service.getOffers();
        expect(cached.cached, isTrue);
        expect(
          cached.data.items.single.offerId,
          offers.data.items.single.offerId,
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
    test('pagination metadata must agree with the request size', () async {
      final f = CoinServiceFixture();
      f.backend.handler = (op, scope, args) async {
        final data = f.backend.dataFor(op, scope, args);
        if (op == ShareCoinOperation.offers) {
          data['page'] = PageInfo(
            page: 1,
            pageSize: 100,
            total: 1,
            hasNext: false,
          ).toJson();
        }
        return f.backend.envelope(scope, data);
      };
      await expectLater(
        f.service.getOffers(query: OfferQuery(pageSize: 20)),
        throwsA(coinError(CoinErrorCode.malformed)),
      );
    });
    test(
      'suspension before provider submission prevents a background mutation',
      () async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.currentUser) f.service.suspend();
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await expectLater(
          f.service.submitRewardEvent(coinFixtureReward()),
          throwsA(coinError(CoinErrorCode.offline)),
        );
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      },
    );
  });

  group('Part 5 late-response safeguards', () {
    test('a pre-mutation wallet response cannot become a fresh post-mutation balance', () async {
      final f = CoinServiceFixture();
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      f.backend.handler = (op, scope, args) async {
        if (op == ShareCoinOperation.wallet) {
          started.complete();
          return pending.future;
        }
        return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
      };
      final wallet = f.service.getCurrentWallet(allowCached: false);
      final rejected = expectLater(
        wallet,
        throwsA(coinError(CoinErrorCode.unavailable)),
      );
      await started.future;
      await f.service.submitRewardEvent(coinFixtureReward());
      pending.complete(
        f.backend.envelope(f.backend.scope!, coinFixtureBalance().toJson()),
      );
      await rejected;
      expect(f.service.cachedWallet, isNull);
    });
    test('an account change during mutation notification cannot post for the old user', () async {
      final f = CoinServiceFixture();
      var switched = false;
      f.service.addListener(() {
        if (!switched) {
          switched = true;
          f.backend.switchAccount(
            AccountScope(userId: 'user-2', sessionId: 'session-2'),
          );
        }
      });
      await expectLater(
        f.service.submitRewardEvent(coinFixtureReward()),
        throwsA(coinError(CoinErrorCode.uncertain)),
      );
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    testWidgets(
      'uncertain withdrawal UI checks its original key without a second submission',
      (tester) async {
        final f = CoinServiceFixture();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.requestWithdrawal) {
            throw TimeoutException('test timeout');
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await mountCoinDashboard(tester, f.service);
        await tapCoinKey(tester, 'coin-withdraw');
        await tester.tap(find.byKey(const ValueKey('submit-coin-withdrawal')));
        await tester.pumpAndSettle();
        expect(find.text('Check request status'), findsOneWidget);
        final submit = tester.widget<FilledButton>(
          find.byKey(const ValueKey('submit-coin-withdrawal')),
        );
        expect(submit.onPressed, isNull);
        await tester.tap(
          find.byKey(const ValueKey('check-coin-withdrawal-status')),
        );
        await tester.pumpAndSettle();
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        expect(find.textContaining('Backend status: paid'), findsOneWidget);
      },
    );
  });

  group('Part 5 connectivity', () {
    test('24 initial state does not assume internet or a backend', () {
      final service = ConnectivityService(localProbe: () async => []);
      addTearDown(service.dispose);
      expect(service.value.internet, InternetState.unknown);
      expect(service.value.shareCoin, CoinServiceState.unconfigured);
    });
    test('25 local IPv4 and offline internet are independent', () async {
      final service = ConnectivityService(
        localProbe: () async => ['192.168.2.2', '8.8.8.8'],
        internetProbe: () async => InternetState.offline,
        serviceProbe: () async => CoinServiceState.unreachable,
      );
      addTearDown(service.dispose);
      final state = await service.refresh();
      expect(state.hasLocalCandidate, isTrue);
      expect(state.internet, InternetState.offline);
      expect(state.canRequestRewards, isFalse);
      expect(state.localAddresses, ['192.168.2.2']);
    });
    test(
      '26 disposal ignores late probes without publishing new state',
      () async {
        final probe = Completer<List<String>>();
        final service = ConnectivityService(localProbe: () => probe.future);
        var calls = 0;
        service.addListener(() => calls += 1);
        final request = service.refresh();
        final before = calls;
        service.dispose();
        probe.complete(['192.168.2.2']);
        await request;
        expect(calls, before);
      },
    );
    test('simultaneous refreshes use one set of probes', () async {
      final probe = Completer<List<String>>();
      var calls = 0;
      final service = ConnectivityService(
        localProbe: () {
          calls += 1;
          return probe.future;
        },
      );
      addTearDown(service.dispose);
      final first = service.refresh();
      final second = service.refresh();
      expect(identical(first, second), isTrue);
      probe.complete(['192.168.2.2']);
      await Future.wait([first, second]);
      expect(calls, 1);
    });
    test(
      'suspended old checks cannot overwrite a newer resumed check',
      () async {
        final old = Completer<List<String>>();
        var calls = 0;
        final service = ConnectivityService(
          localProbe: () =>
              ++calls == 1 ? old.future : Future.value(['10.0.0.2']),
        );
        addTearDown(service.dispose);
        final previous = service.refresh();
        service.suspend();
        service.resume();
        await service.refresh();
        old.complete(['192.168.1.2']);
        await previous;
        expect(service.value.localAddresses, ['10.0.0.2']);
      },
    );
    test(
      'probe failure is limited/error, not a fabricated reachable service',
      () async {
        final service = ConnectivityService(
          localProbe: () async => throw StateError('test failure'),
          internetProbe: () async => throw TimeoutException('test'),
          serviceProbe: () async => CoinServiceState.limited,
        );
        addTearDown(service.dispose);
        final state = await service.refresh();
        expect(state.localNetwork, LocalNetworkState.error);
        expect(state.internet, InternetState.error);
        expect(state.shareCoin, CoinServiceState.limited);
        expect(state.canRequestRewards, isFalse);
      },
    );
    test('a listener may dispose connectivity during publication', () async {
      final service = ConnectivityService(localProbe: () async => []);
      service.addListener(service.dispose);
      await service.refresh();
      expect(await service.changes.isEmpty, isTrue);
    });
  });

  group('Part 5 dashboard and navigation', () {
    testWidgets('new local user sees setup and no invented zero balance', (
      tester,
    ) async {
      final connection = ConnectivityService(localProbe: () async => []);
      final service = ShareCoinService(connectivity: connection);
      addTearDown(service.dispose);
      addTearDown(connection.dispose);
      await mountCoinDashboard(tester, service);
      expect(find.text('Wallet unavailable'), findsOneWidget);
      expect(find.textContaining('Account setup required'), findsOneWidget);
      expect(find.text('0 ShareCoin'), findsNothing);
      await tapCoinKey(tester, 'coin-withdraw');
      expect(find.text('Withdrawals unavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('submit-coin-withdrawal')),
        findsNothing,
      );
    });
    testWidgets('validated wallet and offline cache labels are distinct', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      await mountCoinDashboard(tester, f.service);
      expect(find.text('10,000 ShareCoin'), findsOneWidget);
      f.goOffline();
      await tester.tap(find.byKey(const ValueKey('refresh-share-coin')));
      await tester.pumpAndSettle();
      expect(find.textContaining('CACHED'), findsOneWidget);
      expect(find.text('10,000 ShareCoin'), findsOneWidget);
    });
    testWidgets('file actions remain enabled while reward service is offline', (
      tester,
    ) async {
      final f = CoinServiceFixture()..goOffline();
      ShareCoinFileAction? action;
      await mountCoinDashboard(
        tester,
        f.service,
        action: (value) => action = value,
      );
      await tapCoinKey(tester, 'coin-send-files');
      expect(action, ShareCoinFileAction.send);
      await tapCoinKey(tester, 'coin-receive-files');
      expect(action, ShareCoinFileAction.receive);
      await tapCoinKey(tester, 'coin-saved-files');
      expect(action, ShareCoinFileAction.saved);
      await tapCoinKey(tester, 'coin-file-history');
      expect(action, ShareCoinFileAction.history);
    });
    testWidgets('dashboard handles small screens and enlarged text', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await mountCoinDashboard(tester, f.service, size: const Size(320, 740));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('coin-file-history')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'disposal during wallet load does not update a dead dashboard',
      (tester) async {
        final f = CoinServiceFixture();
        final pending = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        f.backend.handler = (op, scope, args) async {
          if (op == ShareCoinOperation.wallet) {
            started.complete();
            return pending.future;
          }
          return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
        };
        await tester.pumpWidget(
          MaterialApp(home: ShareCoinHomeScreen(service: f.service)),
        );
        for (var i = 0; i < 50 && !started.isCompleted; i += 1) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(started.isCompleted, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete(
          f.backend.envelope(f.backend.scope!, coinFixtureBalance().toJson()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '31 existing home opens ShareCoin without losing selected files',
      (tester) async {
        final f = CoinServiceFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async =>
                  FileSelection(files: [baseline.sampleFile()]),
              onToggleTheme: () {},
              shareCoinScreenBuilder: (_) =>
                  ShareCoinHomeScreen(service: f.service),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await baseline.tapSelect(tester);
        await baseline.tapNavigation(tester, 'nav-home');
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('share-coin-home')), findsOneWidget);
        await tapCoinKey(tester, 'coin-send-files');
        expect(
          find.byKey(const ValueKey('send-selected-button')),
          findsOneWidget,
        );
        expect(find.text('1 file · 1.5 KiB'), findsOneWidget);
      },
    );
    testWidgets(
      '32 receiver and saved-history routes still use original screens',
      (tester) async {
        final f = CoinServiceFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async => FileSelection(files: []),
              onToggleTheme: () {},
              historyScreenBuilder: (_) => HistoryScreen(
                service: baseline.FakeHistoryService(
                  HistorySnapshot(transfers: []),
                ),
              ),
              shareCoinScreenBuilder: (_) =>
                  ShareCoinHomeScreen(service: f.service),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await tapCoinKey(tester, 'coin-receive-files');
        expect(
          find.byKey(const ValueKey('start-receiving-button')),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await tapCoinKey(tester, 'coin-file-history');
        expect(find.byKey(const ValueKey('history-scaffold')), findsOneWidget);
      },
    );
    testWidgets('account changes remove previously displayed wallet values', (
      tester,
    ) async {
      final f = CoinServiceFixture();
      await mountCoinDashboard(tester, f.service);
      f.backend.switchAccount(
        AccountScope(userId: 'user-2', sessionId: 'new-session'),
      );
      await tester.pumpAndSettle();
      expect(find.text('10,000 ShareCoin'), findsNothing);
      expect(find.text('Wallet unavailable'), findsOneWidget);
    });
  });
}
```

## Existing Architecture Inspected

The available `ShareBondhu_Part_04.zip` was the authoritative matching baseline: version 0.4.0+4, Files 1–20, and a documented 143-test result. Its 113 entries were read/inventoried and compared with the starting project, including all Dart source/test files, dependency files, native configuration and Parts 1–4 contracts. It contained the complete sharing stack but no wallet/account/reward/withdrawal implementation. No separately named new ZIP attachment was visible.

## Files Added

Files 21, 22, 23, 24 and 25 above, using the requested paths. These are the first ShareCoin foundation, not a replacement wallet.

## Files Updated

- File 1: version changed to 0.5.0+5 only.
- File 4: additive ShareCoin toolbar/route integration and routing back to existing sharing actions; all old classes/functions retained.
- File 20: new imports, one Part 5 test-registration call and appended fixtures/tests. Original Part 4 test bodies remain intact.
- Documentation, inventory and verification reports updated; older versioned artifacts preserved.

Complete replacement Files 1, 4 and 20 are included above. Every other original Dart source/test file, the lockfile and Android/iOS files is byte-identical to the Part 4 ZIP.

## Dependencies Added

**None.** All exact versions from the baseline remain. Flutter 3.47.2 / Dart 3.13.2 was used. No ad/auth/connectivity SDK or new native permission was added.

## Existing Logic Preserved

The original main entry, theme/picker, Home/Files/Guide tabs, selection, manual/QR pairing, explicit approval, TLS authentication/pinning, five v1 endpoints, streaming, SHA-256, atomic commit/receipt, cancellation/retry, progress/result, saved history/export and lifecycle handling remain. Original model/service/screen/widget/native files are byte-identical except the stated home integration. Reward connectivity never gates the old transfer engine.

Sharing limits remain 50 files, 2 GiB/file, 4 GiB/batch, 10-minute invitations and 60-second receiver approval. The previous foreground/IPv4 restrictions remain.

## ShareCoin Architecture

**User Action → Provider/Tracking Event → RewardEvent Claim → Backend Validation → Transaction → Wallet Refresh**

The client never adds a requested reward to a balance. A started offer, watched-ad client event, promotion open, device date or locally created account is not proof of earning. The default backend is explicitly unconfigured, showing no fake balance.

## Withdrawal Architecture

**Backend Wallet/Policy → Idempotent Request → Server Validation/Reservation → Processing by Admin/Provider → Backend Payout Status → Wallet Refresh**

Minimum/balance/policy/fee/destination/conflict checks are client safeguards, not final authority. No local subtraction is treated as payment. Unknown responses retain the original key; the form can check it without reposting. bKash, Nagad, Rocket, PayPal and Bank are configuration choices only.

## Backend Requirements

Implement the authenticated HTTPS ShareCoinBackend adapter and the response envelope/operation contracts in `docs/PART_05_BACKEND_CONTRACT.md`. Real account/authentication, wallet/ledger storage, provider verification, campaign/daily/referral policy, payout destinations/providers, reconciliation and admin/audit services remain required. No remote origin, sign-in provider or production ad ID is hard-coded.

Coin values are bounded whole integers; financial conversions use rational rates, integer minor units and BigInt intermediates. Raw payout credentials do not belong in these models. Gateway adapters must bound response bytes before JSON parsing and authenticate every operation; AccountScope is correlation, not a credential.

## Anti-Fraud Requirements

Client duplicate/idempotency guards and account/lifecycle checks are not sufficient against modified clients or multiple devices. Enforce authentication, authorization, signed provider callbacks/attribution, provider-event uniqueness, payload-bound idempotency, server-time eligibility, campaign amounts/limits, referral qualification, risk/rate checks, atomic balances/reservations, conflicting withdrawals, reconciliation and reversals on the server. Review provider incentive/redemption rules and applicable privacy/payment obligations.

Cache and client idempotency state are bounded and memory-only. Settled entries can be evicted and app/session state can reset; backend uniqueness remains mandatory. No offline credit queue is implemented.

## Test Coverage

Actually executed:

- Previous baseline retained: **143 tests**.
- New Part 5 tests: **61**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **204 tests passed**.

New tests cover wallet/transaction/reward/user/referral/offer/promotion/ad/payout serialization and validation, negative/overflow amounts, rational conversion, event/start/withdrawal idempotency, minimum/balance/conflicts, unknown results and original-key status, offline cache, account switching, late wallet replies, connectivity coalescing/stale/disposal/error behavior, dashboard lifecycle/layout and retained sharing routes.

The reward tests use a test-only backend. Existing loopback TLS tests run real socket/disk operations on one computer. Neither constitutes real advertiser payouts, production authentication, app-install attribution, cash withdrawal, native build, real-phone/camera or two-phone Wi-Fi verification.

## Verification Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Use a hot restart when updating these Dart classes. No newly required native full rebuild solely for Part 5: no plugin/permission changed. Earlier native package additions still require a rebuild if they were never included in the installed app. Android needs a compatible JDK/SDK; iPhone compilation requires Mac/Xcode/signing.

## Manual Verification

**Required real-device/staging checks — not performed here:**

1. On Android, verify the original picker, Receive files, Saved files, three tabs and theme remain reachable. Open the ShareCoin toolbar entry.
2. Confirm the default build shows Wallet unavailable / Account setup required, no random/zero withdrawable balance, and clear unconfigured messages for earning/payment actions.
3. Test no-internet and private-Wi-Fi-only conditions. Status must distinguish internet/local/backend; file-sharing shortcuts remain usable. Private IPv4 presence alone is not a Wi-Fi or peer-connection guarantee.
4. On two real phones, test original Send/Receive, QR and manual pairing, receiver acceptance/decline, small/multiple/zero-byte files, progress, cancellation/retry, receipt, Saved Files/history and SHA-256.
5. With a future staging backend, verify authenticated and explicitly cached wallet views, account switching, pending/rejected/approved events, visible reversals and transaction IDs. Repeated callbacks must not create duplicate credits.
6. With staging payout configuration only, test minimum, balance, active-request conflicts, fee/policy changes, duplicate taps, timeout and Check request status with the original key. Confirm no client balance deduction and do not call staging records real payouts.
7. Background/dispose the dashboard during operations, resume and refresh. Old-account or stale pre-mutation wallet data must not return.
8. Separately test iPhone navigation, local-network/camera permission behavior, existing TLS sharing and native export. No iPhone test is claimed.

## Known Limitations

This is an implemented client foundation, not a connected earning/payout product. Real login providers, backend transport/storage, ad playback, offer attribution, daily/referral validation and payment integrations are not connected. The dashboard contains bounded catalog/config/history previews; the full large Offerwall is Part 6 work. Provider images/links are DTO data, not automatically fetched/launched.

Internet is unknown until an explicit internet probe is supplied; backend health is independent. Caches/idempotency bookkeeping are not persistent authority. Actual fraud prevention and financial transactions must run on the backend. Native/device/build/store verification remains outstanding; existing sharing limitations are unchanged.

# ▶ Next — Part 6 (File 26–30)
