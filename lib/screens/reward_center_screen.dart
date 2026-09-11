import 'dart:async';

import 'package:flutter/material.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../services/offerwall_service.dart';
import '../services/share_coin_service.dart';
import '../services/authenticated_backend_repository.dart';
import 'offerwall_screen.dart' show OfferThumbnail;

abstract interface class RewardedAdAdapter {
  bool get configured;
  String? get provider;
  Stream<RewardedAdEvent> get events;
  Future<void> load(RewardSession session, AdConfiguration configuration);
  Future<void> show(String sessionId);
  Future<void> dismiss();
  Future<void> dispose();
}

class UnavailableRewardedAdAdapter implements RewardedAdAdapter {
  const UnavailableRewardedAdAdapter();
  @override
  bool get configured => false;
  @override
  String? get provider => null;
  @override
  Stream<RewardedAdEvent> get events => const Stream<RewardedAdEvent>.empty();
  @override
  Future<void> load(RewardSession session, AdConfiguration configuration) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> show(String sessionId) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> dismiss() async {}
  @override
  Future<void> dispose() async {}
}

RewardedAdAdapter createUnavailableRewardedAdAdapter() =>
    const UnavailableRewardedAdAdapter();

class RewardCoordinator extends ValueNotifier<RewardViewState> {
  RewardCoordinator({
    required this.service,
    RewardedAdAdapter? ad,
    OfferResourcePolicy? policy,
    this.launcher = launchRewardLink,
    this.adPlacement = 'rewarded',
    this.clock,
    this.autoTick = true,
  }) : ad = ad ?? createUnavailableRewardedAdAdapter(),
       policy = policy ?? OfferResourcePolicy(),
       super(const RewardViewState()) {
    coinId(adPlacement, 'adPlacement');
    _scope = service.accountKey;
    _reconciler = ShareCoinReconciler(service: service);
    service.addListener(_accountChanged);
    _events = this.ad.events.listen(
      _onAdEvent,
      onError: (Object error, StackTrace stack) {
        if (!_closed &&
            !_submitted &&
            <RewardPhase>{
              RewardPhase.loading,
              RewardPhase.ready,
              RewardPhase.showing,
            }.contains(value.phase)) {
          _providerFailed = true;
          _emit(
            RewardPhase.failed,
            'The ad provider reported an error. No credit is inferred.',
          );
        }
      },
    );
  }
  final ShareCoinService service;
  late final ShareCoinReconciler _reconciler;
  final RewardedAdAdapter ad;
  final OfferResourcePolicy policy;
  final RewardLinkLauncher launcher;
  final String adPlacement;
  final Duration Function()? clock;
  final bool autoTick;
  final Stopwatch _watch = Stopwatch()..start();
  late final StreamSubscription<RewardedAdEvent> _events;
  Timer? _ticker;
  String? _scope, _requestKey;
  CoinData<RewardSession>? _session;
  DateTime? _anchor, _cooldownUntil;
  Duration _anchorTick = Duration.zero, _lastTick = Duration.zero;
  int _generation = 0;
  bool _closed = false,
      _suspended = false,
      _working = false,
      _submitted = false,
      _providerFailed = false;
  bool get canCheckStatus =>
      !_closed &&
      !_suspended &&
      !_working &&
      (_session != null || _requestKey != null);
  bool get canShow =>
      !_closed && !_suspended && !_working && value.phase == RewardPhase.ready;
  bool get hasUnresolved =>
      (_session != null || _requestKey != null) &&
      <RewardPhase>{
        RewardPhase.tracking,
        RewardPhase.rewardPending,
        RewardPhase.checkingCredit,
        RewardPhase.interrupted,
      }.contains(value.phase);
  Duration get _now {
    final next = clock?.call() ?? _watch.elapsed;
    if (next > _lastTick) _lastTick = next;
    return _lastTick;
  }

  DateTime? get serverEstimate => _anchor?.add(_now - _anchorTick);
  void _serverClock(DateTime time) {
    _anchor = time;
    _anchorTick = _now;
  }

  bool _valid(int generation, String? scope) =>
      !_closed &&
      !_suspended &&
      generation == _generation &&
      scope == service.accountKey;
  void _accountChanged() {
    if (_closed || _scope == service.accountKey) return;
    _scope = service.accountKey;
    _generation += 1;
    _session = null;
    _requestKey = null;
    _submitted = false;
    _working = false;
    _ticker?.cancel();
    _anchor = null;
    _cooldownUntil = null;
    unawaited(ad.dismiss().catchError((Object error) {}));
    value = const RewardViewState(
      message: 'Account changed. Start a new eligibility check.',
    );
  }

