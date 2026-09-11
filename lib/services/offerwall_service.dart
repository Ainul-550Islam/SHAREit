import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import 'share_coin_service.dart';
import 'authenticated_backend_repository.dart';

typedef RewardLinkLauncher = Future<bool> Function(Uri uri);

Future<bool> launchRewardLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class OfferResourcePolicy {
  OfferResourcePolicy({
    Iterable<String> linkOrigins = const [],
    Iterable<String> imageOrigins = const [],
  }) : linkOrigins = _origins(linkOrigins),
       imageOrigins = _origins(imageOrigins);
  final Set<String> linkOrigins, imageOrigins;
  static Set<String> _origins(Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      final uri = coinHttpsUrl(value, 'trusted origin')!;
      if (uri.hasQuery || uri.path.isNotEmpty && uri.path != '/') {
        throw const CoinModelException('origin only');
      }
      result.add(uri.origin);
    }
    return Set<String>.unmodifiable(result);
  }

  bool allowsLink(Uri? uri) => _allowed(uri, linkOrigins);
  bool allowsImage(Uri? uri) => _allowed(uri, imageOrigins);
  bool _allowed(Uri? uri, Set<String> origins) {
    if (uri == null) return false;
    try {
      return origins.contains(coinHttpsUrl(uri, 'resource URL')!.origin);
    } catch (_) {
      return false;
    }
  }
}

class OfferThumbnailCache {
  OfferThumbnailCache({
    required this.policy,
    required this.canFetch,
    this.fetchBytes,
    this.maxEntries = 40,
    this.maxBytes = 4 * 1024 * 1024,
    this.parallelism = 3,
  }) {
    if (maxEntries < 1 || maxBytes < 1 || parallelism < 1 || parallelism > 4) {
      throw ArgumentError('Invalid thumbnail limits.');
    }
  }
  final OfferResourcePolicy policy;
  final bool Function() canFetch;
  final Future<Uint8List> Function(Uri)? fetchBytes;
  final int maxEntries, maxBytes, parallelism;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _pending = {};
  final Queue<({Uri uri, int epoch, Completer<Uint8List?> result})> _queue =
      Queue();
  final Set<HttpClient> _clients = {};
  int _bytes = 0, _active = 0, _epoch = 0;
  bool _closed = false;
  int get cachedBytes => _bytes;
  int get entryCount => _cache.length;
  int get activeRequests => _active;

