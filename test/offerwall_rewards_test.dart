import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/models/offerwall_models.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/share_coin_models.dart';
import 'package:sharebondhu/models/user_models.dart';
import 'package:sharebondhu/screens/home_screen.dart';
import 'package:sharebondhu/screens/offerwall_screen.dart';
import 'package:sharebondhu/screens/reward_center_screen.dart';
import 'package:sharebondhu/screens/share_coin_home_screen.dart';
import 'package:sharebondhu/services/connectivity_service.dart';
import 'package:sharebondhu/services/offerwall_service.dart';
import 'package:sharebondhu/services/share_coin_service.dart';

import 'transfer_progress_test.dart' as p5;
import 'widget_test.dart' as baseline;

final offerTestTime = DateTime.utc(2026, 9, 9, 12);

// Lightweight test catalog only. Production code never imports this fixture.
List<Offer> createOfferFixture([int count = 300]) => List<Offer>.generate(
  count,
  (index) => Offer(
    offerId: 'offer-${index.toString().padLeft(4, '0')}',
    title: 'Offer ${index.toString().padLeft(3, '0')}',
    shortDescription: 'A lightweight test task.',
    description: 'Fixture only; no real advertiser or payout.',
    publisher: 'Publisher ${index % 7}',
    category: OfferCategory.values[index % OfferCategory.values.length],
    rewardCoins: 100 + index,
    estimatedMinutes: 1 + index % 30,
    platforms: const [OfferPlatform.android, OfferPlatform.ios],
    countries: const ['BD'],
    status: OfferStatus.available,
    startsAt: offerTestTime.subtract(const Duration(days: 1)),
    expiresAt: offerTestTime.add(const Duration(days: 2)),
    provider: 'test-provider',
    featured: index % 40 == 0,
    sortPriority: index,
    iconUrl: Uri.parse('https://assets.example.org/$index.png'),
    instructions: const ['Complete the provider task.'],
    terms: const ['Backend validation required.'],
  ),
);

