import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../models/offerwall_models.dart';
import 'connectivity_service.dart';

enum ShareCoinOperation {
  currentUser,
  wallet,
  transactions,
  submitReward,
  rewardStatus,
  rewardHistory,
  offers,
  offer,
  startOffer,
  offerStatus,
  promotions,
  withdrawalPolicy,
  requestWithdrawal,
  withdrawals,
  withdrawalStatus,
  withdrawalByKey,
  referral,
  adsConfiguration,
  dailyConfiguration,
}

enum CoinErrorCode {
  notConfigured,
  unauthenticated,
  restricted,
  offline,
  unavailable,
  malformed,
  accountChanged,
  invalidRequest,
  conflict,
  minimum,
  insufficientBalance,
  payoutUnavailable,
  policyChanged,
  notFound,
  rateLimited,
  uncertain,
  disposed,
}

enum CoinDataOrigin { server, cache }

class ShareCoinException implements Exception {
  const ShareCoinException(this.code);
  final CoinErrorCode code;
  bool get outcomeUncertain => code == CoinErrorCode.uncertain;
  String get message => switch (code) {
    CoinErrorCode.notConfigured => 'ShareCoin backend is not configured. No real balance or payout is available.',
    CoinErrorCode.unauthenticated =>
      'Account setup and backend authentication are required.',
    CoinErrorCode.restricted =>
      'This account cannot request rewards or withdrawals.',
    CoinErrorCode.offline =>
      'Reward services are offline. Local file sharing is separate.',
    CoinErrorCode.unavailable =>
      'The ShareCoin service is unavailable. Try a status refresh.',
    CoinErrorCode.malformed => 'The backend response could not be validated.',
    CoinErrorCode.accountChanged =>
      'The account changed. Refresh before continuing.',
    CoinErrorCode.invalidRequest =>
      'The request is invalid. Review the amount and request details.',
    CoinErrorCode.conflict => 'This action is already pending or the request key was reused with different data.',
    CoinErrorCode.minimum =>
      'The amount is below the backend withdrawal minimum.',
    CoinErrorCode.insufficientBalance =>
      'The backend wallet does not have enough available coins.',
    CoinErrorCode.payoutUnavailable =>
      'This payout method or saved destination is not connected.',
    CoinErrorCode.policyChanged =>
      'The payout policy changed. Refresh and review the new quote.',
    CoinErrorCode.notFound => 'The backend did not return this record.',
    CoinErrorCode.rateLimited => 'Too many requests. Wait before trying again.',
    CoinErrorCode.uncertain => 'Confirmation was lost. Check the request status instead of creating another request.',
    CoinErrorCode.disposed => 'This ShareCoin session is closed.',
  };
  factory ShareCoinException.fromServerCode(String code) =>
      ShareCoinException(switch (code) {
        'unauthenticated' => CoinErrorCode.unauthenticated,
        'restricted' => CoinErrorCode.restricted,
        'conflict' => CoinErrorCode.conflict,
        'below_minimum' => CoinErrorCode.minimum,
        'insufficient_balance' => CoinErrorCode.insufficientBalance,
        'payout_unavailable' => CoinErrorCode.payoutUnavailable,
        'policy_changed' => CoinErrorCode.policyChanged,
        'not_found' => CoinErrorCode.notFound,
        'rate_limited' => CoinErrorCode.rateLimited,
        'invalid_request' ||
        'invalid_provider_signature' ||
        'expired_offer' => CoinErrorCode.invalidRequest,
        'cooldown' || 'daily_limit' => CoinErrorCode.rateLimited,
        'duplicate_event' => CoinErrorCode.conflict,
        _ => CoinErrorCode.unavailable,
      });
  @override
  String toString() => message;
}

class CoinData<T> {
  const CoinData({
    required this.data,
    required this.origin,
    required this.serverTime,
    required this.version,
    required this.accountKey,
  });
  final T data;
  final CoinDataOrigin origin;
  final DateTime serverTime;
  final String version, accountKey;
  bool get cached => origin == CoinDataOrigin.cache;
  CoinData<T> asCached() => CoinData<T>(
    data: data,
    origin: CoinDataOrigin.cache,
    serverTime: serverTime,
    version: version,
    accountKey: accountKey,
  );
}

// A real adapter must authenticate every operation, bound response sizes, use
// verified HTTPS, and enforce the documented backend ledger/idempotency rules.
// No URL, credential store, authentication provider or remote server is invented.
abstract interface class ShareCoinBackend {
  bool get configured;
  AccountScope? get scope;
  Stream<AccountScope?> get accountChanges;
  Future<CoinServiceState> checkService();
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  );
}