  void _emit(
    RewardPhase phase,
    String message, {
    RewardEvent? event,
    ShareCoinTransaction? transaction,
  }) {
    if (_closed) return;
    if (phase != RewardPhase.cooldown) {
      _ticker?.cancel();
      _ticker = null;
    }
    final now = serverEstimate;
    final remaining =
        now != null && _cooldownUntil != null && now.isBefore(_cooldownUntil!)
        ? _cooldownUntil!.difference(now)
        : Duration.zero;
    value = RewardViewState(
      phase: phase,
      session: _session?.data,
      event: event ?? value.event,
      transaction: transaction ?? value.transaction,
      message: message,
      cooldownRemaining: remaining,
    );
  }

  void refreshClock() {
    if (!_closed && !_suspended && value.phase == RewardPhase.cooldown) {
      _emit(
        value.phase,
        'Cooldown is a backend policy. Recheck eligibility when the timer ends.',
      );
    }
  }

  void _tickCooldown() {
    _ticker?.cancel();
    if (autoTick) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => refreshClock(),
      );
    }
  }

  bool _acceptSession(CoinData<RewardSession> response) {
    final session = response.data;
    if (session.issuedAt.isAfter(response.serverTime)) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    _session = response;
    _serverClock(response.serverTime);
    _cooldownUntil = session.notBefore;
    if (session.availability == RewardAvailability.dailyLimit) {
      _emit(
        RewardPhase.dailyLimit,
        'The backend daily limit has been reached. Device date does not reset it.',
      );
      return false;
    }
    if (session.availability == RewardAvailability.cooldown ||
        response.serverTime.isBefore(session.notBefore)) {
      _emit(
        RewardPhase.cooldown,
        'Wait for the backend cooldown, then recheck eligibility.',
      );
      _tickCooldown();
      return false;
    }
    if (!session.usableAt(response.serverTime)) {
      _emit(
        RewardPhase.failed,
        'This reward session is expired, restricted or unavailable.',
      );
      return false;
    }
    return true;
  }

  Future<void> loadAd() async {
    if (_closed ||
        _suspended ||
        _working ||
        value.busy ||
        hasUnresolved ||
        value.cooldownRemaining > Duration.zero) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Checking ad configuration and backend eligibility.',
    );
    try {
      if (!ad.configured || !service.rewardExtensionsAvailable) {
        throw const ShareCoinException(CoinErrorCode.notConfigured);
      }
      final configuration = await service.getAdConfiguration(
        allowCached: false,
      );
      if (!_valid(generation, scope)) return;
      if (configuration.data.premium ||
          !configuration.data.rewardedEnabled ||
          configuration.data.provider != ad.provider) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.adReward,
        adPlacement,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (response.data.provider != ad.provider ||
          response.data.dailyLimit > configuration.data.dailyLimit) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      if (!_acceptSession(response)) return;
      await ad
          .load(response.data, configuration.data)
          .timeout(const Duration(seconds: 30));
      if (!_valid(generation, scope)) {
        await ad.dismiss();
        return;
      }
      if (_providerFailed) {
        throw const ShareCoinException(CoinErrorCode.unavailable);
      }
      if (!response.data.usableAt(serverEstimate!)) {
        _emit(
          RewardPhase.failed,
          'Ad session expired before it was ready. Recheck eligibility.',
        );
        return;
      }
      _emit(
        RewardPhase.ready,
        'Ad ready. Watching is not credit; the backend still verifies the provider event.',
      );
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException && error.outcomeUncertain
              ? RewardPhase.interrupted
              : RewardPhase.failed,
          _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> showAd() async {
    final ticket = _session?.data;
    if (!canShow || ticket == null) return;
    if (serverEstimate == null || !ticket.usableAt(serverEstimate!)) {
      _emit(RewardPhase.failed, 'Ad session expired. Recheck eligibility.');
      return;
    }
    final generation = _generation;
    final scope = service.accountKey;
    _emit(
      RewardPhase.showing,
      'Showing provider ad. No ShareCoin has been awarded by the client.',
    );
    try {
      await ad.show(ticket.sessionId);
    } catch (error) {
      if (_valid(generation, scope)) _emit(RewardPhase.failed, _message(error));
    }
  }

  void _onAdEvent(RewardedAdEvent event) {
    final ticket = _session?.data;
    if (_closed ||
        _suspended ||
        ticket == null ||
        event.sessionId != ticket.sessionId ||
        service.accountKey != _scope) {
      return;
    }
    if (event.type == RewardedAdEventType.failed &&
        value.phase == RewardPhase.loading) {
      _providerFailed = true;
      _emit(RewardPhase.failed, 'Ad loading failed. No reward was submitted.');
      return;
    }
    if (event.type == RewardedAdEventType.ready ||
        event.type == RewardedAdEventType.shown) {
      return;
    }
    if (value.phase != RewardPhase.showing || _submitted) return;
    switch (event.type) {
      case RewardedAdEventType.completed:
        if (event.providerEventId == null ||
            serverEstimate == null ||
            !ticket.usableAt(serverEstimate!)) {
          _emit(
            RewardPhase.interrupted,
            'Provider evidence is missing or the session expired. Check backend status.',
          );
        } else {
          unawaited(_claim(event.providerEventId!));
        }
      case RewardedAdEventType.skipped:
        _emit(
          RewardPhase.skipped,
          'Ad skipped. No reward event was submitted.',
        );
      case RewardedAdEventType.failed:
        _emit(RewardPhase.failed, 'Ad failed. No reward event was submitted.');
      case RewardedAdEventType.ready:
      case RewardedAdEventType.shown:
        break;
    }
  }

  Future<void> _claim(String providerEventId) async {
    final ticket = _session?.data;
    if (_closed || _suspended || _submitted || ticket == null) return;
    _submitted = true;
    _working = true;
    final generation = _generation;
    final scope = service.accountKey;
    _emit(
      RewardPhase.completed,
      'Action completed. Submitting a claim, not adding local coins.',
    );
    try {
      final event = RewardEvent(
        eventId: ticket.eventId,
        userId: ticket.userId,
        source: ticket.source,
        provider: ticket.provider,
        providerEventId: providerEventId,
        targetId: ticket.targetId,
        requestedCoins: ticket.rewardCoins,
        occurredAt: serverEstimate ?? ticket.issuedAt,
        status: RewardEventStatus.created,
        idempotencyKey: ticket.idempotencyKey,
        metadata: {'trace': ticket.sessionId},
      );
      final result = await service.submitRewardEvent(event);
      if (!_valid(generation, scope)) return;
      await _eventResult(result.data, generation, scope);
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException &&
                  error.code == CoinErrorCode.invalidRequest
              ? RewardPhase.rejected
              : RewardPhase.interrupted,
          _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> _eventResult(
    RewardEvent event,
    int generation,
    String? scope,
  ) async {
    final ticket = _session!.data;
    if (event.eventId != ticket.eventId ||
        event.userId != ticket.userId ||
        event.source != ticket.source ||
        event.provider != ticket.provider ||
        event.targetId != ticket.targetId ||
        event.idempotencyKey != ticket.idempotencyKey ||
        event.requestedCoins != ticket.rewardCoins) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    if (event.status == RewardEventStatus.rejected ||
        event.status == RewardEventStatus.cancelled) {
      _emit(
        RewardPhase.rejected,
        'Backend rejected or cancelled this reward.',
        event: event,
      );
      return;
    }
    if (event.status != RewardEventStatus.approved ||
        event.transactionId == null) {
      _emit(
        RewardPhase.rewardPending,
        'Reward Pending — waiting for backend validation.',
        event: event,
      );
      return;
    }
    _emit(
      RewardPhase.checkingCredit,
      'Approval reported. Verifying the ledger transaction.',
      event: event,
    );
    final response = await service.getTransaction(event.transactionId!);
    if (!_valid(generation, scope)) return;
    final transaction = response.data;
    if (transaction.source != ticket.source ||
        transaction.referenceId != ticket.targetId ||
        transaction.direction != CoinDirection.credit) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    if (transaction.status == CoinTransactionStatus.reversed) {
      await _reconciler.reconcileReward(event.eventId);
      if (!_valid(generation, scope)) return;
      _emit(
        RewardPhase.reversed,
        'This reward was reversed by the backend.',
        event: event,
        transaction: transaction,
      );
      return;
    }
    if (transaction.status == CoinTransactionStatus.rejected ||
        transaction.status == CoinTransactionStatus.cancelled) {
      await _reconciler.reconcileReward(event.eventId);
      if (!_valid(generation, scope)) return;
      _emit(
        RewardPhase.rejected,
        'The ledger did not post this reward.',
        event: event,
        transaction: transaction,
      );
      return;
    }
    if (transaction.status != CoinTransactionStatus.completed) {
      _emit(
        RewardPhase.rewardPending,
        'The ledger transaction is still pending.',
        event: event,
      );
      return;
    }
    final reconciliation = await _reconciler.reconcileReward(event.eventId);
    if (!_valid(generation, scope)) return;
    if (!reconciliation.reconciled) {
      _emit(
        reconciliation.state == RewardCreditState.reversed
            ? RewardPhase.reversed
            : reconciliation.state == RewardCreditState.rejected
            ? RewardPhase.rejected
            : RewardPhase.rewardPending,
        reconciliation.message,
        event: reconciliation.event ?? event,
        transaction: reconciliation.transaction,
      );
      return;
    }
    _emit(
      RewardPhase.rewardApproved,
      'Backend confirmed ${reconciliation.transaction!.signedAmount}. Wallet reconciled.',
      event: reconciliation.event ?? event,
      transaction: reconciliation.transaction,
    );
  }

  Future<void> claimDaily() async {
    if (_closed ||
        _suspended ||
        _working ||
        value.busy ||
        hasUnresolved ||
        value.cooldownRemaining > Duration.zero) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Checking the backend daily reward policy.',
    );
    try {
      final config = await service.getDailyRewardConfiguration(
        allowCached: false,
      );
      if (!_valid(generation, scope)) return;
      _serverClock(config.serverTime);
      _cooldownUntil = config.data.nextEligibleAt;
      if (!config.data.eligible) {
        _emit(
          RewardPhase.cooldown,
          'The backend has not made the daily reward available.',
        );
        _tickCooldown();
        return;
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.dailyReward,
        config.data.version,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (response.data.rewardCoins !=
          config.data.dayRewards[config.data.streakDay - 1]) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      if (!_acceptSession(response)) return;
      await _claim(response.data.providerEventId!);
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(RewardPhase.interrupted, _message(error));
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> startPromotion(
    Promotion promotion, {
    Future<bool> Function(Uri)? consent,
  }) async {
    if (_closed || _suspended || _working || value.busy || hasUnresolved) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Creating a backend tracking session. A click is not a reward.',
    );
    try {
      if (policy.linkOrigins.isEmpty) {
        throw const ShareCoinException(CoinErrorCode.notConfigured);
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.promotionReward,
        promotion.campaignId,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (!promotion.availableAt(response.serverTime) ||
          !_acceptSession(response)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      final url = response.data.launchUrl;
      if (!policy.allowsLink(url)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      if (consent != null && !await consent(url!)) {
        if (_valid(generation, scope)) {
          _emit(
            RewardPhase.tracking,
            'Tracking session created, but the link was not opened. No reward is inferred.',
          );
        }
        return;
      }
      if (!_valid(generation, scope)) return;
      final opened = await launcher(url!);
      if (_valid(generation, scope)) {
        _emit(
          RewardPhase.tracking,
          opened
              ? 'Campaign opened. Waiting for provider verification; no click credit.'
              : 'The provider link could not open. Check backend tracking status before starting again.',
        );
      }
    } catch (error) {
      if (_valid(generation, scope)) _emit(RewardPhase.failed, _message(error));
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshStatus() async {
    if (_closed ||
        _suspended ||
        _working ||
        _session == null && _requestKey == null) {
      return;
    }
    final generation = _generation;
    final scope = service.accountKey;
    _working = true;
    try {
      if (_session == null) {
        final result = await service.getRewardSessionStatus(
          requestKey: _requestKey,
        );
        if (!_valid(generation, scope)) return;
        _session = result;
        _serverClock(result.serverTime);
        if (result.data.availability != RewardAvailability.eligible &&
            !_acceptSession(result)) {
          return;
        }
      }
      final event = await service.getRewardEventStatus(_session!.data.eventId);
      if (_valid(generation, scope)) {
        await _eventResult(event.data, generation, scope);
      }
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException && error.code == CoinErrorCode.notFound
              ? RewardPhase.tracking
              : RewardPhase.interrupted,
          error is ShareCoinException && error.code == CoinErrorCode.notFound
              ? 'No verified provider event is available yet. Check later; do not create a duplicate claim.'
              : _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  String _message(Object error) => error is ShareCoinException
      ? error.message
      : 'The reward action could not be confirmed. Check backend history.';
  void suspend() {
    if (_closed) return;
    _suspended = true;
    _generation += 1;
    _working = false;
    _ticker?.cancel();
    unawaited(ad.dismiss().catchError((Object error) {}));
    if (_session != null &&
        !value.credited &&
        value.phase != RewardPhase.rejected &&
        value.phase != RewardPhase.reversed) {
      _emit(
        RewardPhase.interrupted,
        'Action interrupted. Provider/server status, not local state, decides any reward.',
      );
    }
  }

  void resume() {
    if (_closed) return;
    _suspended = false;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    _ticker?.cancel();
    _watch.stop();
    service.removeListener(_accountChanged);
    _reconciler.dispose();
    unawaited(_events.cancel());
    unawaited(ad.dispose().catchError((Object error) {}));
    super.dispose();
  }
}

enum RewardCenterMode { ad, daily, promotions, transactions, withdrawals }

class RewardCenterScreen extends StatefulWidget {
  const RewardCenterScreen({
    super.key,
    required this.service,
    required this.mode,
    this.policy,
    this.adFactory = createUnavailableRewardedAdAdapter,
    this.launcher = launchRewardLink,
    this.onConfiguration,
  });
  final ShareCoinService service;
  final RewardCenterMode mode;
  final OfferResourcePolicy? policy;
  final RewardedAdAdapter Function() adFactory;
  final RewardLinkLauncher launcher;
  final VoidCallback? onConfiguration;
  @override
  State<RewardCenterScreen> createState() => _RewardCenterScreenState();
}

class _RewardCenterScreenState extends State<RewardCenterScreen>
    with WidgetsBindingObserver {
  late final RewardCoordinator _rewards;
  late final OfferThumbnailCache _images;
  CoinFeedController<Promotion>? _promotions;
  CoinFeedController<ShareCoinTransaction>? _transactions;
  CoinFeedController<WithdrawalRequest>? _withdrawals;
  CoinData<DailyRewardConfiguration>? _daily;
  String? _error;
  int _generation = 0;
  String? _scope;
  String get _title => switch (widget.mode) {
    RewardCenterMode.ad => 'Rewarded Ads',
    RewardCenterMode.daily => 'Daily Reward',
    RewardCenterMode.promotions => 'Promotions',
    RewardCenterMode.transactions => 'Transactions',
    RewardCenterMode.withdrawals => 'Withdrawal History',
  };
  @override
  void initState() {
    super.initState();
    _rewards = RewardCoordinator(
      service: widget.service,
      ad: widget.adFactory(),
      policy: widget.policy,
      launcher: widget.launcher,
    );
    _images = OfferThumbnailCache(
      policy: _rewards.policy,
      canFetch: () => widget.service.connectivity.value.canRequestRewards,
    );
    if (widget.mode == RewardCenterMode.promotions) {
      _promotions = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getPromotions(query: query),
        id: (item) => item.campaignId,
      );
    }
    if (widget.mode == RewardCenterMode.transactions) {
      _transactions = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getTransactionHistory(query: query),
        id: (item) => item.transactionId,
      );
    }
    if (widget.mode == RewardCenterMode.withdrawals) {
      _withdrawals = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getWithdrawalHistory(query: query),
        id: (item) => item.withdrawalId,
      );
    }
    _scope = widget.service.accountKey;
    widget.service.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _accountChanged() {
    if (!mounted || _scope == widget.service.accountKey) return;
    _scope = widget.service.accountKey;
    _generation += 1;
    _images.clear();
    setState(() {
      _daily = null;
      _error = 'Account changed. Refresh this view.';
    });
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      if (_promotions != null) await _promotions!.refresh();
      if (_transactions != null) await _transactions!.refresh();
      if (_withdrawals != null) await _withdrawals!.refresh();
      if (widget.mode == RewardCenterMode.daily) {
        final data = await widget.service.getDailyRewardConfiguration();
        if (mounted && generation == _generation) {
          setState(() {
            _daily = data;
            _error = null;
          });
        }
      }
      if (widget.mode == RewardCenterMode.ad) {
        await widget.service.getServiceStatus();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is ShareCoinException
              ? error.message
              : 'Could not load this reward view.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      _rewards.suspend();
      _promotions?.suspend();
      _transactions?.suspend();
      _withdrawals?.suspend();
    } else if (state == AppLifecycleState.resumed) {
      _rewards.resume();
      _promotions?.resume();
      _transactions?.resume();
      _withdrawals?.resume();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    widget.service.removeListener(_accountChanged);
    _rewards.dispose();
    _images.dispose();
    _promotions?.dispose();
    _transactions?.dispose();
    _withdrawals?.dispose();
    super.dispose();
  }

  Future<bool> _consent(Uri uri) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open campaign?'),
            content: Text(
              'Continue to ${uri.host}? Tracking may be required. Clicking does not guarantee payment.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open provider'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('reward-center-screen'),
    appBar: AppBar(
      title: Text(_title),
      toolbarHeight: 70,
      actions: <Widget>[
        if (widget.onConfiguration != null)
          IconButton(
            tooltip: 'Configuration and previous view',
            onPressed: widget.onConfiguration,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        IconButton(
          tooltip: 'Refresh backend data',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: _body(),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_promotions != null) {
      return _feed(
        _promotions!,
        (promotion) => _promotionCard(promotion),
        header: _rewardPanel(),
      );
    }
    if (_transactions != null) {
      return _feed(
        _transactions!,
        (transaction) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.signedAmount,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '${transaction.source.name} · ${transaction.status.name}',
                  key: ValueKey(
                    'transaction-status-${transaction.transactionId}',
                  ),
                ),
                const SizedBox(height: 6),
                Text(transaction.description),
                Text(transaction.createdAt.toLocal().toString()),
                SelectableText(transaction.transactionId),
              ],
            ),
          ),
        ),
      );
    }
    if (_withdrawals != null) {
      return _feed(
        _withdrawals!,
        (request) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${request.requestedCoins} ShareCoin requested',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${request.method.name} · ${request.status.name}'),
                Text(request.maskedDestination),
                Text('Fee: ${request.rate.formatMinor(request.feeMinor)}'),
                Text(
                  'Final amount: ${request.rate.formatMinor(request.finalPayoutMinor)}',
                ),
                Text(request.updatedAt.toLocal().toString()),
                SelectableText(request.withdrawalId),
                if (request.rejectionReason != null)
                  Text(request.rejectionReason!),
                const Text(
                  'Status is reported by the backend, not a local payout action.',
                ),
              ],
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _header(
            widget.mode == RewardCenterMode.ad
                ? 'Watch. Verify. Refresh.'
                : 'Your daily check-in.',
          ),
          if (_error != null) _RewardNotice(_error!),
          if (widget.mode == RewardCenterMode.ad)
            const _RewardNotice(
              'A compliant rewarded-ad provider adapter and authenticated reward backend are required. This build does not simulate ad playback or cash earnings.',
            ),
          if (_daily != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Backend streak: Day ${_daily!.data.streakDay}'),
                    if (_daily!.cached)
                      const Text(
                        'Cached policy — fresh eligibility is checked before claiming.',
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (
                          var i = 0;
                          i < _daily!.data.dayRewards.length;
                          i += 1
                        )
                          Chip(
                            label: Text(
                              'Day ${i + 1}: ${_daily!.data.dayRewards[i]}',
                            ),
                          ),
                      ],
                    ),
                    const Text(
                      'Reward values and eligibility come from the backend, never from device date.',
                    ),
                  ],
                ),
              ),
            ),
          _rewardPanel(),
        ],
      ),
    );
  }

  Widget _header(String title) => Container(
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF164D3C),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'SHAREBONDHU · SHARECOIN',
          style: TextStyle(
            color: Color(0xFFD5F391),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Actions are not money. Only a validated backend ledger transaction confirms credit.',
          style: TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
        ),
      ],
    ),
  );

  Widget _rewardPanel() => ValueListenableBuilder<RewardViewState>(
    valueListenable: _rewards,
    builder: (context, state, child) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _phaseLabel(state.phase),
              key: const ValueKey('reward-phase'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(state.message, key: const ValueKey('reward-message')),
            if (state.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (state.session != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Backend usage before this session: ${state.session!.usedToday} / ${state.session!.dailyLimit}',
                ),
              ),
            if (state.cooldownRemaining > Duration.zero)
              Text('Cooldown: ${state.cooldownRemaining.inSeconds}s'),
            if (state.credited)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.transaction!.signedAmount,
                  key: const ValueKey('confirmed-reward-amount'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (widget.mode == RewardCenterMode.ad)
                  FilledButton(
                    key: const ValueKey('load-rewarded-ad'),
                    onPressed:
                        state.busy ||
                            _rewards.hasUnresolved ||
                            state.cooldownRemaining > Duration.zero
                        ? null
                        : _rewards.loadAd,
                    child: const Text('Load rewarded ad'),
                  ),
                if (widget.mode == RewardCenterMode.ad)
                  OutlinedButton(
                    key: const ValueKey('show-rewarded-ad'),
                    onPressed: _rewards.canShow ? _rewards.showAd : null,
                    child: const Text('Watch Ad'),
                  ),
                if (widget.mode == RewardCenterMode.daily)
                  FilledButton(
                    key: const ValueKey('claim-daily-reward'),
                    onPressed:
                        state.busy ||
                            _rewards.hasUnresolved ||
                            state.cooldownRemaining > Duration.zero
                        ? null
                        : _rewards.claimDaily,
                    child: const Text('Check and claim daily reward'),
                  ),
                OutlinedButton(
                  key: const ValueKey('refresh-reward-status'),
                  onPressed: _rewards.canCheckStatus
                      ? _rewards.refreshStatus
                      : null,
                  child: const Text('Check reward status'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _promotionCard(Promotion promotion) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              OfferThumbnail(cache: _images, uri: promotion.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  promotion.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(promotion.advertiser),
          Text(promotion.description),
          Text(
            '${promotion.rewardCoins} ShareCoin potential · ${promotion.status.name}',
          ),
          Text('Ends ${promotion.endsAt.toLocal()}'),
          SelectableText(promotion.campaignId),
          const SizedBox(height: 12),
          ValueListenableBuilder<RewardViewState>(
            valueListenable: _rewards,
            builder: (context, state, child) => FilledButton(
              key: ValueKey('start-promotion-${promotion.campaignId}'),
              onPressed: state.busy || _rewards.hasUnresolved
                  ? null
                  : () => _rewards.startPromotion(promotion, consent: _consent),
              child: Text(promotion.cta),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _feed<T>(
    CoinFeedController<T> controller,
    Widget Function(T) row, {
    Widget? header,
  }) => ValueListenableBuilder<CoinFeedState<T>>(
    valueListenable: controller,
    builder: (context, state, child) => RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _header(_title),
                  ?header,
                  if (state.cached)
                    const _RewardNotice(
                      'Cached records. Refresh before treating status as current.',
                    ),
                  if (state.error != null) _RewardNotice(state.error!),
                  if (state.items.isEmpty && !state.loading)
                    const Text('No records available from the backend.'),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => row(state.items[index]),
                childCount: state.items.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  if (state.loading) const LinearProgressIndicator(),
                  if (!state.loading && state.page?.hasNext == true)
                    OutlinedButton(
                      onPressed: controller.more,
                      child: Text(
                        state.windowFull ? 'Next record window' : 'Load more',
                      ),
                    ),
                  if (!state.loading && state.error != null)
                    TextButton(
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
                    ),
                  if (!state.loading &&
                      state.page != null &&
                      !state.page!.hasNext)
                    const Text('End of records'),
                  const SizedBox(height: 12),
                  const Text(
                    'Rejected, cancelled and reversed entries are not hidden. This client does not create payout success or credit money locally.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _phaseLabel(RewardPhase phase) => switch (phase) {
    RewardPhase.idle => 'Ready for an action',
    RewardPhase.loading => 'Loading / checking eligibility',
    RewardPhase.ready => 'Ad ready',
    RewardPhase.showing => 'Ad showing',
    RewardPhase.completed => 'Provider completion received',
    RewardPhase.skipped => 'Ad skipped',
    RewardPhase.failed => 'Action unavailable',
    RewardPhase.tracking => 'Provider tracking',
    RewardPhase.rewardPending => 'Reward Pending',
    RewardPhase.checkingCredit => 'Checking ledger credit',
    RewardPhase.rewardApproved => 'Reward Approved',
    RewardPhase.cooldown => 'Cooldown',
    RewardPhase.dailyLimit => 'Daily limit reached',
    RewardPhase.rejected => 'Reward Rejected',
    RewardPhase.reversed => 'Reward Reversed',
    RewardPhase.interrupted => 'Confirmation required',
  };
}

class _RewardNotice extends StatelessWidget {
  const _RewardNotice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(message),
  );
}