class OfferTestBackend extends p5.TestShareCoinBackend
    implements ShareCoinRewardBackend {
  OfferTestBackend([int count = 300]) : catalog = createOfferFixture(count);
  final List<Offer> catalog;
  final Map<String, OfferStart> starts = {};
  final Map<String, RewardSession> sessions = {};
  final Map<String, RewardEvent> rewardEvents = {};
  final Map<String, ShareCoinTransaction> ledger = {};
  final Map<ShareCoinRewardOperation, int> extensionCalls = {};
  final Map<String, String> offerTransactions = {};
  RewardAvailability availability = RewardAvailability.eligible;
  int used = 0, limit = 5;
  bool approveImmediately = false,
      rejectSignature = false,
      duplicatePage = false;
  Uri launch = Uri.parse('https://offers.example.org/task');
  OfferStatus? forcedOfferStatus;
  Future<Map<String, dynamic>> Function(
    ShareCoinRewardOperation,
    AccountScope,
    Map<String, Object?>,
  )?
  extensionHandler;

  @override
  Map<String, dynamic> envelope(
    AccountScope owner,
    Map<String, Object?> data,
  ) => {
    'userId': owner.userId,
    'serverTime': offerTestTime.toIso8601String(),
    'version': 'test-v6',
    'data': data,
  };

  Offer offer(String id) {
    final original = catalog.where((item) => item.offerId == id).firstOrNull;
    if (original == null) {
      throw const ShareCoinException(CoinErrorCode.notFound);
    }
    final json = original.toJson();
    if (offerTransactions.containsKey(id)) {
      json['status'] = OfferStatus.completed.name;
      json['rewardTransactionId'] = offerTransactions[id];
    } else if (forcedOfferStatus != null) {
      json['status'] = forcedOfferStatus!.name;
    } else if (starts.containsKey(id)) {
      json['status'] = starts[id]!.status.name;
    }
    return Offer.fromJson(json);
  }

  @override
  Map<String, Object?> dataFor(
    ShareCoinOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    if (op == ShareCoinOperation.offers) {
      final query = OfferQuery.fromJson(args);
      final filter = OfferwallFilter(
        search: query.search,
        category: query.category,
        sort: query.sort,
        platform: query.platform,
        country: query.country,
        minimumReward: args['minimumReward'] as int?,
        maximumReward: args['maximumReward'] as int?,
      );
      final all =
          catalog
              .map((item) => offer(item.offerId))
              .where(filter.matches)
              .toList()
            ..sort(filter.compare);
      final offset = (query.page - 1) * query.pageSize;
      final items = offset >= all.length
          ? <Offer>[]
          : all.skip(offset).take(query.pageSize).toList();
      if (duplicatePage && query.page == 2 && items.isNotEmpty) {
        items[0] = all.first;
      }
      return {
        'items': items.map((item) => item.toJson()).toList(),
        'page': PageInfo(
          page: query.page,
          pageSize: query.pageSize,
          total: all.length,
          hasNext: offset + items.length < all.length,
          nextCursor: offset + items.length < all.length
              ? 'page-${query.page + 1}'
              : null,
          previousCursor: query.page > 1 ? 'page-${query.page - 1}' : null,
        ).toJson(),
      };
    }
    if (op == ShareCoinOperation.offer ||
        op == ShareCoinOperation.offerStatus) {
      return offer(args['offerId'] as String).toJson();
    }
    if (op == ShareCoinOperation.startOffer) {
      final id = args['offerId'] as String;
      if (!offer(id).availableAt(offerTestTime)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      return (starts[id] = OfferStart(
        startId: 'start-$id',
        offerId: id,
        userId: owner.userId,
        idempotencyKey: args['idempotencyKey'] as String,
        status: OfferStatus.started,
        updatedAt: offerTestTime,
      )).toJson();
    }
    if (op == ShareCoinOperation.adsConfiguration) {
      return AdConfiguration(
        rewardedEnabled: true,
        bannerEnabled: false,
        interstitialEnabled: false,
        cooldownSeconds: 60,
        dailyLimit: 5,
        premium: false,
        provider: 'test-provider',
        units: const {'rewarded': 'test-unit'},
      ).toJson();
    }
    if (op == ShareCoinOperation.dailyConfiguration) {
      return DailyRewardConfiguration(
        dayRewards: const [10, 20, 30, 40, 50, 60, 70],
        streakDay: 2,
        eligible: true,
        nextEligibleAt: offerTestTime,
        version: 'daily-policy',
      ).toJson();
    }
    if (op == ShareCoinOperation.submitReward) {
      if (rejectSignature) {
        throw ShareCoinException.fromServerCode('invalid_provider_signature');
      }
      final event = RewardEvent.fromJson(args);
      final ticket = sessions.values
          .where((ticket) => ticket.eventId == event.eventId)
          .firstOrNull;
      if (ticket == null ||
          ticket.userId != owner.userId ||
          event.requestedCoins != ticket.rewardCoins) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      final json = event.toJson()..['status'] = RewardEventStatus.pending.name;
      rewardEvents[event.eventId] = RewardEvent.fromJson(json);
      if (approveImmediately) approve(ticket);
      return rewardEvents[event.eventId]!.toJson();
    }
    if (op == ShareCoinOperation.rewardStatus) {
      final event = rewardEvents[args['eventId']];
      if (event == null) throw const ShareCoinException(CoinErrorCode.notFound);
      return event.toJson();
    }
    if (op == ShareCoinOperation.transactions) {
      final query = OfferQuery.fromJson(args);
      final values = ledger.values.toList();
      final offset = (query.page - 1) * query.pageSize;
      final items = values.skip(offset).take(query.pageSize).toList();
      final more = offset + items.length < values.length;
      return {
        'items': items.map((item) => item.toJson()).toList(),
        'page': PageInfo(
          page: query.page,
          pageSize: query.pageSize,
          total: values.length,
          hasNext: more,
          nextCursor: more ? 'ledger-${query.page + 1}' : null,
        ).toJson(),
      };
    }
    if (op == ShareCoinOperation.promotions) {
      return page([promotion().toJson()], args);
    }
    return super.dataFor(op, owner, args);
  }

  Promotion promotion() => Promotion(
    campaignId: 'campaign-1',
    title: 'Test promotion',
    description: 'Fixture campaign, not an advertiser payout.',
    advertiser: 'Test advertiser',
    cta: 'Open test campaign',
    rewardCoins: 150,
    startsAt: offerTestTime.subtract(const Duration(days: 1)),
    endsAt: offerTestTime.add(const Duration(days: 1)),
    status: PromotionStatus.active,
    trackingId: 'campaign-track',
  );

  void approve(RewardSession ticket) {
    final previous =
        rewardEvents[ticket.eventId] ??
        RewardEvent(
          eventId: ticket.eventId,
          userId: ticket.userId,
          source: ticket.source,
          provider: ticket.provider,
          providerEventId: ticket.providerEventId ?? 'provider-event',
          targetId: ticket.targetId,
          requestedCoins: ticket.rewardCoins,
          occurredAt: offerTestTime,
          status: RewardEventStatus.pending,
          idempotencyKey: ticket.idempotencyKey,
        );
    final id = 'transaction-${ticket.sessionId}';
    if (!ledger.containsKey(id)) {
      // Emulates a backend ledger mutation in a test, never client wallet logic.
      balance += ticket.rewardCoins;
      ledger[id] = ShareCoinTransaction(
        transactionId: id,
        userId: ticket.userId,
        amount: ticket.rewardCoins,
        direction: CoinDirection.credit,
        source: ticket.source,
        status: CoinTransactionStatus.completed,
        description: 'Test backend credit.',
        createdAt: offerTestTime,
        completedAt: offerTestTime,
        referenceId: ticket.targetId,
        idempotencyKey: ticket.idempotencyKey,
      );
    }
    rewardEvents[ticket.eventId] = RewardEvent.fromJson(
      previous.toJson()
        ..['status'] = RewardEventStatus.approved.name
        ..['transactionId'] = id,
    );
  }

  @override
  Future<Map<String, dynamic>> executeRewardExtension(
    ShareCoinRewardOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) async {
    extensionCalls[op] = (extensionCalls[op] ?? 0) + 1;
    if (extensionHandler != null) return extensionHandler!(op, owner, args);
    return extensionResponse(op, owner, args);
  }

  Map<String, dynamic> extensionResponse(
    ShareCoinRewardOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    switch (op) {
      case ShareCoinRewardOperation.offerLaunch:
        final start = starts.values
            .where((value) => value.startId == args['startId'])
            .firstOrNull;
        if (start == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(
          owner,
          OfferLaunchGrant(
            startId: start.startId,
            offerId: start.offerId,
            userId: owner.userId,
            platform: coinEnum(
              args['platform'],
              OfferPlatform.values,
              'platform',
            ),
            url: launch,
            issuedAt: offerTestTime,
            expiresAt: offerTestTime.add(const Duration(minutes: 10)),
          ).toJson(),
        );
      case ShareCoinRewardOperation.prepareReward:
        final key = args['idempotencyKey'] as String;
        final existing = sessions.values
            .where((value) => value.requestKey == key)
            .firstOrNull;
        if (existing != null) return envelope(owner, existing.toJson());
        final number = sessions.length + 1;
        final source = coinEnum(args['source'], CoinSource.values, 'source');
        final session = RewardSession(
          sessionId: 'session-$number',
          userId: owner.userId,
          eventId: 'reward-$number',
          idempotencyKey: 'claim-$number',
          requestKey: key,
          source: source,
          provider: 'test-provider',
          targetId: args['targetId'] as String,
          rewardCoins: source == CoinSource.dailyReward ? 20 : 150,
          issuedAt: offerTestTime,
          expiresAt: offerTestTime.add(const Duration(minutes: 10)),
          notBefore: availability == RewardAvailability.cooldown
              ? offerTestTime.add(const Duration(seconds: 60))
              : offerTestTime,
          availability: availability,
          usedToday: used,
          dailyLimit: limit,
          providerEventId: source == CoinSource.dailyReward
              ? 'daily-server-event'
              : null,
          launchUrl: source == CoinSource.promotionReward ? launch : null,
        );
        sessions[session.sessionId] = session;
        return envelope(owner, session.toJson());
      case ShareCoinRewardOperation.sessionStatus:
        final session = sessions.values
            .where(
              (item) =>
                  args['sessionId'] == item.sessionId ||
                  args['requestKey'] == item.requestKey,
            )
            .firstOrNull;
        if (session == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(owner, session.toJson());
      case ShareCoinRewardOperation.transaction:
        final transaction = ledger[args['transactionId']];
        if (transaction == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(owner, transaction.toJson());
    }
  }
}

class TestRewardedAd implements RewardedAdAdapter {
  final StreamController<RewardedAdEvent> stream =
      StreamController<RewardedAdEvent>.broadcast(sync: true);
  RewardSession? loaded;
  int loads = 0, shows = 0, dismissals = 0;
  bool closed = false;
  Object? loadError;
  @override
  bool get configured => true;
  @override
  String get provider => 'test-provider';
  @override
  Stream<RewardedAdEvent> get events => stream.stream;
  @override
  Future<void> load(
    RewardSession session,
    AdConfiguration configuration,
  ) async {
    loads += 1;
    if (loadError != null) throw loadError!;
    loaded = session;
  }

  @override
  Future<void> show(String sessionId) async {
    shows += 1;
    stream.add(
      RewardedAdEvent(sessionId: sessionId, type: RewardedAdEventType.shown),
    );
  }

  void emit(
    RewardedAdEventType type, {
    String? sessionId,
    String? providerEvent,
  }) => stream.add(
    RewardedAdEvent(
      sessionId: sessionId ?? loaded!.sessionId,
      type: type,
      providerEventId: type == RewardedAdEventType.completed
          ? providerEvent ?? 'provider-event'
          : null,
    ),
  );
  @override
  Future<void> dismiss() async {
    dismissals += 1;
  }

  @override
  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    await stream.close();
  }
}

class OfferFixture {
  OfferFixture({int count = 300}) : backend = OfferTestBackend(count) {
    network = ConnectivityService(
      localProbe: () async => ['192.168.2.2'],
      internetProbe: () async => internet,
      serviceProbe: backend.checkService,
    );
    service = ShareCoinService(backend: backend, connectivity: network);
    controller = OfferwallController(
      service: service,
      policy: policy,
      clock: () => elapsed,
      launcher: (uri) async {
        launches.add(uri);
        return launchResult;
      },
    );
    rewards = RewardCoordinator(
      service: service,
      ad: ad,
      policy: policy,
      launcher: (uri) async {
        launches.add(uri);
        return launchResult;
      },
      clock: () => elapsed,
      autoTick: false,
    );
    addTearDown(() async {
      controller.dispose();
      rewards.dispose();
      service.dispose();
      network.dispose();
      await backend.close();
    });
  }
  final OfferTestBackend backend;
  final OfferResourcePolicy policy = OfferResourcePolicy(
    linkOrigins: const ['https://offers.example.org'],
  );
  final TestRewardedAd ad = TestRewardedAd();
  final List<Uri> launches = [];
  bool launchResult = true;
  InternetState internet = InternetState.available;
  Duration elapsed = Duration.zero;
  late final ConnectivityService network;
  late final ShareCoinService service;
  late final OfferwallController controller;
  late final RewardCoordinator rewards;
  void offline() {
    internet = InternetState.offline;
    backend.serviceState = CoinServiceState.unreachable;
  }
}

Future<void> settleReward(RewardCoordinator controller) async {
  if (!controller.value.busy) return;
  final done = Completer<void>();
  void listener() {
    if (!controller.value.busy && !done.isCompleted) done.complete();
  }

  controller.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
  } finally {
    controller.removeListener(listener);
  }
}

Future<void> mountOfferwall(
  WidgetTester tester,
  OfferFixture fixture, {
  Size size = const Size(390, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: OfferwallScreen(
        service: fixture.service,
        controller: fixture.controller,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Part 6 300-offer catalog', () {
    test('01 fixture has 300 unique lightweight offers and no live production source', () {
      final offers = createOfferFixture();
      expect(offers.length, 300);
      expect(offers.map((offer) => offer.offerId).toSet().length, 300);
      expect(
        offers.every((offer) => offer.description.contains('Fixture only')),
        isTrue,
      );
    });
    test(
      '02 pagination loads all 300 records from real service contracts',
      () async {
        final f = OfferFixture();
        await f.controller.refresh();
        while (f.controller.value.hasNext) {
          await f.controller.loadMore();
        }
        expect(f.controller.value.items.length, 300);
        expect(f.controller.value.total, 300);
        expect(f.backend.calls[ShareCoinOperation.offers], 15);
      },
    );
    test('03 cross-page duplicates are removed and disclosed', () async {
      final f = OfferFixture();
      f.backend.duplicatePage = true;
      await f.controller.refresh();
      await f.controller.loadMore();
      expect(f.controller.value.items.length, 39);
      expect(
        f.controller.value.items.map((item) => item.offerId).toSet().length,
        39,
      );
      expect(f.controller.value.message, contains('Duplicate'));
    });
    test('04 category and reward filters are passed to the backend', () async {
      final f = OfferFixture();
      f.controller.setFilter(
        OfferwallFilter(
          category: OfferCategory.games,
          minimumReward: 200,
          maximumReward: 260,
        ),
      );
      await f.controller.refresh();
      expect(f.controller.value.items, isNotEmpty);
      expect(
        f.controller.value.items.every(
          (item) =>
              item.category == OfferCategory.games &&
              item.rewardCoins >= 200 &&
              item.rewardCoins <= 260,
        ),
        isTrue,
      );
    });
    test('05 search works across a paginated catalog', () async {
      final f = OfferFixture();
      f.controller.setFilter(OfferwallFilter(search: 'Offer 299'));
      await f.controller.refresh();
      expect(f.controller.value.items.single.title, 'Offer 299');
    });
    test('06 all sorting modes use deterministic backend order', () async {
      final f = OfferFixture();
      for (final sort in OfferSort.values) {
        final filter = OfferwallFilter(sort: sort);
        f.controller.setFilter(filter);
        await f.controller.refresh();
        final expected = createOfferFixture().toList()..sort(filter.compare);
        expect(
          f.controller.value.items.map((item) => item.offerId),
          expected.take(20).map((item) => item.offerId),
        );
      }
    });
    test('07 expired offers cannot start or launch a link', () async {
      final f = OfferFixture();
      f.backend.forcedOfferStatus = OfferStatus.expired;
      await f.controller.start(f.backend.catalog.first);
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
      expect(f.launches, isEmpty);
    });
    test(
      '08 started and pending states do not imply credited reward',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        await f.controller.start(offer);
        expect(f.controller.statusOf(offer), OfferStatus.started);
        expect(f.controller.credits[offer.offerId], isNull);
        expect(f.backend.balance, 10000);
      },
    );
    test(
      '09 repeated start calls produce one backend start and launch',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        await Future.wait([
          f.controller.start(offer),
          f.controller.start(offer),
        ]);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.launches.length, 1);
        await f.controller.start(offer);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
      },
    );
    test('10 invalid offer responses are rejected', () async {
      final f = OfferFixture();
      f.backend.handler = (op, scope, args) async => f.backend.envelope(scope, {
        'items': [],
        'page': {'page': -1},
      });
      await f.controller.refresh();
      expect(f.controller.value.state, OfferLoadState.error);
      expect(f.controller.value.items, isEmpty);
    });
    test(
      '27 offline catalog exposes cached data without starting offline offers',
      () async {
        final f = OfferFixture();
        await f.controller.refresh();
        f.offline();
        await f.controller.refresh();
        expect(f.controller.value.cached, isTrue);
        expect(f.controller.value.items.length, 20);
        await f.controller.start(f.backend.catalog.first);
        expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
      },
    );
    test('32 end state prevents further requests', () async {
      final f = OfferFixture(count: 5);
      await f.controller.refresh();
      await f.controller.loadMore();
      expect(f.controller.value.hasNext, isFalse);
      expect(f.backend.calls[ShareCoinOperation.offers], 1);
    });
    test('bounded windows can traverse more than 1000 offers', () async {
      final f = OfferFixture(count: 1020);
      await f.controller.refresh();
      var found = 0;
      while (true) {
        if (f.controller.value.windowFull || !f.controller.value.hasNext) {
          found += f.controller.value.items.length;
          expect(f.controller.value.items.length, lessThanOrEqualTo(500));
          if (!f.controller.value.hasNext) break;
          await f.controller.nextWindow();
        } else {
          await f.controller.loadMore();
        }
      }
      expect(found, 1020);
    });
    test('unknown offer IDs never reach start mutation', () async {
      final f = OfferFixture();
      final unknown = createOfferFixture(1).first.toJson()
        ..['offerId'] = 'unknown-id';
      await f.controller.start(Offer.fromJson(unknown));
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
    });
    test('unsafe backend launch grants are not opened', () async {
      final f = OfferFixture();
      f.backend.launch = Uri.parse('https://untrusted.example.org/task');
      await f.controller.start(f.backend.catalog.first);
      expect(f.launches, isEmpty);
    });
    test('completion label uses a matching completed ledger transaction, not nominal reward', () async {
      final f = OfferFixture();
      final offer = f.backend.catalog.first;
      f.backend.offerTransactions[offer.offerId] = 'offer-tx';
      f.backend.ledger['offer-tx'] = ShareCoinTransaction(
        transactionId: 'offer-tx',
        userId: 'user-1',
        amount: 175,
        direction: CoinDirection.credit,
        source: CoinSource.offerReward,
        status: CoinTransactionStatus.completed,
        description: 'Test completed credit.',
        createdAt: offerTestTime,
        completedAt: offerTestTime,
        referenceId: offer.offerId,
        idempotencyKey: 'offer-credit-key',
      );
      await f.controller.refreshOffer(offer.offerId);
      expect(f.controller.statusLabel(offer), 'Completed +175 ShareCoin');
    });
    test(
      '36 malformed ledger linkage cannot confirm an offer reward',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        f.backend.offerTransactions[offer.offerId] = 'wrong-tx';
        f.backend.ledger['wrong-tx'] = p5.coinFixtureTransaction();
        await f.controller.refreshOffer(offer.offerId);
        expect(
          f.controller.credits[offer.offerId]?.state,
          isNot(RewardCreditState.credited),
        );
      },
    );
  });

  group('Part 6 reward authority', () {
    test('11 invalid reward sessions reject negative amount and impossible eligibility', () {
      expect(
        () => RewardSession(
          sessionId: 's',
          userId: 'u',
          eventId: 'e',
          idempotencyKey: 'k',
          requestKey: 'r',
          source: CoinSource.adReward,
          provider: 'p',
          targetId: 't',
          rewardCoins: -1,
          issuedAt: offerTestTime,
          expiresAt: offerTestTime.add(const Duration(minutes: 1)),
          notBefore: offerTestTime,
          availability: RewardAvailability.eligible,
          usedToday: 0,
          dailyLimit: 5,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('12 provider completion alone remains backend pending, with unchanged wallet', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.ready);
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      expect(f.rewards.value.phase, RewardPhase.rewardPending);
      expect(f.backend.balance, 10000);
    });
    test(
      '13 duplicate ad callbacks cannot submit multiple reward events',
      () async {
        final f = OfferFixture();
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      },
    );
    test('14 backend cooldown uses monotonic elapsed time and cannot be bypassed by repeated taps', () async {
      final f = OfferFixture();
      f.backend.availability = RewardAvailability.cooldown;
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.cooldown);
      f.elapsed = const Duration(seconds: 30);
      f.rewards.refreshClock();
      expect(f.rewards.value.cooldownRemaining.inSeconds, 30);
      await f.rewards.loadAd();
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward],
        1,
      );
      expect(f.ad.loads, 0);
    });
    test(
      '15 daily ad limit is a backend decision, not a local reset',
      () async {
        final f = OfferFixture();
        f.backend.availability = RewardAvailability.dailyLimit;
        f.backend.used = 5;
        await f.rewards.loadAd();
        expect(f.rewards.value.phase, RewardPhase.dailyLimit);
        expect(f.ad.loads, 0);
      },
    );
    test('16 daily claim uses a server-issued reference and backend event validation', () async {
      final f = OfferFixture();
      await f.rewards.claimDaily();
      expect(f.rewards.value.phase, RewardPhase.rewardPending);
      expect(
        f.backend.rewardEvents.values.single.providerEventId,
        'daily-server-event',
      );
      expect(f.backend.balance, 10000);
    });
    test('17 expired promotions cannot launch or credit', () async {
      final f = OfferFixture();
      final json = f.backend.promotion().toJson()
        ..['endsAt'] = offerTestTime
            .subtract(const Duration(hours: 1))
            .toIso8601String();
      await f.rewards.startPromotion(Promotion.fromJson(json));
      expect(f.launches, isEmpty);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      'promotion clicks create tracking only, never a reward event',
      () async {
        final f = OfferFixture();
        await f.rewards.startPromotion(f.backend.promotion());
        expect(f.rewards.value.phase, RewardPhase.tracking);
        expect(f.launches.length, 1);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        expect(f.backend.balance, 10000);
      },
    );
    test('backend approval requires completed matching transaction before credit display', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      f.backend.approve(f.backend.sessions.values.single);
      await f.rewards.refreshStatus();
      expect(f.rewards.value.credited, isTrue);
      expect(f.rewards.value.transaction!.amount, 150);
      expect(f.backend.calls[ShareCoinOperation.wallet], greaterThan(0));
    });
    test(
      'invalid provider signature reported by backend never credits',
      () async {
        final f = OfferFixture();
        f.backend.rejectSignature = true;
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.rewards.value.phase, RewardPhase.rejected);
        expect(f.backend.balance, 10000);
        expect(f.backend.ledger, isEmpty);
      },
    );
    test('24 reversed ledger transactions remain visible and are not approved credits', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      f.backend.approve(f.backend.sessions.values.single);
      final old = f.backend.ledger.values.single;
      f.backend.ledger[old.transactionId] = ShareCoinTransaction.fromJson(
        old.toJson()..['status'] = CoinTransactionStatus.reversed.name,
      );
      await f.rewards.refreshStatus();
      expect(f.rewards.value.phase, RewardPhase.reversed);
      expect(f.rewards.value.credited, isFalse);
    });
    test('25 and 26 negative or overflowing callback amounts cannot enter the domain', () {
      for (final amount in <int>[-1, maxShareCoinInteger + 1]) {
        expect(
          () => p5.coinFixtureReward(coins: amount),
          throwsA(isA<CoinModelException>()),
        );
      }
    });
    test('28 offline reward flow does not send events or show ads', () async {
      final f = OfferFixture()..offline();
      await f.rewards.loadAd();
      expect(f.ad.loads, 0);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      '37 stale session callbacks and completion before show are ignored',
      () async {
        final f = OfferFixture();
        await f.rewards.loadAd();
        f.ad.emit(RewardedAdEventType.completed);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed, sessionId: 'stale-session');
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        f.ad.emit(RewardedAdEventType.skipped);
        expect(f.rewards.value.phase, RewardPhase.skipped);
      },
    );
    test('38 background interruption discards callbacks but retains reconciliation identity', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.rewards.suspend();
      f.ad.emit(RewardedAdEventType.completed);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      expect(f.rewards.value.phase, RewardPhase.interrupted);
      f.rewards.resume();
      await f.rewards.refreshStatus();
      expect(f.rewards.value.phase, RewardPhase.tracking);
    });
    test('account switch rejects an old provider completion', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.backend.switchAccount(
        AccountScope(userId: 'user-2', sessionId: 'login-2'),
      );
      f.ad.emit(RewardedAdEventType.completed);
      await Future<void>.delayed(Duration.zero);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      expect(f.rewards.value.session, isNull);
    });
    test('provider load failure is not a completed ad', () async {
      final f = OfferFixture();
      f.ad.loadError = const ShareCoinException(CoinErrorCode.unavailable);
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.failed);
      expect(f.rewards.canShow, isFalse);
    });
    test('unconfigured ad adapter never simulates playback', () async {
      final f = OfferFixture();
      final coordinator = RewardCoordinator(
        service: f.service,
        autoTick: false,
      );
      addTearDown(coordinator.dispose);
      await coordinator.loadAd();
      expect(coordinator.value.phase, RewardPhase.failed);
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward] ?? 0,
        0,
      );
    });
  });

  group('Part 6 consent and receipt regressions', () {
    test(
      'a grant expiring while the user reviews consent is not launched',
      () async {
        final f = OfferFixture();
        await f.controller.start(
          f.backend.catalog.first,
          consent: (uri) async {
            f.elapsed = const Duration(minutes: 20);
            return true;
          },
        );
        expect(f.launches, isEmpty);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
      },
    );
    test(
      'late provider errors do not erase a backend-confirmed credit',
      () async {
        final f = OfferFixture();
        f.backend.approveImmediately = true;
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.rewards.value.credited, isTrue);
        f.ad.stream.addError(StateError('late provider notification'));
        expect(f.rewards.value.credited, isTrue);
      },
    );
    test('a pending provider claim cannot load a second ad session', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      await f.rewards.loadAd();
      expect(f.ad.loads, 1);
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward],
        1,
      );
    });
  });

  group('Part 6 retained account and withdrawal safety', () {
    test('18 referral model preserves server qualification and rejects impossible totals', () {
      expect(
        () => ReferralSummary(
          userId: 'u',
          referralCode: 'ref',
          invitedCount: 1,
          pendingCount: 2,
          qualifiedCount: 1,
          earnedCoins: 1,
          status: ReferralStatus.active,
          updatedAt: offerTestTime,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('19 minimum and 20 balance remain backend-policy checks', () async {
      final f = p5.CoinServiceFixture();
      await expectLater(
        f.service.requestWithdrawal(p5.coinFixtureIntent(coins: 500)),
        throwsA(p5.coinError(CoinErrorCode.minimum)),
      );
      await expectLater(
        f.service.requestWithdrawal(p5.coinFixtureIntent(coins: 11000)),
        throwsA(p5.coinError(CoinErrorCode.insufficientBalance)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      '21 and 22 duplicate withdrawal request keys still coalesce',
      () async {
        final f = p5.CoinServiceFixture();
        final intent = p5.coinFixtureIntent();
        await Future.wait([
          f.service.requestWithdrawal(intent),
          f.service.requestWithdrawal(intent),
        ]);
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        expect(f.backend.balance, 10000);
      },
    );
    test('23 all transaction source/status values round trip', () {
      for (final source in CoinSource.values) {
        for (final status in CoinTransactionStatus.values) {
          final transaction = p5.coinFixtureTransaction(
            source: source,
            status: status,
          );
          expect(
            ShareCoinTransaction.fromJson(transaction.toJson()).toJson(),
            transaction.toJson(),
          );
        }
      }
    });
    test(
      '29 local Wi-Fi remains distinct from unavailable internet rewards',
      () async {
        final f = OfferFixture()..offline();
        await f.network.refresh();
        expect(f.network.value.hasLocalCandidate, isTrue);
        expect(f.network.value.canRequestRewards, isFalse);
      },
    );
    test(
      '35 backend errors are safely mapped without exposing provider secrets',
      () {
        expect(
          ShareCoinException.fromServerCode('invalid_provider_signature').code,
          CoinErrorCode.invalidRequest,
        );
        expect(
          ShareCoinException.fromServerCode('private_stack').message,
          isNot(contains('private_stack')),
        );
      },
    );
  });

  group('Part 6 images and lifecycle UI', () {
    testWidgets('31 search debounce discards intermediate queries', (
      tester,
    ) async {
      final f = OfferFixture();
      await mountOfferwall(tester, f);
      final before = f.backend.calls[ShareCoinOperation.offers]!;
      await tester.enterText(
        find.byKey(const ValueKey('offer-search')),
        'Offer 2',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const ValueKey('offer-search')),
        'Offer 299',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(f.backend.calls[ShareCoinOperation.offers], before);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(f.controller.value.items.single.title, 'Offer 299');
      expect(f.backend.calls[ShareCoinOperation.offers], before + 1);
    });
    testWidgets(
      '33 all 300 offers can be scrolled with lazy card construction',
      (tester) async {
        final f = OfferFixture();
        await mountOfferwall(tester, f);
        for (
          var index = 0;
          index < 300 && f.controller.value.hasNext;
          index += 1
        ) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -1500),
          );
          await tester.pumpAndSettle();
        }
        expect(f.controller.value.items.length, 300);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('offer-end')),
          1800,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('offer-end')), findsOneWidget);
        expect(find.byType(OfferThumbnail).evaluate().length, lessThan(30));
      },
    );
    testWidgets('34 malformed images fall back without breaking a card', (
      tester,
    ) async {
      final policy = OfferResourcePolicy(
        imageOrigins: const ['https://assets.example.org'],
      );
      final cache = OfferThumbnailCache(
        policy: policy,
        canFetch: () => true,
        fetchBytes: (uri) async => Uint8List.fromList([1, 2, 3]),
      );
      addTearDown(cache.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfferThumbnail(
              cache: cache,
              uri: Uri.parse('https://assets.example.org/bad.png'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await cache.get(Uri.parse('https://assets.example.org/bad.png'));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    });
    testWidgets(
      'thumbnail cache is bounded and shared rather than loading 300 images at once',
      (tester) async {
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGMUyw76z8DAwMDEAAUAGxwB1s7iOpcAAAAASUVORK5CYII=',
        );
        var active = 0, maximum = 0, calls = 0;
        final cache = OfferThumbnailCache(
          policy: OfferResourcePolicy(
            imageOrigins: const ['https://assets.example.org'],
          ),
          canFetch: () => true,
          maxEntries: 2,
          parallelism: 2,
          fetchBytes: (uri) async {
            active += 1;
            calls += 1;
            if (active > maximum) maximum = active;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            active -= 1;
            return bytes;
          },
        );
        addTearDown(cache.dispose);
        await tester.runAsync(() async {
          final uri = Uri.parse('https://assets.example.org/one.png');
          final pair = await Future.wait([cache.get(uri), cache.get(uri)]);
          expect(pair.first, isNotNull);
          expect(calls, 1);
          await Future.wait(
            List.generate(
              6,
              (i) => cache.get(Uri.parse('https://assets.example.org/$i.png')),
            ),
          );
        });
        expect(maximum, lessThanOrEqualTo(2));
        expect(cache.entryCount, lessThanOrEqualTo(2));
        expect(cache.cachedBytes, lessThanOrEqualTo(cache.maxBytes));
      },
    );
    test('resource policy blocks untrusted origins and unsafe URL schemes', () {
      final policy = OfferResourcePolicy(
        linkOrigins: const ['https://offers.example.org'],
      );
      for (final input in [
        'http://offers.example.org/a',
        'https://offers.example.org.evil/a',
        'javascript:alert(1)',
        'file:///secret',
        'https://user:pass@offers.example.org/a',
      ]) {
        expect(policy.allowsLink(Uri.parse(input)), isFalse);
      }
      expect(
        policy.allowsLink(Uri.parse('https://offers.example.org/task')),
        isTrue,
      );
    });
    testWidgets(
      'detail requires tracking consent and returns no reward merely for opening',
      (tester) async {
        final f = OfferFixture(count: 1);
        await mountOfferwall(tester, f);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('open-offer-offer-0000')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('open-offer-offer-0000'),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('start-detailed-offer')),
              )
              .onPressed,
          isNull,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('offer-tracking-consent'),
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('start-detailed-offer'),
        );
        expect(find.text('Open provider destination?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(f.launches, isEmpty);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.backend.balance, 10000);
      },
    );
    testWidgets('30 disposing offer UI safely detaches ongoing reads', (
      tester,
    ) async {
      final f = OfferFixture();
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      f.backend.handler = (op, scope, args) async {
        if (op == ShareCoinOperation.offers) {
          started.complete();
          return pending.future;
        }
        return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
      };
      await tester.pumpWidget(
        MaterialApp(
          home: OfferwallScreen(service: f.service, controller: f.controller),
        ),
      );
      for (var i = 0; i < 50 && !started.isCompleted; i += 1) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(started.isCompleted, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
      pending.complete(
        f.backend.envelope(
          f.backend.scope!,
          f.backend.dataFor(
            ShareCoinOperation.offers,
            f.backend.scope!,
            OfferQuery().toJson(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'large text on a narrow screen keeps featured cards and controls usable',
      (tester) async {
        final f = OfferFixture();
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await mountOfferwall(tester, f, size: const Size(320, 740));
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '39 unified navigation retains the original file-sharing home',
      (tester) async {
        final f = OfferFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async => FileSelection(files: []),
              onToggleTheme: () {},
              shareCoinScreenBuilder: (context) => ShareCoinHomeScreen(
                service: f.service,
                offerPolicy: f.policy,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await p5.tapCoinKey(tester, 'coin-offers');
        expect(find.byKey(const ValueKey('offerwall-screen')), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('select-files-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('receive-files-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('saved-files-button')),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      '40 existing withdrawal UI remains reachable with no real-provider claim',
      (tester) async {
        final service = ShareCoinService(
          connectivity: ConnectivityService(localProbe: () async => []),
        );
        addTearDown(service.connectivity.dispose);
        addTearDown(service.dispose);
        await p5.mountCoinDashboard(tester, service);
        await p5.tapCoinKey(tester, 'coin-withdraw');
        expect(find.text('Withdrawals unavailable'), findsOneWidget);
        expect(
          find.textContaining('configuration options only'),
          findsOneWidget,
        );
      },
    );
  });
}
