import 'dart:async';
import 'dart:collection';

import '../config/backend_config.dart';
import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import 'auth_session_service.dart';
import 'connectivity_service.dart';
import 'share_coin_service.dart';

class AuthenticatedShareCoinBackend implements ShareCoinRewardBackend {
  AuthenticatedShareCoinBackend({
    required this.config,
    required this.auth,
    AuthenticatedApiClient? client,
  }) : client = client ?? AuthenticatedApiClient(config: config, auth: auth),
       _ownsClient = client == null {
    auth.addListener(_authChanged);
    _scopeKey = auth.scope?.key;
  }
  final BackendConfig config;
  final AuthSessionService auth;
  final AuthenticatedApiClient client;
  final bool _ownsClient;
  final StreamController<AccountScope?> _accounts =
      StreamController<AccountScope?>.broadcast();
  String? _scopeKey;
  bool _closed = false;
  @override
  bool get configured => !_closed && config.enabled && config.baseUrl != null;
  @override
  AccountScope? get scope => _closed ? null : auth.scope;
  @override
  Stream<AccountScope?> get accountChanges => _accounts.stream;
  void _authChanged() {
    if (_closed) return;
    final next = scope;
    if (_scopeKey != next?.key) {
      _scopeKey = next?.key;
      _accounts.add(next);
    }
  }

  void _owner(AccountScope owner) {
    if (!configured) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    if (scope == null) {
      throw const ShareCoinException(CoinErrorCode.unauthenticated);
    }
    if (scope!.key != owner.key) {
      throw const ShareCoinException(CoinErrorCode.accountChanged);
    }
  }

  @override
  Future<CoinServiceState> checkService() async {
    if (!configured) return CoinServiceState.unconfigured;
    try {
      final data = await client.request(
        'GET',
        config.healthPath,
        authenticated: false,
      );
      if (data['status'] != 'ok' ||
          data['apiVersion'] != config.apiVersion ||
          data.keys.any((key) => !{'status', 'apiVersion'}.contains(key))) {
        return CoinServiceState.limited;
      }
      return CoinServiceState.reachable;
    } catch (_) {
      return CoinServiceState.unreachable;
    }
  }