// Optional capability on the SAME authenticated backend, not another wallet.
enum ShareCoinRewardOperation {
  transaction,
  prepareReward,
  sessionStatus,
  offerLaunch,
}

abstract interface class ShareCoinRewardBackend implements ShareCoinBackend {
  Future<Map<String, dynamic>> executeRewardExtension(
    ShareCoinRewardOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  );
}

class UnconfiguredShareCoinBackend implements ShareCoinBackend {
  const UnconfiguredShareCoinBackend();
  @override
  bool get configured => false;
  @override
  AccountScope? get scope => null;
  @override
  Stream<AccountScope?> get accountChanges =>
      const Stream<AccountScope?>.empty();
  @override
  Future<CoinServiceState> checkService() async =>
      CoinServiceState.unconfigured;
  @override
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  ) => Future<Map<String, dynamic>>.error(
    const ShareCoinException(CoinErrorCode.notConfigured),
  );
}

class _CoinMutation {
  _CoinMutation(this.fingerprint, this.key, this.future);
  final String fingerprint, key;
  final Future<Object> future;
  final Set<String> aliases = <String>{};
  bool settled = false;
  bool uncertain = false;
}

String newCoinRequestId() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ShareCoinService extends ChangeNotifier {
  ShareCoinService({
    ShareCoinBackend? backend,
    ConnectivityService? connectivity,
    this.requestTimeout = const Duration(seconds: 15),
    this.cachePages = 24,
    this.mutationLimit = 256,
  }) {
    if (requestTimeout <= Duration.zero ||
        cachePages < 1 ||
        mutationLimit < 1) {
      throw ArgumentError('Service limits must be positive.');
    }
    _backend = backend ?? const UnconfiguredShareCoinBackend();
    _ownsConnectivity = connectivity == null;
    this.connectivity =
        connectivity ??
        ConnectivityService(
          serviceProbe: _backend.configured ? _backend.checkService : null,
        );
    _accountKey = _backend.scope?.key;
    _accountSubscription = _backend.accountChanges.listen(
      (_) => _synchronizeAccount(),
      onError: (Object error, StackTrace stack) {
        _clearAccountState();
      },
    );
  }
  late final ShareCoinBackend _backend;
  late final ConnectivityService connectivity;
  late final bool _ownsConnectivity;
  late final StreamSubscription<AccountScope?> _accountSubscription;
  final Duration requestTimeout;
  final int cachePages, mutationLimit;
  final LinkedHashMap<String, CoinData<Object>> _cache =
      LinkedHashMap<String, CoinData<Object>>();
  final Map<String, Future<Object>> _reads = <String, Future<Object>>{};
  final LinkedHashMap<String, _CoinMutation> _mutations =
      LinkedHashMap<String, _CoinMutation>();
  final Map<String, String> _aliases = <String, String>{};
  final Map<String, WithdrawalRequest> _withdrawalStates =
      <String, WithdrawalRequest>{};
  String? _accountKey;
  String? _withdrawalLock;
  String? _activeWithdrawalId;
  int _generation = 0;
  int _walletGeneration = 0;
  bool _closed = false;
  bool _suspended = false;

  bool get backendConfigured => _backend.configured;
  String? get accountKey => _backend.scope?.key;
  bool get hasAccount => _backend.scope != null;
  bool get hasPendingWithdrawal =>
      _withdrawalLock != null || _activeWithdrawalId != null;
  CoinData<ShareCoinBalance>? get cachedWallet {
    final scope = _backend.scope;
    if (scope == null || scope.key != _accountKey) return null;
    return (_cache[_key(scope, ShareCoinOperation.wallet, const {})]
            as CoinData<ShareCoinBalance>?)
        ?.asCached();
  }

  void _synchronizeAccount() {
    if (_closed) return;
    final key = _backend.scope?.key;
    if (key != _accountKey) {
      _clearAccountState(nextKey: key);
    }
  }

  void _clearAccountState({String? nextKey}) {
    if (_closed) return;
    _generation += 1;
    _walletGeneration += 1;
    _accountKey = nextKey;
    _cache.clear();
    _reads.clear();
    _mutations.clear();
    _aliases.clear();
    _withdrawalStates.clear();
    _withdrawalLock = null;
    _activeWithdrawalId = null;
    notifyListeners();
  }

  AccountScope _scope() {
    if (_closed) throw const ShareCoinException(CoinErrorCode.disposed);
    if (!_backend.configured) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    _synchronizeAccount();
    final scope = _backend.scope;
    if (scope == null) {
      throw const ShareCoinException(CoinErrorCode.unauthenticated);
    }
    return scope;
  }

  void _current(AccountScope scope, int generation) {
    if (_closed) throw const ShareCoinException(CoinErrorCode.disposed);
    if (generation != _generation || _backend.scope?.key != scope.key) {
      throw const ShareCoinException(CoinErrorCode.accountChanged);
    }
  }

  Future<void> _online(AccountScope scope, int generation) async {
    if (_suspended) throw const ShareCoinException(CoinErrorCode.offline);
    await connectivity.refresh();
    _current(scope, generation);
    if (_suspended || !connectivity.value.canRequestRewards) {
      throw ShareCoinException(
        connectivity.value.internet == InternetState.offline
            ? CoinErrorCode.offline
            : CoinErrorCode.unavailable,
      );
    }
  }

  String _key(
    AccountScope scope,
    ShareCoinOperation operation,
    Map<String, Object?> args,
  ) => '${scope.key}|${operation.name}|${jsonEncode(_canonical(args))}';
  Object? _canonical(Object? input) {
    if (input is Map) {
      final keys = input.keys.cast<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(input[key]),
      };
    }
    if (input is List) return input.map(_canonical).toList();
    return input;
  }

  Future<CoinData<T>> _execute<T extends Object>(
    AccountScope scope,
    int generation,
    ShareCoinOperation operation,
    Map<String, Object?> arguments,
    T Function(Map<String, dynamic>, AccountScope) parse, {
    bool mutation = false,
    Future<Map<String, dynamic>> Function()? request,
  }) async {
    try {
      _current(scope, generation);
      if (mutation && _suspended) {
        throw const ShareCoinException(CoinErrorCode.offline);
      }
      final response = request != null
          ? request()
          : _backend.execute(
              operation,
              scope,
              Map<String, Object?>.unmodifiable(arguments),
            );
      final envelope = await response.timeout(requestTimeout);
      _current(scope, generation);
      if (coinId(envelope['userId'], 'userId') != scope.userId) {
        throw const CoinModelException('response account');
      }
      final serverTime = coinTime(envelope['serverTime'], 'serverTime');
      final version = coinId(envelope['version'], 'version');
      final value = parse(coinObject(envelope['data'], 'data'), scope);
      return CoinData<T>(
        data: value,
        origin: CoinDataOrigin.server,
        serverTime: serverTime,
        version: version,
        accountKey: scope.key,
      );
    } on ShareCoinException catch (error) {
      if (mutation &&
          <CoinErrorCode>{
            CoinErrorCode.offline,
            CoinErrorCode.unavailable,
            CoinErrorCode.malformed,
          }.contains(error.code)) {
        throw const ShareCoinException(CoinErrorCode.uncertain);
      }
      rethrow;
    } on CoinModelException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    } on SocketException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } on HandshakeException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } on TimeoutException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } catch (_) {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    }
  }

  T _owned<T>(T object, String userId, AccountScope scope) {
    if (userId != scope.userId) {
      throw const CoinModelException('record account');
    }
    return object;
  }

  Future<CoinData<T>> _read<T extends Object>(
    ShareCoinOperation operation,
    T Function(Map<String, dynamic>, AccountScope) parse, {
    Map<String, Object?> arguments = const {},
    bool allowCached = true,
    Future<Map<String, dynamic>> Function(AccountScope, Map<String, Object?>)?
    request,
  }) {
    try {
      final scope = _scope();
      final generation = _generation;
      final walletGeneration = _walletGeneration;
      final key = _key(scope, operation, arguments);
      final readKey = '$key|${allowCached ? 'cache-ok' : 'server-only'}';
      final current = _reads[readKey];
      if (current != null) return current.then((value) => value as CoinData<T>);
      final completion = Completer<CoinData<T>>();
      _reads[readKey] = completion.future;
      Future<void>(() async {
        try {
          await _online(scope, generation);
          final data = await _execute(
            scope,
            generation,
            operation,
            arguments,
            parse,
            request: request == null ? null : () => request(scope, arguments),
          );
          _current(scope, generation);
          if (operation == ShareCoinOperation.wallet &&
              walletGeneration != _walletGeneration) {
            throw const ShareCoinException(CoinErrorCode.unavailable);
          }
          final old = _cache[key];
          if (old != null && data.serverTime.isBefore(old.serverTime)) {
            throw const ShareCoinException(CoinErrorCode.malformed);
          }
          if (data.data is CoinPage) {
            final page = data.data as CoinPage;
            if (page.info.page != arguments['page'] ||
                page.info.pageSize != arguments['pageSize'] ||
                (page.info.hasNext &&
                    page.info.nextCursor != null &&
                    page.info.nextCursor == arguments['cursor'])) {
              throw const ShareCoinException(CoinErrorCode.malformed);
            }
          }
          _cache.remove(key);
          _cache[key] = data;
          while (_cache.length > cachePages) {
            _cache.remove(_cache.keys.first);
          }
          completion.complete(data);
        } catch (error) {
          final cached = _cache[key];
          final canCache =
              error is ShareCoinException &&
              <CoinErrorCode>{
                CoinErrorCode.offline,
                CoinErrorCode.unavailable,
              }.contains(error.code);
          if (allowCached &&
              canCache &&
              cached != null &&
              !_closed &&
              _backend.scope?.key == scope.key &&
              generation == _generation) {
            completion.complete((cached as CoinData<T>).asCached());
          } else {
            completion.completeError(error);
          }
        } finally {
          if (identical(_reads[readKey], completion.future)) {
            _reads.remove(readKey);
          }
        }
      });
      return completion.future;
    } catch (error) {
      return Future<CoinData<T>>.error(error);
    }
  }

  Future<CoinData<ShareCoinUser>> getCurrentUser({bool allowCached = true}) =>
      _read(ShareCoinOperation.currentUser, (j, scope) {
        final user = ShareCoinUser.fromJson(j);
        return _owned(user, user.userId, scope);
      }, allowCached: allowCached);

  Future<CoinData<ShareCoinBalance>> getCurrentWallet({
    bool allowCached = true,
  }) => _read(ShareCoinOperation.wallet, (j, scope) {
    final wallet = ShareCoinBalance.fromJson(j);
    return _owned(wallet, wallet.userId, scope);
  }, allowCached: allowCached);

  Future<CoinData<CoinPage<ShareCoinTransaction>>> getTransactionHistory({
    OfferQuery? query,
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.transactions,
    (j, scope) {
      final page = CoinPage<ShareCoinTransaction>.fromJson(
        j,
        ShareCoinTransaction.fromJson,
        (value) => value.transactionId,
      );
      for (final item in page.items) {
        _owned(item, item.userId, scope);
      }
      return page;
    },
    arguments: (query ?? OfferQuery()).toJson(),
    allowCached: allowCached,
  );

  Future<CoinData<CoinPage<RewardEvent>>> getRewardHistory({
    OfferQuery? query,
  }) => _read(ShareCoinOperation.rewardHistory, (j, scope) {
    final page = CoinPage<RewardEvent>.fromJson(
      j,
      RewardEvent.fromJson,
      (value) => value.eventId,
    );
    for (final item in page.items) {
      _owned(item, item.userId, scope);
    }
    return page;
  }, arguments: (query ?? OfferQuery()).toJson());

  Future<CoinData<CoinPage<Offer>>> getOffers({
    OfferQuery? query,
    bool allowCached = true,
    int? minimumReward,
    int? maximumReward,
  }) => _read(
    ShareCoinOperation.offers,
    (j, scope) =>
        CoinPage<Offer>.fromJson(j, Offer.fromJson, (value) => value.offerId),
    arguments: _offerArguments(
      query ?? OfferQuery(),
      minimumReward,
      maximumReward,
    ),
    allowCached: allowCached,
  );

  Future<CoinData<Offer>> getOfferStatus(
    String offerId, {
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.offerStatus,
    (j, scope) {
      final offer = Offer.fromJson(j);
      if (offer.offerId != offerId) throw const CoinModelException('offerId');
      return offer;
    },
    arguments: {'offerId': coinId(offerId, 'offerId')},
    allowCached: allowCached,
  );

  Future<CoinData<CoinPage<Promotion>>> getPromotions({OfferQuery? query}) =>
      _read(
        ShareCoinOperation.promotions,
        (j, scope) => CoinPage<Promotion>.fromJson(
          j,
          Promotion.fromJson,
          (value) => value.campaignId,
        ),
        arguments: (query ?? OfferQuery()).toJson(),
      );

  Future<CoinData<AdConfiguration>> getAdConfiguration({
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.adsConfiguration,
    (j, scope) => AdConfiguration.fromJson(j),
    allowCached: allowCached,
  );
  Future<CoinData<DailyRewardConfiguration>> getDailyRewardConfiguration({
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.dailyConfiguration,
    (j, scope) => DailyRewardConfiguration.fromJson(j),
    allowCached: allowCached,
  );
  Future<CoinData<ReferralSummary>> getReferral() =>
      _read(ShareCoinOperation.referral, (j, scope) {
        final referral = ReferralSummary.fromJson(j);
        return _owned(referral, referral.userId, scope);
      });
  Future<CoinServiceState> getServiceStatus() async =>
      (await connectivity.refresh()).shareCoin;

  Future<CoinData<WithdrawalPolicy>> getWithdrawalPolicy({
    bool allowCached = true,
  }) => _read(ShareCoinOperation.withdrawalPolicy, (j, scope) {
    final policy = WithdrawalPolicy.fromJson(j);
    return _owned(policy, policy.userId, scope);
  }, allowCached: allowCached);

  Future<CoinData<CoinPage<WithdrawalRequest>>> getWithdrawalHistory({
    OfferQuery? query,
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.withdrawals,
    (j, scope) {
      final page = CoinPage<WithdrawalRequest>.fromJson(
        j,
        WithdrawalRequest.fromJson,
        (value) => value.withdrawalId,
      );
      for (final item in page.items) {
        _owned(item, item.userId, scope);
      }
      return page;
    },
    arguments: (query ?? OfferQuery()).toJson(),
    allowCached: allowCached,
  );

  Future<void> _activeAccount(AccountScope scope, int generation) async {
    final user = await getCurrentUser(allowCached: false);
    _current(scope, generation);
    if (!user.data.mayRequestRewards) {
      throw const ShareCoinException(CoinErrorCode.restricted);
    }
  }

  Future<CoinData<T>> _mutate<T extends Object>(
    String logicalKey,
    String fingerprint,
    List<String> aliases,
    String idempotencyKey,
    Future<CoinData<T>> Function(AccountScope, int, void Function())
    operation, {
    bool withdrawal = false,
  }) {
    try {
      final scope = _scope();
      final generation = _generation;
      final previous = _mutations[logicalKey];
      for (final alias in aliases) {
        final owner = _aliases[alias];
        if (owner != null && owner != logicalKey) {
          throw const ShareCoinException(CoinErrorCode.conflict);
        }
      }
      if (previous != null) {
        if (previous.fingerprint != fingerprint) {
          throw const ShareCoinException(CoinErrorCode.conflict);
        }
        final combined = previous.aliases.union(aliases.toSet());
        if (combined.length > 16) {
          throw const ShareCoinException(CoinErrorCode.rateLimited);
        }
        previous.aliases.addAll(aliases);
        for (final alias in aliases) {
          _aliases[alias] = logicalKey;
        }
        return previous.future.then((value) => value as CoinData<T>);
      }
      if (withdrawal &&
          (_withdrawalLock != null || _activeWithdrawalId != null)) {
        throw const ShareCoinException(CoinErrorCode.conflict);
      }
      while (_mutations.length >= mutationLimit) {
        final removable = _mutations.entries
            .where((entry) => entry.value.settled && !entry.value.uncertain)
            .firstOrNull;
        if (removable == null) {
          throw const ShareCoinException(CoinErrorCode.rateLimited);
        }
        _mutations.remove(removable.key);
        for (final alias in removable.value.aliases) {
          _aliases.remove(alias);
        }
      }
      final completion = Completer<CoinData<T>>();
      final record = _CoinMutation(
        fingerprint,
        idempotencyKey,
        completion.future,
      );
      record.aliases.addAll(aliases);
      _mutations[logicalKey] = record;
      for (final alias in aliases) {
        _aliases[alias] = logicalKey;
      }
      if (withdrawal) _withdrawalLock = idempotencyKey;
      var sent = false;
      Future<void>(() async {
        try {
          await _online(scope, generation);
          await _activeAccount(scope, generation);
          final result = await operation(scope, generation, () {
            _current(scope, generation);
            if (_suspended) {
              throw const ShareCoinException(CoinErrorCode.offline);
            }
            sent = true;
            _invalidateWallet(scope);
          });
          _current(scope, generation);
          record.settled = true;
          _invalidateWallet(scope);
          completion.complete(result);
          if (!_closed) notifyListeners();
        } catch (error) {
          record.settled = true;
          record.uncertain =
              sent &&
              (error is! ShareCoinException ||
                  error.outcomeUncertain ||
                  error.code == CoinErrorCode.accountChanged ||
                  error.code == CoinErrorCode.disposed);
          final failure = record.uncertain
              ? const ShareCoinException(CoinErrorCode.uncertain)
              : error;
          if (!sent && identical(_mutations[logicalKey], record)) {
            _mutations.remove(logicalKey);
            for (final alias in record.aliases) {
              _aliases.remove(alias);
            }
          }
          completion.completeError(failure);
        } finally {
          if (sent &&
              !_closed &&
              _backend.scope?.key == scope.key &&
              generation == _generation) {
            _invalidateWallet(scope);
          }
          if (withdrawal &&
              !record.uncertain &&
              _backend.scope?.key == scope.key &&
              generation == _generation &&
              _withdrawalLock == idempotencyKey) {
            _withdrawalLock = null;
          }
        }
      });
      return completion.future;
    } catch (error) {
      return Future<CoinData<T>>.error(error);
    }
  }

  void _invalidateWallet(AccountScope scope) {
    if (_closed || _backend.scope?.key != scope.key) return;
    _walletGeneration += 1;
    _cache.removeWhere((key, value) => key.startsWith('${scope.key}|wallet|'));
    notifyListeners();
  }

  Future<CoinData<RewardEvent>> submitRewardEvent(RewardEvent event) {
    if (event.status != RewardEventStatus.created ||
        event.transactionId != null) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final signature = event.toJson()
      ..remove('eventId')
      ..remove('idempotencyKey')
      ..remove('occurredAt');
    return _mutate(
      'reward:${event.actionKey}',
      jsonEncode(_canonical(signature)),
      ['rewardId:${event.eventId}', 'key:${event.idempotencyKey}'],
      event.idempotencyKey,
      (scope, generation, sent) async {
        if (event.userId != scope.userId) {
          throw const ShareCoinException(CoinErrorCode.accountChanged);
        }
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.submitReward,
          event.toJson(),
          (j, owner) {
            final reply = RewardEvent.fromJson(j);
            if (reply.userId != owner.userId ||
                reply.eventId != event.eventId ||
                reply.actionKey != event.actionKey ||
                reply.idempotencyKey != event.idempotencyKey ||
                reply.requestedCoins != event.requestedCoins ||
                reply.status == RewardEventStatus.created ||
                reply.status == RewardEventStatus.submitted) {
              throw const CoinModelException('reward confirmation');
            }
            return reply;
          },
          mutation: true,
        );
      },
    );
  }

  Future<CoinData<RewardEvent>> getRewardEventStatus(String eventId) => _read(
    ShareCoinOperation.rewardStatus,
    (j, scope) {
      final event = RewardEvent.fromJson(j);
      if (event.userId != scope.userId || event.eventId != eventId) {
        throw const CoinModelException('reward identity');
      }
      return event;
    },
    arguments: {'eventId': coinId(eventId, 'eventId')},
    allowCached: false,
  );

  Future<CoinData<OfferStart>> startOffer(
    String offerId, {
    required String idempotencyKey,
  }) {
    coinId(offerId, 'offerId');
    coinId(idempotencyKey, 'idempotencyKey');
    return _mutate(
      'offer:$offerId',
      offerId,
      ['key:$idempotencyKey'],
      idempotencyKey,
      (scope, generation, sent) async {
        final offer = await getOfferStatus(offerId, allowCached: false);
        _current(scope, generation);
        if (!offer.data.availableAt(offer.serverTime)) {
          throw const ShareCoinException(CoinErrorCode.invalidRequest);
        }
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.startOffer,
          {'offerId': offerId, 'idempotencyKey': idempotencyKey},
          (j, owner) {
            final start = OfferStart.fromJson(j);
            if (start.offerId != offerId ||
                start.userId != owner.userId ||
                start.idempotencyKey != idempotencyKey) {
              throw const CoinModelException('offer start confirmation');
            }
            return start;
          },
          mutation: true,
        );
      },
    );
  }

  Future<CoinData<WithdrawalRequest>> requestWithdrawal(
    WithdrawalIntent intent,
  ) => _mutate(
    'withdrawal:${intent.idempotencyKey}',
    jsonEncode(_canonical(intent.toJson())),
    ['key:${intent.idempotencyKey}'],
    intent.idempotencyKey,
    (scope, generation, sent) async {
      if (intent.userId != scope.userId) {
        throw const ShareCoinException(CoinErrorCode.accountChanged);
      }
      final policy = (await getWithdrawalPolicy(allowCached: false)).data;
      final wallet = (await getCurrentWallet(allowCached: false)).data;
      _current(scope, generation);
      if (intent.coins < policy.minimumCoins) {
        throw const ShareCoinException(CoinErrorCode.minimum);
      }
      if (intent.coins > wallet.available) {
        throw const ShareCoinException(CoinErrorCode.insufficientBalance);
      }
      if (policy.activeRequestIds.isNotEmpty) {
        throw const ShareCoinException(CoinErrorCode.conflict);
      }
      if (policy.version != intent.policyVersion) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      final method = policy.methods
          .where((method) => method.method == intent.method)
          .firstOrNull;
      if (method == null ||
          !method.usable ||
          method.destinationReference != intent.destinationReference) {
        throw const ShareCoinException(CoinErrorCode.payoutUnavailable);
      }
      final gross = policy.rate.grossMinor(intent.coins);
      if (method.feeMinor > gross ||
          method.feeMinor != intent.expectedFeeMinor ||
          gross - method.feeMinor != intent.expectedFinalMinor) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      sent();
      final response = await _execute(
        scope,
        generation,
        ShareCoinOperation.requestWithdrawal,
        intent.toJson(),
        (j, owner) {
          final request = WithdrawalRequest.fromJson(j);
          if (request.userId != owner.userId ||
              request.idempotencyKey != intent.idempotencyKey ||
              request.requestedCoins != intent.coins ||
              request.method != intent.method ||
              request.maskedDestination != method.maskedDestination ||
              request.feeMinor != intent.expectedFeeMinor ||
              request.finalPayoutMinor != intent.expectedFinalMinor ||
              jsonEncode(request.rate.toJson()) !=
                  jsonEncode(policy.rate.toJson())) {
            throw const CoinModelException('withdrawal confirmation');
          }
          return request;
        },
        mutation: true,
      );
      _rememberWithdrawal(response.data);
      return response;
    },
    withdrawal: true,
  );

  void _rememberWithdrawal(WithdrawalRequest request) {
    final previous = _withdrawalStates[request.withdrawalId];
    if (previous != null &&
        (request.updatedAt.isBefore(previous.updatedAt) ||
            !previous.canTransitionTo(request.status))) {
      throw const CoinModelException('withdrawal status regression');
    }
    _withdrawalStates[request.withdrawalId] = request;
    if (_withdrawalStates.length > 100) {
      _withdrawalStates.remove(_withdrawalStates.keys.first);
    }
    if (request.active) {
      _activeWithdrawalId = request.withdrawalId;
    } else if (_activeWithdrawalId == request.withdrawalId ||
        _withdrawalLock == request.idempotencyKey) {
      _activeWithdrawalId = null;
      _withdrawalLock = null;
    }
  }

  Future<CoinData<WithdrawalRequest>> getWithdrawalStatus(
    String withdrawalId,
  ) async {
    final response = await _read(
      ShareCoinOperation.withdrawalStatus,
      (j, scope) {
        final request = WithdrawalRequest.fromJson(j);
        if (request.withdrawalId != withdrawalId ||
            request.userId != scope.userId) {
          throw const CoinModelException('withdrawal identity');
        }
        return request;
      },
      arguments: {'withdrawalId': coinId(withdrawalId, 'withdrawalId')},
      allowCached: false,
    );
    try {
      _rememberWithdrawal(response.data);
    } on CoinModelException {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    return response;
  }

  Future<CoinData<WithdrawalRequest>> getWithdrawalByKey(
    String idempotencyKey,
  ) async {
    final response = await _read(
      ShareCoinOperation.withdrawalByKey,
      (j, scope) {
        final request = WithdrawalRequest.fromJson(j);
        if (request.userId != scope.userId ||
            request.idempotencyKey != idempotencyKey) {
          throw const CoinModelException('withdrawal key');
        }
        return request;
      },
      arguments: {'idempotencyKey': coinId(idempotencyKey, 'idempotencyKey')},
      allowCached: false,
    );
    try {
      _rememberWithdrawal(response.data);
    } on CoinModelException {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    return response;
  }

  Map<String, Object?> _offerArguments(
    OfferQuery query,
    int? minimum,
    int? maximum,
  ) {
    if (minimum != null) coinInt(minimum, 'minimumReward');
    if (maximum != null) coinInt(maximum, 'maximumReward');
    if (minimum != null && maximum != null && minimum > maximum) {
      throw const CoinModelException('reward range');
    }
    final args = query.toJson();
    if (minimum != null) args['minimumReward'] = minimum;
    if (maximum != null) args['maximumReward'] = maximum;
    return args;
  }

  bool get rewardExtensionsAvailable =>
      _backend.configured && _backend is ShareCoinRewardBackend;

  Future<Map<String, dynamic>> _extension(
    ShareCoinRewardOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  ) {
    final backend = _backend;
    if (backend is! ShareCoinRewardBackend) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    return backend.executeRewardExtension(
      operation,
      scope,
      Map<String, Object?>.unmodifiable(arguments),
    );
  }

  Future<CoinData<ShareCoinTransaction>> getTransaction(
    String transactionId, {
    bool allowCached = false,
  }) => _read(
    ShareCoinOperation.transactions,
    (j, scope) {
      final transaction = ShareCoinTransaction.fromJson(j);
      if (transaction.transactionId != transactionId) {
        throw const CoinModelException('transactionId');
      }
      return _owned(transaction, transaction.userId, scope);
    },
    arguments: {'transactionId': coinId(transactionId, 'transactionId')},
    allowCached: allowCached,
    request: (scope, args) =>
        _extension(ShareCoinRewardOperation.transaction, scope, args),
  );

  Future<CoinData<RewardSession>> prepareRewardSession(
    CoinSource source,
    String targetId, {
    required String idempotencyKey,
  }) {
    coinId(targetId, 'targetId');
    coinId(idempotencyKey, 'idempotencyKey');
    if (!rewardExtensionsAvailable) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.notConfigured),
      );
    }
    if (!<CoinSource>{
      CoinSource.adReward,
      CoinSource.dailyReward,
      CoinSource.promotionReward,
    }.contains(source)) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final args = <String, Object?>{
      'source': source.name,
      'targetId': targetId,
      'idempotencyKey': idempotencyKey,
    };
    return _mutate(
      'reward-session:$idempotencyKey',
      jsonEncode(args),
      ['session-key:$idempotencyKey'],
      idempotencyKey,
      (scope, generation, sent) async {
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.submitReward,
          args,
          (j, owner) {
            final session = RewardSession.fromJson(j);
            if (session.userId != owner.userId ||
                session.source != source ||
                session.targetId != targetId ||
                session.requestKey != idempotencyKey) {
              throw const CoinModelException('reward session identity');
            }
            return session;
          },
          mutation: true,
          request: () =>
              _extension(ShareCoinRewardOperation.prepareReward, scope, args),
        );
      },
    );
  }

  Future<CoinData<RewardSession>> getRewardSessionStatus({
    String? sessionId,
    String? requestKey,
  }) {
    if ((sessionId == null) == (requestKey == null)) {
      throw const CoinModelException('one session reference required');
    }
    final args = <String, Object?>{};
    if (sessionId != null) args['sessionId'] = coinId(sessionId, 'sessionId');
    if (requestKey != null) {
      args['requestKey'] = coinId(requestKey, 'requestKey');
    }
    return _read(
      ShareCoinOperation.rewardStatus,
      (j, scope) {
        final session = RewardSession.fromJson(j);
        if (session.userId != scope.userId ||
            sessionId != null && session.sessionId != sessionId ||
            requestKey != null && session.requestKey != requestKey) {
          throw const CoinModelException('reward session identity');
        }
        return session;
      },
      arguments: args,
      allowCached: false,
      request: (scope, args) =>
          _extension(ShareCoinRewardOperation.sessionStatus, scope, args),
    );
  }

  Future<CoinData<OfferLaunchGrant>> getOfferLaunch(
    OfferStart start,
    OfferPlatform platform,
  ) => _read(
    ShareCoinOperation.offerStatus,
    (j, scope) {
      final grant = OfferLaunchGrant.fromJson(j);
      if (grant.userId != scope.userId ||
          start.userId != scope.userId ||
          grant.startId != start.startId ||
          grant.offerId != start.offerId ||
          grant.platform != platform) {
        throw const CoinModelException('offer launch grant');
      }
      return grant;
    },
    arguments: {'startId': start.startId, 'platform': platform.name},
    allowCached: false,
    request: (scope, args) =>
        _extension(ShareCoinRewardOperation.offerLaunch, scope, args),
  );

  void suspend() {
    if (_closed) return;
    _suspended = true;
    connectivity.suspend();
  }

  void resume() {
    if (_closed) return;
    _suspended = false;
    connectivity.resume();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    unawaited(_accountSubscription.cancel());
    _cache.clear();
    _reads.clear();
    _mutations.clear();
    _aliases.clear();
    if (_ownsConnectivity) connectivity.dispose();
    super.dispose();
  }
}