  Future<Uint8List?> get(Uri? uri) {
    if (_closed || !policy.allowsImage(uri)) return Future.value(null);
    final key = uri.toString();
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return Future.value(hit);
    }
    if (!canFetch()) return Future.value(null);
    final running = _pending[key];
    if (running != null) return running;
    if (_queue.length >= 32) return Future.value(null);
    final result = Completer<Uint8List?>();
    _pending[key] = result.future;
    _queue.add((uri: uri!, epoch: _epoch, result: result));
    _pump();
    return result.future;
  }

  void _pump() {
    while (!_closed && _active < parallelism && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active += 1;
      unawaited(
        _load(job.uri)
            .then(
              (data) {
                if (_closed || job.epoch != _epoch) {
                  job.result.complete(null);
                  return;
                }
                if (data != null && data.length <= maxBytes) {
                  final old = _cache.remove(job.uri.toString());
                  if (old != null) _bytes -= old.length;
                  _cache[job.uri.toString()] = data;
                  _bytes += data.length;
                  while (_cache.length > maxEntries || _bytes > maxBytes) {
                    _bytes -= _cache.remove(_cache.keys.first)!.length;
                  }
                }
                job.result.complete(data);
              },
              onError: (Object error, StackTrace stack) {
                job.result.complete(null);
              },
            )
            .whenComplete(() {
              if (identical(_pending[job.uri.toString()], job.result.future)) {
                _pending.remove(job.uri.toString());
              }
              _active -= 1;
              _pump();
            }),
      );
    }
  }

  Future<Uint8List?> _load(Uri uri) async {
    try {
      final bytes = await (fetchBytes?.call(uri) ?? _download(uri)).timeout(
        const Duration(seconds: 10),
      );
      if (bytes.isEmpty || bytes.length > 512 * 1024 || _closed) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      ui.Image? image;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 2048 ||
            descriptor.height > 2048 ||
            descriptor.width * descriptor.height > 4 * 1024 * 1024) {
          return null;
        }
        final largest = descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height;
        final scale = largest > 128 ? 128 / largest : 1.0;
        final width = (descriptor.width * scale).round().clamp(1, 128);
        final height = (descriptor.height * scale).round().clamp(1, 128);
        codec = await descriptor.instantiateCodec(
          targetWidth: width,
          targetHeight: height,
        );
        if (codec.frameCount != 1) return null;
        image = (await codec.getNextFrame()).image;
        final result = await image.toByteData(format: ui.ImageByteFormat.png);
        final data = result?.buffer.asUint8List(
          result.offsetInBytes,
          result.lengthInBytes,
        );
        return data == null || data.length > 128 * 1024 ? null : data;
      } finally {
        image?.dispose();
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _download(Uri uri) async {
    if (!policy.allowsImage(uri) || !canFetch() || _closed) {
      throw const ShareCoinException(CoinErrorCode.offline);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    _clients.add(client);
    final deadline = Timer(
      const Duration(seconds: 8),
      () => client.close(force: true),
    );
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'image/png,image/jpeg,image/webp',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200 ||
          response.contentLength > 512 * 1024 ||
          !<String>{
            'image/png',
            'image/jpeg',
            'image/webp',
          }.contains(response.headers.contentType?.mimeType)) {
        throw const FormatException('Unsupported image response.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        if (_closed || bytes.length + chunk.length > 512 * 1024) {
          throw const FormatException('Image limit exceeded.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      deadline.cancel();
      _clients.remove(client);
      client.close(force: true);
    }
  }

  void clear() {
    _epoch += 1;
    _cache.clear();
    _bytes = 0;
    _pending.clear();
    while (_queue.isNotEmpty) {
      _queue.removeFirst().result.complete(null);
    }
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    clear();
  }
}

class OfferwallController extends ValueNotifier<OfferwallState> {
  OfferwallController({
    required this.service,
    OfferResourcePolicy? policy,
    this.launcher = launchRewardLink,
    this.platform = OfferPlatform.android,
    this.pageSize = 20,
    this.windowSize = 500,
    this.debounce = const Duration(milliseconds: 350),
    this.clock,
  }) : policy = policy ?? OfferResourcePolicy(),
       super(OfferwallState(filter: OfferwallFilter(platform: platform))) {
    if (pageSize < 1 ||
        pageSize > 100 ||
        windowSize < pageSize ||
        windowSize % pageSize != 0 ||
        windowSize > 1000) {
      throw ArgumentError('Invalid offer window.');
    }
    _scope = service.accountKey;
    _reconciler = ShareCoinReconciler(service: service);
    service.addListener(_accountChanged);
    images = OfferThumbnailCache(
      policy: this.policy,
      canFetch: () => service.connectivity.value.canRequestRewards,
    );
  }
  final ShareCoinService service;
  final OfferResourcePolicy policy;
  final RewardLinkLauncher launcher;
  final OfferPlatform platform;
  final int pageSize, windowSize;
  final Duration debounce;
  final Duration Function()? clock;
  final Stopwatch _watch = Stopwatch()..start();
  late final OfferThumbnailCache images;
  late final ShareCoinReconciler _reconciler;
  final Map<String, CoinData<Offer>> details = {};
  final Map<String, CoinData<OfferStart>> starts = {};
  final Map<String, OfferRewardStatus> credits = {};
  final Map<String, String> _startKeys = {};
  final Map<String, Future<void>> _starting = {};
  final LinkedHashSet<String> _seen = LinkedHashSet();
  final Set<String> _cursors = {};
  Timer? _debounce;
  String? _scope;
  int _generation = 0;
  bool _closed = false, _suspended = false;
  DateTime? _serverTime;
  Duration _serverMark = Duration.zero;
  String? actionMessage;
  Duration get _now => clock?.call() ?? _watch.elapsed;
  DateTime? get serverEstimate => _serverTime?.add(
    _now >= _serverMark ? _now - _serverMark : Duration.zero,
  );
  bool isStarting(String id) => _starting.containsKey(id);

  void _accountChanged() {
    if (_closed || _scope == service.accountKey) return;
    _scope = service.accountKey;
    _generation += 1;
    _debounce?.cancel();
    _seen.clear();
    _cursors.clear();
    details.clear();
    starts.clear();
    credits.clear();
    _startKeys.clear();
    _starting.clear();
    images.clear();
    _serverTime = null;
    actionMessage = null;
    value = OfferwallState(
      filter: value.filter,
      message: 'Account changed. Refresh offers.',
    );
  }

  void setFilter(OfferwallFilter filter, {bool delayed = false}) {
    if (_closed) return;
    _generation += 1;
    _debounce?.cancel();
    _seen.clear();
    _cursors.clear();
    value = OfferwallState(
      filter: filter,
      state: delayed ? OfferLoadState.debouncing : OfferLoadState.idle,
    );
    if (delayed) {
      _debounce = Timer(debounce, refresh);
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_closed || _suspended) return;
    _debounce?.cancel();
    _generation += 1;
    _seen.clear();
    _cursors.clear();
    value = OfferwallState(filter: value.filter);
    await _page(1, null, replace: true);
  }

  Future<void> loadMore() async {
    if (_closed ||
        _suspended ||
        value.busy ||
        !value.hasNext ||
        value.windowFull) {
      return;
    }
    await _page(value.page!.page + 1, value.page!.nextCursor);
  }

  Future<void> nextWindow() async {
    if (_closed ||
        _suspended ||
        value.busy ||
        !value.hasNext ||
        !value.windowFull) {
      return;
    }
    final page = value.page!;
    value = OfferwallState(
      filter: value.filter,
      page: page,
      cached: value.cached,
      serverTime: value.serverTime,
    );
    await _page(page.page + 1, page.nextCursor, replace: true);
  }

  Future<void> _page(int page, String? cursor, {bool replace = false}) async {
    final generation = _generation;
    final scope = service.accountKey;
    final before = value;
    final filter = before.filter;
    value = OfferwallState(
      filter: filter,
      items: before.items,
      page: before.page,
      state: OfferLoadState.loading,
      cached: before.cached,
      serverTime: before.serverTime,
    );
    try {
      final result = await service.getOffers(
        query: filter.query(page: page, pageSize: pageSize, cursor: cursor),
        minimumReward: filter.minimumReward,
        maximumReward: filter.maximumReward,
      );
      if (!_current(generation, scope)) return;
      if (result.data.items.any((offer) => !filter.matches(offer)) ||
          result.data.info.hasNext &&
              result.data.info.nextCursor != null &&
              _cursors.contains(result.data.info.nextCursor)) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      if (result.data.info.nextCursor != null) {
        _cursors.add(result.data.info.nextCursor!);
      }
      if (_cursors.length > 128) _cursors.remove(_cursors.first);
      final items = replace ? <Offer>[] : before.items.toList();
      var duplicate = false;
      for (final offer in result.data.items) {
        if (_seen.add(offer.offerId)) {
          items.add(offer);
        } else {
          duplicate = true;
        }
      }
      if (items.length > windowSize) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      while (_seen.length > 2000) {
        _seen.remove(_seen.first);
      }
      _setTime(result.serverTime);
      value = OfferwallState(
        filter: filter,
        items: items,
        page: result.data.info,
        state: OfferLoadState.ready,
        cached: (!replace && before.cached) || result.cached,
        stale: result.cached,
        windowFull:
            items.length + pageSize > windowSize && result.data.info.hasNext,
        serverTime: result.serverTime,
        message: duplicate
            ? 'Duplicate offer IDs were ignored. Refresh if the catalog changed.'
            : null,
      );
    } catch (error) {
      if (_current(generation, scope)) {
        value = OfferwallState(
          filter: filter,
          items: before.items,
          page: before.page,
          state: OfferLoadState.error,
          cached: before.cached,
          stale: before.stale,
          serverTime: before.serverTime,
          message: _error(error),
        );
      }
    }
  }

  void _setTime(DateTime time) {
    final estimate = serverEstimate;
    _serverTime = estimate != null && estimate.isAfter(time) ? estimate : time;
    _serverMark = _now;
  }

  bool _current(int generation, String? scope) =>
      !_closed &&
      !_suspended &&
      generation == _generation &&
      scope == service.accountKey;
  String _error(Object error) => error is ShareCoinException
      ? error.message
      : 'The offer data could not be validated. Try refreshing.';

  Future<CoinData<Offer>?> refreshOffer(String id) async {
    final generation = _generation;
    final scope = service.accountKey;
    try {
      final result = await service.getOfferStatus(id, allowCached: false);
      if (!_current(generation, scope)) return null;
      details[id] = result;
      credits.remove(id);
      _setTime(result.serverTime);
      if (details.length > 100) details.remove(details.keys.first);
      actionMessage = null;
      if (result.data.status == OfferStatus.completed &&
          result.data.rewardTransactionId != null) {
        final transaction = await service.getTransaction(
          result.data.rewardTransactionId!,
        );
        if (!_current(generation, scope)) return null;
        final record = transaction.data;
        if (record.source != CoinSource.offerReward ||
            record.referenceId != id ||
            record.direction != CoinDirection.credit) {
          throw const ShareCoinException(CoinErrorCode.malformed);
        }
        final reconciliation = await _reconciler.reconcileOffer(id);
        if (!_current(generation, scope)) return null;
        credits[id] = OfferRewardStatus(
          state: reconciliation.state,
          transaction: reconciliation.transaction ?? record,
          note: reconciliation.message,
        );
        if (credits.length > 100) credits.remove(credits.keys.first);
        if (!reconciliation.reconciled &&
            record.status == CoinTransactionStatus.completed) {
          actionMessage = reconciliation.message;
        }
      } else if (result.data.status == OfferStatus.pending) {
        credits[id] = const OfferRewardStatus(state: RewardCreditState.pending);
      } else if (result.data.status == OfferStatus.rejected) {
        credits[id] = const OfferRewardStatus(
          state: RewardCreditState.rejected,
        );
      }
      if (_current(generation, scope)) notifyListeners();
      return result;
    } catch (error) {
      if (_current(generation, scope)) {
        actionMessage = _error(error);
        notifyListeners();
      }
      return null;
    }
  }

  Offer currentOffer(Offer original) =>
      details[original.offerId]?.data ?? original;
  OfferStatus statusOf(Offer original) {
    final offer = currentOffer(original);
    final now = serverEstimate;
    if (now != null &&
        !now.isBefore(offer.expiresAt) &&
        offer.status != OfferStatus.completed) {
      return OfferStatus.expired;
    }
    if (offer.status == OfferStatus.available &&
        starts.containsKey(offer.offerId)) {
      return starts[offer.offerId]!.data.status;
    }
    return offer.status;
  }

  String statusLabel(Offer original) {
    final credit = credits[original.offerId];
    if (credit != null) return credit.label;
    return switch (statusOf(original)) {
      OfferStatus.available => 'Available',
      OfferStatus.started => 'In Progress',
      OfferStatus.pending => 'Reward Pending',
      OfferStatus.completed => 'Completion reported · verify credit',
      OfferStatus.rejected => 'Rejected',
      OfferStatus.expired => 'Expired',
      OfferStatus.unavailable => 'Unavailable',
    };
  }

  Future<void> start(Offer original, {Future<bool> Function(Uri)? consent}) {
    final id = original.offerId;
    if (_closed || _suspended) return Future.value();
    final active = _starting[id];
    if (active != null) return active;
    final completion = Completer<void>();
    _starting[id] = completion.future;
    final generation = _generation;
    final scope = service.accountKey;
    Future<void>(() async {
      try {
        if (policy.linkOrigins.isEmpty || !service.rewardExtensionsAvailable) {
          throw const ShareCoinException(CoinErrorCode.notConfigured);
        }
        final fresh = await service.getOfferStatus(id, allowCached: false);
        if (!_current(generation, scope)) return;
        details[id] = fresh;
        _setTime(fresh.serverTime);
        if (!fresh.data.platforms.contains(platform) ||
            fresh.data.countries.isEmpty ||
            fresh.serverTime.isBefore(fresh.data.startsAt) ||
            !fresh.serverTime.isBefore(fresh.data.expiresAt) ||
            <OfferStatus>{
              OfferStatus.expired,
              OfferStatus.rejected,
              OfferStatus.unavailable,
              OfferStatus.completed,
            }.contains(fresh.data.status) ||
            !fresh.data.availableAt(fresh.serverTime) &&
                !starts.containsKey(id)) {
          throw const ShareCoinException(CoinErrorCode.invalidRequest);
        }
        var started = starts[id];
        if (started == null) {
          final key = _startKeys.putIfAbsent(id, newCoinRequestId);
          started = await service.startOffer(id, idempotencyKey: key);
          if (!_current(generation, scope)) return;
          starts[id] = started;
          if (starts.length > 100) {
            final oldest = starts.keys.first;
            starts.remove(oldest);
            _startKeys.remove(oldest);
          }
          notifyListeners();
        }
        final grant = await service.getOfferLaunch(started.data, platform);
        if (!_current(generation, scope)) return;
        if (!policy.allowsLink(grant.data.url) ||
            !grant.serverTime.isBefore(grant.data.expiresAt) ||
            grant.serverTime.isBefore(grant.data.issuedAt)) {
          throw const ShareCoinException(CoinErrorCode.invalidRequest);
        }
        final grantReceived = _now;
        if (consent != null && !await consent(grant.data.url)) {
          if (_current(generation, scope)) actionMessage = 'Start recorded; you chose not to open the provider link. No reward is inferred.';
          return;
        }
        if (!_current(generation, scope)) return;
        final waited = _now >= grantReceived
            ? _now - grantReceived
            : Duration.zero;
        final atLaunch = grant.serverTime.add(waited);
        if (!atLaunch.isBefore(grant.data.expiresAt) ||
            !atLaunch.isBefore(fresh.data.expiresAt)) {
          throw const ShareCoinException(CoinErrorCode.invalidRequest);
        }
        final launched = await launcher(grant.data.url);
        if (_current(generation, scope)) {
          actionMessage = launched
              ? 'Provider link opened. Complete its tasks, then check status. Opening is not earning.'
              : 'Start is recorded, but the link could not open. Retry Open offer; no reward is inferred.';
        }
      } catch (error) {
        if (_current(generation, scope)) actionMessage = _error(error);
      } finally {
        if (identical(_starting[id], completion.future)) _starting.remove(id);
        if (!_closed) notifyListeners();
        completion.complete();
      }
    });
    notifyListeners();
    return completion.future;
  }

  void suspend() {
    if (_closed) return;
    _suspended = true;
    _generation += 1;
    _debounce?.cancel();
    value = OfferwallState(
      filter: value.filter,
      items: value.items,
      page: value.page,
      state: OfferLoadState.ready,
      cached: value.cached,
      stale: true,
      windowFull: value.windowFull,
      serverTime: value.serverTime,
      message: 'Paused. Refresh after returning from the provider.',
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
    _debounce?.cancel();
    _watch.stop();
    service.removeListener(_accountChanged);
    images.dispose();
    _reconciler.dispose();
    super.dispose();
  }
}

class CoinFeedState<T> {
  CoinFeedState({
    Iterable<T> items = const [],
    this.page,
    this.loading = false,
    this.cached = false,
    this.error,
    this.windowFull = false,
    this.serverTime,
  }) : items = List<T>.unmodifiable(items);
  final List<T> items;
  final PageInfo? page;
  final bool loading, cached, windowFull;
  final String? error;
  final DateTime? serverTime;
}

class CoinFeedController<T> extends ValueNotifier<CoinFeedState<T>> {
  CoinFeedController({
    required this.service,
    required this.fetch,
    required this.id,
    this.pageSize = 20,
    this.windowSize = 500,
  }) : super(CoinFeedState<T>()) {
    if (pageSize < 1 ||
        pageSize > 100 ||
        windowSize < pageSize ||
        windowSize % pageSize != 0 ||
        windowSize > 1000) {
      throw ArgumentError('Invalid feed window.');
    }
    _scope = service.accountKey;
    service.addListener(_accountChanged);
  }
  final ShareCoinService service;
  final Future<CoinData<CoinPage<T>>> Function(OfferQuery query) fetch;
  final String Function(T item) id;
  final int pageSize, windowSize;
  String? _scope;
  int _generation = 0;
  bool _closed = false, _suspended = false;
  final Set<String> _cursors = {};
  void _accountChanged() {
    if (!_closed && _scope != service.accountKey) {
      _scope = service.accountKey;
      _generation += 1;
      _cursors.clear();
      value = CoinFeedState<T>();
    }
  }

  Future<void> refresh() async {
    if (_closed || _suspended) return;
    _generation += 1;
    _cursors.clear();
    value = CoinFeedState<T>();
    await _load(1, null, true);
  }

  Future<void> more() async {
    if (_closed ||
        _suspended ||
        value.loading ||
        !(value.page?.hasNext ?? false)) {
      return;
    }
    await _load(value.page!.page + 1, value.page!.nextCursor, value.windowFull);
  }

  Future<void> _load(int page, String? cursor, bool replace) async {
    final generation = _generation;
    final scope = service.accountKey;
    final old = value;
    value = CoinFeedState<T>(
      items: old.items,
      page: old.page,
      loading: true,
      cached: old.cached,
      serverTime: old.serverTime,
    );
    try {
      final response = await fetch(
        OfferQuery(page: page, pageSize: pageSize, cursor: cursor),
      );
      if (_closed ||
          _suspended ||
          generation != _generation ||
          scope != service.accountKey) {
        return;
      }
      if (response.data.info.nextCursor != null &&
          _cursors.contains(response.data.info.nextCursor)) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      if (response.data.info.nextCursor != null) {
        _cursors.add(response.data.info.nextCursor!);
      }
      if (_cursors.length > 128) _cursors.remove(_cursors.first);
      final items = replace ? <T>[] : old.items.toList();
      final seen = items.map(id).toSet();
      for (final item in response.data.items) {
        if (seen.add(id(item))) items.add(item);
      }
      if (items.length > windowSize) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      value = CoinFeedState<T>(
        items: items,
        page: response.data.info,
        cached: (!replace && old.cached) || response.cached,
        windowFull:
            items.length + pageSize > windowSize && response.data.info.hasNext,
        serverTime: response.serverTime,
      );
    } catch (error) {
      if (!_closed &&
          generation == _generation &&
          scope == service.accountKey) {
        value = CoinFeedState<T>(
          items: old.items,
          page: old.page,
          cached: old.cached,
          serverTime: old.serverTime,
          error: error is ShareCoinException
              ? error.message
              : 'Feed data could not be validated.',
        );
      }
    }
  }

  void suspend() {
    _suspended = true;
    _generation += 1;
    if (!_closed) {
      value = CoinFeedState<T>(
        items: value.items,
        page: value.page,
        cached: true,
        windowFull: value.windowFull,
        serverTime: value.serverTime,
      );
    }
  }

  void resume() {
    _suspended = false;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    service.removeListener(_accountChanged);
    super.dispose();
  }
}