  @override
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> arguments,
  ) async {
    _owner(owner);
    if (!config.capabilities.contains(operation)) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    final write = <ShareCoinOperation>{
      ShareCoinOperation.submitReward,
      ShareCoinOperation.startOffer,
      ShareCoinOperation.requestWithdrawal,
    }.contains(operation);
    try {
      _validateArguments(operation, owner, arguments);
    } on CoinModelException {
      throw const ShareCoinException(CoinErrorCode.invalidRequest);
    }
    try {
      final route = _route(operation, arguments);
      final payload = await client.request(
        write ? 'POST' : 'GET',
        route.path,
        query: write ? const {} : route.query,
        body: write ? arguments : null,
        idempotencyKey: write
            ? coinId(arguments['idempotencyKey'], 'idempotencyKey')
            : null,
      );
      _owner(owner);
      return _validateEnvelope(
        payload,
        owner,
        (data) => _baseData(operation, data, owner, arguments),
      );
    } on ApiException catch (error) {
      throw _map(error);
    } on CoinModelException {
      throw ShareCoinException(
        write ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    } on BackendConfigurationException {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
  }

  @override
  Future<Map<String, dynamic>> executeRewardExtension(
    ShareCoinRewardOperation operation,
    AccountScope owner,
    Map<String, Object?> arguments,
  ) async {
    _owner(owner);
    if (!config.rewardCapabilities.contains(operation)) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    final write = operation == ShareCoinRewardOperation.prepareReward;
    try {
      final route = _extensionRoute(operation, arguments);
      final payload = await client.request(
        write ? 'POST' : 'GET',
        route.path,
        query: write ? const {} : route.query,
        body: write ? arguments : null,
        idempotencyKey: write
            ? coinId(arguments['idempotencyKey'], 'idempotencyKey')
            : null,
      );
      _owner(owner);
      return _validateEnvelope(payload, owner, (data) {
        switch (operation) {
          case ShareCoinRewardOperation.transaction:
            final value = ShareCoinTransaction.fromJson(data);
            _same(value.userId, owner.userId);
            _same(value.transactionId, arguments['transactionId']);
            return value.toJson();
          case ShareCoinRewardOperation.prepareReward:
          case ShareCoinRewardOperation.sessionStatus:
            final value = RewardSession.fromJson(data);
            _same(value.userId, owner.userId);
            if (write) {
              _same(value.source.name, arguments['source']);
              _same(value.targetId, arguments['targetId']);
              _same(value.requestKey, arguments['idempotencyKey']);
            } else {
              if (arguments['sessionId'] != null) {
                _same(value.sessionId, arguments['sessionId']);
              }
              if (arguments['requestKey'] != null) {
                _same(value.requestKey, arguments['requestKey']);
              }
            }
            return value.toJson();
          case ShareCoinRewardOperation.offerLaunch:
            final value = OfferLaunchGrant.fromJson(data);
            _same(value.userId, owner.userId);
            _same(value.startId, arguments['startId']);
            _same(value.platform.name, arguments['platform']);
            return value.toJson();
        }
      });
    } on ApiException catch (error) {
      throw _map(error);
    } on CoinModelException {
      throw ShareCoinException(
        write ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    } on BackendConfigurationException {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
  }

  void _same(Object? actual, Object? expected) {
    if (actual != expected) {
      throw const CoinModelException('response/request mismatch');
    }
  }

  void _keys(Map<String, Object?> value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const CoinModelException('unknown request field');
    }
  }

  static const _pageKeys = {
    'page',
    'pageSize',
    'cursor',
    'search',
    'category',
    'sort',
    'platform',
    'country',
  };
  void _validateArguments(
    ShareCoinOperation operation,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    if (<ShareCoinOperation>{
      ShareCoinOperation.transactions,
      ShareCoinOperation.rewardHistory,
      ShareCoinOperation.offers,
      ShareCoinOperation.promotions,
      ShareCoinOperation.withdrawals,
    }.contains(operation)) {
      _keys(
        args,
        operation == ShareCoinOperation.offers
            ? (Set<String>.from(_pageKeys)
                ..addAll({'minimumReward', 'maximumReward'}))
            : _pageKeys,
      );
      OfferQuery.fromJson(Map<String, dynamic>.from(args));
      if (args['minimumReward'] != null) {
        coinInt(args['minimumReward'], 'minimumReward');
      }
      if (args['maximumReward'] != null) {
        coinInt(args['maximumReward'], 'maximumReward');
      }
      if (args['minimumReward'] != null &&
          args['maximumReward'] != null &&
          (args['minimumReward'] as int) > (args['maximumReward'] as int)) {
        throw const CoinModelException('reward range');
      }
      return;
    }
    switch (operation) {
      case ShareCoinOperation.submitReward:
        final event = RewardEvent.fromJson(Map<String, dynamic>.from(args));
        _keys(args, event.toJson().keys.toSet());
        _same(event.userId, owner.userId);
        if (event.status != RewardEventStatus.created ||
            event.transactionId != null) {
          throw const CoinModelException('client cannot approve reward');
        }
      case ShareCoinOperation.requestWithdrawal:
        final intent = WithdrawalIntent.fromJson(
          Map<String, dynamic>.from(args),
        );
        _keys(args, intent.toJson().keys.toSet());
        _same(intent.userId, owner.userId);
      case ShareCoinOperation.startOffer:
        _keys(args, {'offerId', 'idempotencyKey'});
        coinId(args['offerId'], 'offerId');
        coinId(args['idempotencyKey'], 'idempotencyKey');
      case ShareCoinOperation.offer:
      case ShareCoinOperation.offerStatus:
        _keys(args, {'offerId'});
        coinId(args['offerId'], 'offerId');
      case ShareCoinOperation.rewardStatus:
        _keys(args, {'eventId'});
        coinId(args['eventId'], 'eventId');
      case ShareCoinOperation.withdrawalStatus:
        _keys(args, {'withdrawalId'});
        coinId(args['withdrawalId'], 'withdrawalId');
      case ShareCoinOperation.withdrawalByKey:
        _keys(args, {'idempotencyKey'});
        coinId(args['idempotencyKey'], 'idempotencyKey');
      default:
        _keys(args, {});
    }
  }

  ({String path, Map<String, Object?> query}) _route(
    ShareCoinOperation operation,
    Map<String, Object?> args,
  ) {
    final path = switch (operation) {
      ShareCoinOperation.currentUser => 'users/me',
      ShareCoinOperation.wallet => 'wallet',
      ShareCoinOperation.transactions => 'wallet/transactions',
      ShareCoinOperation.submitReward ||
      ShareCoinOperation.rewardHistory => 'rewards/events',
      ShareCoinOperation.rewardStatus => 'rewards/events/${args['eventId']}',
      ShareCoinOperation.offers => 'offers',
      ShareCoinOperation.offer => 'offers/${args['offerId']}',
      ShareCoinOperation.startOffer => 'offers/${args['offerId']}/start',
      ShareCoinOperation.offerStatus => 'offers/${args['offerId']}/status',
      ShareCoinOperation.promotions => 'promotions',
      ShareCoinOperation.withdrawalPolicy => 'withdrawals/policy',
      ShareCoinOperation.requestWithdrawal ||
      ShareCoinOperation.withdrawals => 'withdrawals',
      ShareCoinOperation.withdrawalStatus =>
        'withdrawals/${args['withdrawalId']}',
      ShareCoinOperation.withdrawalByKey =>
        'withdrawals/by-key/${args['idempotencyKey']}',
      ShareCoinOperation.referral => 'users/me/referral',
      ShareCoinOperation.adsConfiguration => config.adConfigurationPath,
      ShareCoinOperation.dailyConfiguration => 'rewards/daily/configuration',
    };
    final paged = <ShareCoinOperation>{
      ShareCoinOperation.transactions,
      ShareCoinOperation.rewardHistory,
      ShareCoinOperation.offers,
      ShareCoinOperation.promotions,
      ShareCoinOperation.withdrawals,
    }.contains(operation);
    return (path: path, query: paged ? args : const {});
  }

  ({String path, Map<String, Object?> query}) _extensionRoute(
    ShareCoinRewardOperation operation,
    Map<String, Object?> args,
  ) {
    switch (operation) {
      case ShareCoinRewardOperation.transaction:
        _keys(args, {'transactionId'});
        final id = coinId(args['transactionId'], 'transactionId');
        return (path: 'wallet/transactions/$id', query: const {});
      case ShareCoinRewardOperation.prepareReward:
        _keys(args, {'source', 'targetId', 'idempotencyKey'});
        final source = coinEnum(args['source'], CoinSource.values, 'source');
        if (!{
          CoinSource.adReward,
          CoinSource.dailyReward,
          CoinSource.promotionReward,
        }.contains(source)) {
          throw const CoinModelException('session source');
        }
        coinId(args['targetId'], 'targetId');
        coinId(args['idempotencyKey'], 'idempotencyKey');
        return (path: 'rewards/sessions', query: const {});
      case ShareCoinRewardOperation.sessionStatus:
        _keys(args, {'sessionId', 'requestKey'});
        if ((args['sessionId'] == null) == (args['requestKey'] == null)) {
          throw const CoinModelException('session reference');
        }
        if (args['sessionId'] != null) coinId(args['sessionId'], 'sessionId');
        if (args['requestKey'] != null) {
          coinId(args['requestKey'], 'requestKey');
        }
        return (path: 'rewards/sessions/status', query: args);
      case ShareCoinRewardOperation.offerLaunch:
        _keys(args, {'startId', 'platform'});
        final id = coinId(args['startId'], 'startId');
        coinEnum(args['platform'], OfferPlatform.values, 'platform');
        return (
          path: 'offers/starts/$id/launch',
          query: {'platform': args['platform']},
        );
    }
  }

  Map<String, dynamic> _validateEnvelope(
    Map<String, dynamic> envelope,
    AccountScope owner,
    Map<String, Object?> Function(Map<String, dynamic>) parse,
  ) {
    _keys(envelope, {'userId', 'serverTime', 'version', 'data'});
    _same(coinId(envelope['userId'], 'userId'), owner.userId);
    final time = coinTime(envelope['serverTime'], 'serverTime');
    final version = coinId(envelope['version'], 'version');
    final raw = coinObject(envelope['data'], 'data');
    final normalized = parse(raw);
    _strict(raw, normalized);
    return {
      'userId': owner.userId,
      'serverTime': time.toIso8601String(),
      'version': version,
      'data': normalized,
    };
  }

  void _strict(Object? raw, Object? normalized) {
    if (raw is Map && normalized is Map) {
      if (raw.keys.any((key) => !normalized.containsKey(key))) {
        throw const CoinModelException('unknown response field');
      }
      for (final key in raw.keys) {
        _strict(raw[key], normalized[key]);
      }
    } else if (raw is List && normalized is List) {
      if (raw.length != normalized.length) {
        throw const CoinModelException('response length');
      }
      for (var i = 0; i < raw.length; i += 1) {
        _strict(raw[i], normalized[i]);
      }
    }
  }

  Map<String, Object?> _page<T>(
    Map<String, dynamic> data,
    AccountScope owner,
    Map<String, Object?> args,
    T Function(Map<String, dynamic>) parse,
    String Function(T) id,
    Map<String, Object?> Function(T) serialize, {
    String Function(T)? user,
  }) {
    final page = CoinPage<T>.fromJson(data, parse, id);
    _same(page.info.page, args['page']);
    _same(page.info.pageSize, args['pageSize']);
    if (page.info.hasNext &&
        page.info.nextCursor != null &&
        page.info.nextCursor == args['cursor']) {
      throw const CoinModelException('cursor cycle');
    }
    if (user != null) {
      for (final item in page.items) {
        _same(user(item), owner.userId);
      }
    }
    return page.toJson(serialize);
  }

  Map<String, Object?> _baseData(
    ShareCoinOperation operation,
    Map<String, dynamic> data,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    switch (operation) {
      case ShareCoinOperation.currentUser:
        final user = ShareCoinUser.fromJson(data);
        _same(user.userId, owner.userId);
        return user.toJson();
      case ShareCoinOperation.wallet:
        final wallet = ShareCoinBalance.fromJson(data);
        _same(wallet.userId, owner.userId);
        return wallet.toJson();
      case ShareCoinOperation.transactions:
        return _page(
          data,
          owner,
          args,
          ShareCoinTransaction.fromJson,
          (value) => value.transactionId,
          (value) => value.toJson(),
          user: (value) => value.userId,
        );
      case ShareCoinOperation.rewardHistory:
        return _page(
          data,
          owner,
          args,
          RewardEvent.fromJson,
          (value) => value.eventId,
          (value) => value.toJson(),
          user: (value) => value.userId,
        );
      case ShareCoinOperation.submitReward:
      case ShareCoinOperation.rewardStatus:
        final event = RewardEvent.fromJson(data);
        _same(event.userId, owner.userId);
        _same(event.eventId, args['eventId']);
        if (operation == ShareCoinOperation.submitReward) {
          final expected = RewardEvent.fromJson(
            Map<String, dynamic>.from(args),
          );
          _same(event.actionKey, expected.actionKey);
          _same(event.idempotencyKey, expected.idempotencyKey);
          _same(event.requestedCoins, expected.requestedCoins);
          if (event.status == RewardEventStatus.created ||
              event.status == RewardEventStatus.submitted) {
            throw const CoinModelException('unconfirmed reward response');
          }
        }
        return event.toJson();
      case ShareCoinOperation.offers:
        return _page(
          data,
          owner,
          args,
          Offer.fromJson,
          (value) => value.offerId,
          (value) => value.toJson(),
        );
      case ShareCoinOperation.offer:
      case ShareCoinOperation.offerStatus:
        final offer = Offer.fromJson(data);
        _same(offer.offerId, args['offerId']);
        return offer.toJson();
      case ShareCoinOperation.startOffer:
        final start = OfferStart.fromJson(data);
        _same(start.userId, owner.userId);
        _same(start.offerId, args['offerId']);
        _same(start.idempotencyKey, args['idempotencyKey']);
        return start.toJson();
      case ShareCoinOperation.promotions:
        return _page(
          data,
          owner,
          args,
          Promotion.fromJson,
          (value) => value.campaignId,
          (value) => value.toJson(),
        );
      case ShareCoinOperation.withdrawalPolicy:
        final policy = WithdrawalPolicy.fromJson(data);
        _same(policy.userId, owner.userId);
        return policy.toJson();
      case ShareCoinOperation.withdrawals:
        return _page(
          data,
          owner,
          args,
          WithdrawalRequest.fromJson,
          (value) => value.withdrawalId,
          (value) => value.toJson(),
          user: (value) => value.userId,
        );
      case ShareCoinOperation.requestWithdrawal:
      case ShareCoinOperation.withdrawalStatus:
      case ShareCoinOperation.withdrawalByKey:
        final request = WithdrawalRequest.fromJson(data);
        _same(request.userId, owner.userId);
        if (operation == ShareCoinOperation.withdrawalStatus) {
          _same(request.withdrawalId, args['withdrawalId']);
        }
        if (operation != ShareCoinOperation.withdrawalStatus) {
          _same(request.idempotencyKey, args['idempotencyKey']);
        }
        if (operation == ShareCoinOperation.requestWithdrawal) {
          _same(request.requestedCoins, args['coins']);
          _same(request.method.name, args['method']);
          _same(request.feeMinor, args['expectedFeeMinor']);
          _same(request.finalPayoutMinor, args['expectedFinalMinor']);
        }
        return request.toJson();
      case ShareCoinOperation.referral:
        final referral = ReferralSummary.fromJson(data);
        _same(referral.userId, owner.userId);
        return referral.toJson();
      case ShareCoinOperation.adsConfiguration:
        return AdConfiguration.fromJson(data).toJson();
      case ShareCoinOperation.dailyConfiguration:
        return DailyRewardConfiguration.fromJson(data).toJson();
    }
  }

  ShareCoinException _map(ApiException error) {
    if (error.uncertain) {
      return const ShareCoinException(CoinErrorCode.uncertain);
    }
    if (error.serverCode != null) {
      return ShareCoinException.fromServerCode(error.serverCode!);
    }
    return ShareCoinException(switch (error.code) {
      ApiErrorCode.configuration => CoinErrorCode.notConfigured,
      ApiErrorCode.unauthenticated => CoinErrorCode.unauthenticated,
      ApiErrorCode.restricted => CoinErrorCode.restricted,
      ApiErrorCode.stale ||
      ApiErrorCode.cancelled => CoinErrorCode.accountChanged,
      ApiErrorCode.malformed => CoinErrorCode.malformed,
      ApiErrorCode.notFound => CoinErrorCode.notFound,
      ApiErrorCode.conflict => CoinErrorCode.conflict,
      ApiErrorCode.rateLimited => CoinErrorCode.rateLimited,
      ApiErrorCode.invalidRequest => CoinErrorCode.invalidRequest,
      ApiErrorCode.network ||
      ApiErrorCode.timeout ||
      ApiErrorCode.server => CoinErrorCode.unavailable,
    });
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    auth.removeListener(_authChanged);
    unawaited(_accounts.close());
    if (_ownsClient) client.dispose();
  }
}

class RewardReconciliation {
  const RewardReconciliation({
    required this.accountKey,
    required this.state,
    required this.reference,
    this.event,
    this.transaction,
    this.wallet,
    required this.message,
  });
  final String accountKey, reference, message;
  final RewardCreditState state;
  final RewardEvent? event;
  final ShareCoinTransaction? transaction;
  final CoinData<ShareCoinBalance>? wallet;
  bool get reconciled =>
      state == RewardCreditState.credited &&
      transaction?.status == CoinTransactionStatus.completed &&
      wallet != null &&
      !wallet!.cached;
}

class WithdrawalReconciliation {
  const WithdrawalReconciliation({
    required this.request,
    required this.wallet,
    required this.transactions,
    required this.accountKey,
  });
  final WithdrawalRequest request;
  final CoinData<ShareCoinBalance> wallet;
  final CoinPage<ShareCoinTransaction> transactions;
  final String accountKey;
}

// An account-scoped synchronization coordinator around the EXISTING wallet
// service. It never calculates a wallet delta or creates a financial record.
class ShareCoinReconciler {
  ShareCoinReconciler({required this.service, this.limit = 128}) {
    if (limit < 1 || limit > 1024) {
      throw ArgumentError('Invalid reconciliation limit.');
    }
    _scope = service.accountKey;
    service.addListener(_changed);
  }
  final ShareCoinService service;
  final int limit;
  final LinkedHashMap<String, RewardReconciliation> _results = LinkedHashMap();
  final Map<String, Future<Object>> _pending = {};
  String? _scope;
  int _generation = 0;
  bool _closed = false;
  void _changed() {
    if (_closed || _scope == service.accountKey) return;
    _scope = service.accountKey;
    _generation += 1;
    _results.clear();
    _pending.clear();
  }

  bool isRewardReconciled(String eventId) =>
      !_closed &&
      _scope == service.accountKey &&
      (_results['event:$eventId']?.reconciled ?? false);
  void _current(String key, int generation) {
    if (_closed || generation != _generation || key != service.accountKey) {
      throw const ShareCoinException(CoinErrorCode.accountChanged);
    }
  }

  Future<T> _run<T extends Object>(
    String key,
    Future<T> Function(String, int) action,
  ) {
    if (_closed) {
      return Future.error(const ShareCoinException(CoinErrorCode.disposed));
    }
    final scope = service.accountKey;
    if (scope == null) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.unauthenticated),
      );
    }
    _changed();
    final existing = _pending[key];
    if (existing != null) return existing.then((value) => value as T);
    final generation = _generation;
    final completion = Completer<T>();
    _pending[key] = completion.future;
    Future<void>(() async {
      try {
        final value = await action(scope, generation);
        _current(scope, generation);
        completion.complete(value);
      } catch (error) {
        completion.completeError(error);
      } finally {
        if (identical(_pending[key], completion.future)) _pending.remove(key);
      }
    });
    return completion.future;
  }

  Future<RewardReconciliation> reconcileReward(String eventId) =>
      _run('event:${coinId(eventId, 'eventId')}', (scope, generation) async {
        final response = await service.getRewardEventStatus(eventId);
        _current(scope, generation);
        final event = response.data;
        if (response.accountKey != scope) {
          throw const ShareCoinException(CoinErrorCode.accountChanged);
        }
        final RewardReconciliation result;
        if (event.status == RewardEventStatus.rejected ||
            event.status == RewardEventStatus.cancelled) {
          result = RewardReconciliation(
            accountKey: scope,
            reference: eventId,
            state: RewardCreditState.rejected,
            event: event,
            message: 'The backend rejected or cancelled this reward.',
          );
        } else if (event.status != RewardEventStatus.approved ||
            event.transactionId == null) {
          result = RewardReconciliation(
            accountKey: scope,
            reference: eventId,
            state: RewardCreditState.pending,
            event: event,
            message: 'Reward pending backend verification.',
          );
        } else {
          result = await _ledger(
            scope,
            generation,
            eventId,
            event.transactionId!,
            event.source,
            event.targetId,
            event: event,
          );
        }
        _remember('event:$eventId', result);
        return result;
      });

  Future<RewardReconciliation> reconcileOffer(String offerId) =>
      _run('offer:${coinId(offerId, 'offerId')}', (scope, generation) async {
        final response = await service.getOfferStatus(
          offerId,
          allowCached: false,
        );
        _current(scope, generation);
        final offer = response.data;
        if (response.accountKey != scope) {
          throw const ShareCoinException(CoinErrorCode.accountChanged);
        }
        final RewardReconciliation result;
        if (offer.status == OfferStatus.completed &&
            offer.rewardTransactionId != null) {
          result = await _ledger(
            scope,
            generation,
            offerId,
            offer.rewardTransactionId!,
            CoinSource.offerReward,
            offerId,
          );
        } else {
          result = RewardReconciliation(
            accountKey: scope,
            reference: offerId,
            state:
                offer.status == OfferStatus.rejected ||
                    offer.status == OfferStatus.expired
                ? RewardCreditState.rejected
                : RewardCreditState.pending,
            message: 'The offer has no completed backend credit transaction.',
          );
        }
        _remember('offer:$offerId', result);
        return result;
      });

  Future<RewardReconciliation> _ledger(
    String scope,
    int generation,
    String reference,
    String transactionId,
    CoinSource source,
    String targetId, {
    RewardEvent? event,
  }) async {
    final data = await service.getTransaction(
      transactionId,
      allowCached: false,
    );
    _current(scope, generation);
    final transaction = data.data;
    if (data.accountKey != scope ||
        transaction.transactionId != transactionId ||
        transaction.source != source ||
        transaction.referenceId != targetId ||
        transaction.direction != CoinDirection.credit) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    final state = switch (transaction.status) {
      CoinTransactionStatus.completed => RewardCreditState.credited,
      CoinTransactionStatus.reversed => RewardCreditState.reversed,
      CoinTransactionStatus.rejected ||
      CoinTransactionStatus.cancelled => RewardCreditState.rejected,
      CoinTransactionStatus.approved ||
      CoinTransactionStatus.pending => RewardCreditState.pending,
    };
    CoinData<ShareCoinBalance>? wallet;
    if (state == RewardCreditState.credited ||
        state == RewardCreditState.reversed ||
        state == RewardCreditState.rejected) {
      try {
        wallet = await service.getCurrentWallet(allowCached: false);
        _current(scope, generation);
      } on ShareCoinException catch (error) {
        _current(scope, generation);
        if (error.code == CoinErrorCode.accountChanged ||
            error.code == CoinErrorCode.unauthenticated) {
          rethrow;
        }
        return RewardReconciliation(
          accountKey: scope,
          reference: reference,
          state: state == RewardCreditState.credited
              ? RewardCreditState.unconfirmed
              : state,
          event: event,
          transaction: transaction,
          message: 'Ledger status received; a fresh wallet could not be synchronized. No local balance is changed.',
        );
      }
      if (wallet.accountKey != scope ||
          wallet.cached ||
          wallet.data.userId != transaction.userId) {
        throw const ShareCoinException(CoinErrorCode.accountChanged);
      }
    }
    return RewardReconciliation(
      accountKey: scope,
      reference: reference,
      state: state,
      event: event,
      transaction: transaction,
      wallet: wallet,
      message: state == RewardCreditState.credited
          ? 'Backend credit and fresh wallet reconciled.'
          : 'Backend ledger status: ${transaction.status.name}.',
    );
  }

  void _remember(String key, RewardReconciliation result) {
    if (_closed || result.accountKey != service.accountKey) return;
    _results.remove(key);
    _results[key] = result;
    while (_results.length > limit) {
      _results.remove(_results.keys.first);
    }
  }

  Future<WithdrawalReconciliation> reconcileWithdrawal({
    String? withdrawalId,
    String? idempotencyKey,
  }) {
    if ((withdrawalId == null) == (idempotencyKey == null)) {
      throw const CoinModelException('one withdrawal reference required');
    }
    return _run('withdrawal:${withdrawalId ?? idempotencyKey}', (
      scope,
      generation,
    ) async {
      final response = withdrawalId != null
          ? await service.getWithdrawalStatus(withdrawalId)
          : await service.getWithdrawalByKey(idempotencyKey!);
      _current(scope, generation);
      final transactions = await service.getTransactionHistory(
        query: OfferQuery(pageSize: 20),
        allowCached: false,
      );
      _current(scope, generation);
      final wallet = await service.getCurrentWallet(allowCached: false);
      _current(scope, generation);
      if (response.accountKey != scope ||
          transactions.accountKey != scope ||
          wallet.accountKey != scope ||
          wallet.cached) {
        throw const ShareCoinException(CoinErrorCode.accountChanged);
      }
      return WithdrawalReconciliation(
        request: response.data,
        wallet: wallet,
        transactions: transactions.data,
        accountKey: scope,
      );
    });
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    service.removeListener(_changed);
    _results.clear();
    _pending.clear();
  }
}
