import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../services/connectivity_service.dart';
import '../services/share_coin_service.dart';
import '../config/backend_config.dart';
import '../services/auth_session_service.dart';
import '../services/authenticated_backend_repository.dart';
import '../services/rewarded_ad_provider.dart';
import '../services/offerwall_service.dart';
import 'offerwall_screen.dart';
import 'reward_center_screen.dart';

enum ShareCoinFileAction { send, receive, saved, history }

class ShareCoinHomeScreen extends StatefulWidget {
  const ShareCoinHomeScreen({
    super.key,
    this.service,
    this.onFileAction,
    this.offerPolicy,
    this.adFactory = createSafeRewardedAdProvider,
    this.backendConfig,
    this.auth,
    this.linkLauncher = launchRewardLink,
  });
  final ShareCoinService? service;
  final BackendConfig? backendConfig;
  final AuthSessionService? auth;
  final ValueChanged<ShareCoinFileAction>? onFileAction;
  final OfferResourcePolicy? offerPolicy;
  final RewardedAdAdapter Function() adFactory;
  final RewardLinkLauncher linkLauncher;
  @override
  State<ShareCoinHomeScreen> createState() => _ShareCoinHomeScreenState();
}

class _ShareCoinHomeScreenState extends State<ShareCoinHomeScreen>
    with WidgetsBindingObserver {
  late final ShareCoinService _service;
  late final bool _ownsService;
  AuthSessionService? _auth;
  AuthenticatedShareCoinBackend? _backend;
  bool _ownsAuth = false;
  CoinData<ShareCoinBalance>? _wallet;
  CoinData<ShareCoinUser>? _user;
  String? _scopeKey;
  String? _notice;
  String? _busyAction;
  bool _loading = false;
  bool _closed = false;
  bool _navigating = false;
  int _generation = 0;
  bool get _canUpdate => mounted && !_closed;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    if (widget.service != null) {
      _service = widget.service!;
      _auth = widget.auth;
    } else {
      final config =
          widget.backendConfig ??
          widget.auth?.config ??
          BackendConfig.fromEnvironment();
      _ownsAuth = widget.auth == null;
      _auth = widget.auth ?? AuthSessionService(config: config);
      _backend = AuthenticatedShareCoinBackend(config: config, auth: _auth!);
      _service = ShareCoinService(
        backend: _backend,
        requestTimeout:
            config.requestTimeout +
            _auth!.operationTimeout +
            const Duration(seconds: 1),
      );
    }
    _auth?.addListener(_authChanged);
    _scopeKey = _service.accountKey;
    _service.addListener(_serviceChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _authChanged() {
    if (!_canUpdate) return;
    _serviceChanged();
    setState(() {});
  }

  Future<void> _account() async {
    final auth = _auth;
    if (auth == null) {
      await _info(
        'Account integration',
        'This service was supplied externally. Its authentication adapter owns account management.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<AuthSessionSnapshot>(
        valueListenable: auth,
        builder: (context, state, child) => AlertDialog(
          title: const Text('Account / API session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Session: ${state.status.name}',
                  key: const ValueKey('auth-session-status'),
                ),
                if (state.user != null) Text(state.user!.displayName),
                if (state.error != null)
                  Text(AuthSessionException(state.error!).message),
                const SizedBox(height: 12),
                const Text(
                  'No login provider or production credentials are bundled. A real adapter must verify identity through the configured backend.',
                ),
                const SizedBox(height: 12),
                for (final method in AuthenticationMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      key: ValueKey('auth-sign-in-${method.name}'),
                      onPressed:
                          !auth.availableMethods.contains(method) ||
                              state.status == AuthStatus.authenticating ||
                              state.status == AuthStatus.refreshing
                          ? null
                          : () async {
                              try {
                                await auth.signIn(method);
                              } catch (_) {}
                              if (_canUpdate) unawaited(_refresh());
                            },
                      child: Text(switch (method) {
                        AuthenticationMethod.google => 'Google',
                        AuthenticationMethod.apple => 'Apple',
                        AuthenticationMethod.emailOtp => 'Email / OTP',
                        AuthenticationMethod.phoneOtp => 'Phone / OTP',
                      }),
                    ),
                  ),
                if (state.scope != null)
                  FilledButton(
                    key: const ValueKey('auth-sign-out'),
                    onPressed: () async {
                      await auth.logout();
                    },
                    child: const Text('Sign out'),
                  ),
              ],
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
      _auth?.suspend();
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
      _auth?.resume();
      _service.resume();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_serviceChanged);
    _auth?.removeListener(_authChanged);
    if (_ownsService) _service.dispose();
    _backend?.dispose();
    if (_ownsAuth) _auth?.dispose();
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

  Future<void> _openOfferwall() async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => OfferwallScreen(
            service: _service,
            policy: widget.offerPolicy,
            launcher: widget.linkLauncher,
            onCatalogInfo: _offers,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

  Future<void> _openRewardCenter(
    RewardCenterMode mode,
    VoidCallback configuration,
  ) async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => RewardCenterScreen(
            service: _service,
            mode: mode,
            policy: widget.offerPolicy,
            adFactory: widget.adFactory,
            launcher: widget.linkLauncher,
            onConfiguration: configuration,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

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
        'No ad SDK is bundled. A configured provider completion is only an event claim; the backend must verify it before crediting ShareCoin.',
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
          IconButton(
            key: const ValueKey('share-coin-account'),
            tooltip: 'Account session',
            onPressed: _account,
            icon: const Icon(Icons.person_outline_rounded),
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
                      () => _openRewardCenter(RewardCenterMode.ad, _ads),
                      'Provider / backend required',
                      key: 'coin-watch-ads',
                    ),
                    _tile(
                      'Offers',
                      Icons.apps_rounded,
                      _openOfferwall,
                      'Paginated Offerwall',
                      key: 'coin-offers',
                    ),
                    _tile(
                      'Promotions',
                      Icons.campaign_outlined,
                      () => _openRewardCenter(
                        RewardCenterMode.promotions,
                        _promotions,
                      ),
                      'Campaign verification',
                      key: 'coin-promotions',
                    ),
                    _tile(
                      'Daily Reward',
                      Icons.calendar_today_outlined,
                      () => _openRewardCenter(RewardCenterMode.daily, _daily),
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
                      () => _openRewardCenter(
                        RewardCenterMode.transactions,
                        _transactions,
                      ),
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
                      () => _openRewardCenter(
                        RewardCenterMode.withdrawals,
                        _withdrawals,
                      ),
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
  late final ShareCoinReconciler _reconciler;
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
    _reconciler = ShareCoinReconciler(service: widget.service);
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
    _reconciler.dispose();
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
      try {
        final sync = await _reconciler.reconcileWithdrawal(
          withdrawalId: response.data.withdrawalId,
        );
        if (mounted && _ownerMatches) setState(() => _result = sync.request);
      } catch (_) {
        if (mounted && _ownerMatches) {
          setState(
            () => _error = 'Request recorded. Refresh status and wallet to finish synchronization.',
          );
        }
      }
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
      try {
        final sync = await _reconciler.reconcileWithdrawal(
          idempotencyKey: _idempotencyKey,
        );
        if (mounted && _ownerMatches) setState(() => _result = sync.request);
      } catch (_) {
        if (mounted && _ownerMatches) {
          setState(
            () => _error = 'Backend status received. Wallet/history synchronization is still required.',
          );
        }
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
