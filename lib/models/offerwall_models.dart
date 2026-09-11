import 'share_coin_models.dart';

// Existing Offer, OfferStatus, OfferCategory, OfferQuery and CoinPage remain
// the domain authority. These classes add presentation/filter/session state.
class OfferwallFilter {
  OfferwallFilter({
    this.search = '',
    this.category,
    this.sort = OfferSort.recommended,
    this.platform,
    this.country,
    this.minimumReward,
    this.maximumReward,
  }) {
    OfferQuery(
      search: search,
      category: category,
      sort: sort,
      platform: platform,
      country: country,
    );
    if (minimumReward != null) coinInt(minimumReward, 'minimumReward');
    if (maximumReward != null) coinInt(maximumReward, 'maximumReward');
    if (minimumReward != null &&
        maximumReward != null &&
        minimumReward! > maximumReward!) {
      throw const CoinModelException('reward range');
    }
  }
  final String search;
  final OfferCategory? category;
  final OfferSort sort;
  final OfferPlatform? platform;
  final String? country;
  final int? minimumReward, maximumReward;
  OfferQuery query({int page = 1, int pageSize = 20, String? cursor}) =>
      OfferQuery(
        page: page,
        pageSize: pageSize,
        cursor: cursor,
        search: search,
        category: category,
        sort: sort,
        platform: platform,
        country: country,
      );
  Map<String, Object?> toJson() => <String, Object?>{
    'query': query().toJson(),
    'minimumReward': minimumReward,
    'maximumReward': maximumReward,
  };
  factory OfferwallFilter.fromJson(Map<String, dynamic> json) {
    final base = OfferQuery.fromJson(coinObject(json['query'], 'query'));
    return OfferwallFilter(
      search: base.search,
      category: base.category,
      sort: base.sort,
      platform: base.platform,
      country: base.country,
      minimumReward: json['minimumReward'] == null
          ? null
          : coinInt(json['minimumReward'], 'minimumReward'),
      maximumReward: json['maximumReward'] == null
          ? null
          : coinInt(json['maximumReward'], 'maximumReward'),
    );
  }
  bool matches(Offer offer) {
    final text = search.trim().toLowerCase();
    return (text.isEmpty ||
            '${offer.title} ${offer.description} ${offer.publisher}'
                .toLowerCase()
                .contains(text)) &&
        (category == null || category == offer.category) &&
        (platform == null || offer.platforms.contains(platform)) &&
        (country == null || offer.countries.contains(country)) &&
        (minimumReward == null || offer.rewardCoins >= minimumReward!) &&
        (maximumReward == null || offer.rewardCoins <= maximumReward!);
  }

  int compare(Offer a, Offer b) {
    final primary = switch (sort) {
      OfferSort.rewardHigh => b.rewardCoins.compareTo(a.rewardCoins),
      OfferSort.rewardLow => a.rewardCoins.compareTo(b.rewardCoins),
      OfferSort.timeShort => a.estimatedMinutes.compareTo(b.estimatedMinutes),
      OfferSort.recommended =>
        a.featured != b.featured
            ? (a.featured ? -1 : 1)
            : a.sortPriority.compareTo(b.sortPriority),
    };
    return primary == 0 ? a.offerId.compareTo(b.offerId) : primary;
  }
}

String offerCategoryLabel(OfferCategory category) => switch (category) {
  OfferCategory.installApps => 'Install Apps',
  OfferCategory.games => 'Games',
  OfferCategory.registerAndEarn => 'Register & Earn',
  OfferCategory.surveys => 'Surveys',
  OfferCategory.shopping => 'Shopping',
  OfferCategory.finance => 'Finance',
  OfferCategory.education => 'Education',
  OfferCategory.entertainment => 'Entertainment',
  OfferCategory.featured => 'Featured',
  OfferCategory.limitedTime => 'Limited Time',
};

enum OfferLoadState { idle, debouncing, loading, ready, error }

enum RewardCreditState { unconfirmed, pending, credited, rejected, reversed }

class OfferwallState {
  OfferwallState({
    required this.filter,
    Iterable<Offer> items = const [],
    this.state = OfferLoadState.idle,
    this.page,
    this.cached = false,
    this.stale = false,
    this.windowFull = false,
    this.message,
    this.serverTime,
  }) : items = List<Offer>.unmodifiable(items) {
    coinUnique(this.items.map((offer) => offer.offerId), 'displayed offer IDs');
  }
  final OfferwallFilter filter;
  final List<Offer> items;
  final OfferLoadState state;
  final PageInfo? page;
  final bool cached, stale, windowFull;
  final String? message;
  final DateTime? serverTime;
  bool get hasNext => page?.hasNext ?? false;
  bool get busy =>
      state == OfferLoadState.loading || state == OfferLoadState.debouncing;
  int get total => page?.total ?? 0;
}

class OfferRewardStatus {
  const OfferRewardStatus({required this.state, this.transaction, this.note});
  final RewardCreditState state;
  final ShareCoinTransaction? transaction;
  final String? note;
  String get label => switch (state) {
    RewardCreditState.unconfirmed => 'Reward not confirmed',
    RewardCreditState.pending => 'Reward Pending',
    RewardCreditState.credited => 'Completed ${transaction!.signedAmount}',
    RewardCreditState.rejected => 'Reward Rejected',
    RewardCreditState.reversed => 'Reward Reversed',
  };
}

enum RewardAvailability {
  eligible,
  cooldown,
  dailyLimit,
  expired,
  unavailable,
  restricted,
}

enum RewardPhase {
  idle,
  loading,
  ready,
  showing,
  completed,
  skipped,
  failed,
  tracking,
  rewardPending,
  checkingCredit,
  rewardApproved,
  cooldown,
  dailyLimit,
  rejected,
  reversed,
  interrupted,
}

enum RewardedAdEventType { ready, shown, completed, skipped, failed }

class RewardSession {
  RewardSession({
    required String sessionId,
    required String userId,
    required String eventId,
    required String idempotencyKey,
    required String requestKey,
    required this.source,
    required String provider,
    required String targetId,
    required int rewardCoins,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required DateTime notBefore,
    required this.availability,
    required int usedToday,
    required int dailyLimit,
    String? providerEventId,
    Uri? launchUrl,
  }) : sessionId = coinId(sessionId, 'sessionId'),
       userId = coinId(userId, 'userId'),
       eventId = coinId(eventId, 'eventId'),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey'),
       requestKey = coinId(requestKey, 'requestKey'),
       provider = coinId(provider, 'provider'),
       targetId = coinId(targetId, 'targetId'),
       rewardCoins = coinInt(rewardCoins, 'rewardCoins'),
       issuedAt = coinTime(issuedAt, 'issuedAt'),
       expiresAt = coinTime(expiresAt, 'expiresAt'),
       notBefore = coinTime(notBefore, 'notBefore'),
       usedToday = coinInt(usedToday, 'usedToday', max: 1000000),
       dailyLimit = coinInt(dailyLimit, 'dailyLimit', max: 1000000),
       providerEventId = coinOptionalId(providerEventId, 'providerEventId'),
       launchUrl = coinHttpsUrl(launchUrl, 'launchUrl') {
    if (!<CoinSource>{
          CoinSource.adReward,
          CoinSource.dailyReward,
          CoinSource.promotionReward,
        }.contains(source) ||
        !expiresAt.isAfter(issuedAt) ||
        notBefore.isBefore(issuedAt) ||
        !expiresAt.isAfter(notBefore)) {
      throw const CoinModelException('reward session');
    }
    if (availability == RewardAvailability.eligible &&
        (rewardCoins == 0 || dailyLimit == 0 || usedToday >= dailyLimit)) {
      throw const CoinModelException('reward eligibility');
    }
    if (source == CoinSource.dailyReward &&
        availability == RewardAvailability.eligible &&
        providerEventId == null) {
      throw const CoinModelException('daily claim reference');
    }
  }
  final String sessionId,
      userId,
      eventId,
      idempotencyKey,
      requestKey,
      provider,
      targetId;
  final String? providerEventId;
  final CoinSource source;
  final RewardAvailability availability;
  final int rewardCoins, usedToday, dailyLimit;
  final DateTime issuedAt, expiresAt, notBefore;
  final Uri? launchUrl;
  bool usableAt(DateTime serverEstimate) =>
      availability == RewardAvailability.eligible &&
      !serverEstimate.isBefore(notBefore) &&
      serverEstimate.isBefore(expiresAt);
  factory RewardSession.fromJson(Map<String, dynamic> j) => RewardSession(
    sessionId: coinId(j['sessionId'], 'sessionId'),
    userId: coinId(j['userId'], 'userId'),
    eventId: coinId(j['eventId'], 'eventId'),
    idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
    requestKey: coinId(j['requestKey'], 'requestKey'),
    source: coinEnum(j['source'], CoinSource.values, 'source'),
    provider: coinId(j['provider'], 'provider'),
    targetId: coinId(j['targetId'], 'targetId'),
    rewardCoins: coinInt(j['rewardCoins'], 'rewardCoins'),
    issuedAt: coinTime(j['issuedAt'], 'issuedAt'),
    expiresAt: coinTime(j['expiresAt'], 'expiresAt'),
    notBefore: coinTime(j['notBefore'], 'notBefore'),
    availability: coinEnum(
      j['availability'],
      RewardAvailability.values,
      'availability',
    ),
    usedToday: coinInt(j['usedToday'], 'usedToday', max: 1000000),
    dailyLimit: coinInt(j['dailyLimit'], 'dailyLimit', max: 1000000),
    providerEventId: coinOptionalId(j['providerEventId'], 'providerEventId'),
    launchUrl: coinHttpsUrl(j['launchUrl'], 'launchUrl'),
  );
  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'userId': userId,
    'eventId': eventId,
    'idempotencyKey': idempotencyKey,
    'requestKey': requestKey,
    'source': source.name,
    'provider': provider,
    'targetId': targetId,
    'rewardCoins': rewardCoins,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'notBefore': notBefore.toIso8601String(),
    'availability': availability.name,
    'usedToday': usedToday,
    'dailyLimit': dailyLimit,
    'providerEventId': providerEventId,
    'launchUrl': launchUrl?.toString(),
  };
}

class RewardedAdEvent {
  RewardedAdEvent({
    required String sessionId,
    required this.type,
    String? providerEventId,
  }) : sessionId = coinId(sessionId, 'sessionId'),
       providerEventId = coinOptionalId(providerEventId, 'providerEventId');
  final String sessionId;
  final RewardedAdEventType type;
  final String? providerEventId;
}

class RewardViewState {
  const RewardViewState({
    this.phase = RewardPhase.idle,
    this.session,
    this.event,
    this.transaction,
    this.message = 'Choose an action. Rewards require backend validation.',
    this.cooldownRemaining = Duration.zero,
  });
  final RewardPhase phase;
  final RewardSession? session;
  final RewardEvent? event;
  final ShareCoinTransaction? transaction;
  final String message;
  final Duration cooldownRemaining;
  bool get busy => <RewardPhase>{
    RewardPhase.loading,
    RewardPhase.showing,
    RewardPhase.completed,
    RewardPhase.checkingCredit,
  }.contains(phase);
  bool get credited =>
      phase == RewardPhase.rewardApproved &&
      transaction?.status == CoinTransactionStatus.completed;
}

class OfferLaunchGrant {
  OfferLaunchGrant({
    required String startId,
    required String offerId,
    required String userId,
    required this.platform,
    required Uri url,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) : startId = coinId(startId, 'startId'),
       offerId = coinId(offerId, 'offerId'),
       userId = coinId(userId, 'userId'),
       url = coinHttpsUrl(url, 'launchUrl')!,
       issuedAt = coinTime(issuedAt, 'issuedAt'),
       expiresAt = coinTime(expiresAt, 'expiresAt') {
    if (!expiresAt.isAfter(issuedAt)) {
      throw const CoinModelException('launch expiry');
    }
  }
  final String startId, offerId, userId;
  final OfferPlatform platform;
  final Uri url;
  final DateTime issuedAt, expiresAt;
  factory OfferLaunchGrant.fromJson(Map<String, dynamic> j) => OfferLaunchGrant(
    startId: coinId(j['startId'], 'startId'),
    offerId: coinId(j['offerId'], 'offerId'),
    userId: coinId(j['userId'], 'userId'),
    platform: coinEnum(j['platform'], OfferPlatform.values, 'platform'),
    url:
        coinHttpsUrl(j['launchUrl'], 'launchUrl') ??
        (throw const CoinModelException('launchUrl')),
    issuedAt: coinTime(j['issuedAt'], 'issuedAt'),
    expiresAt: coinTime(j['expiresAt'], 'expiresAt'),
  );
  Map<String, Object?> toJson() => {
    'startId': startId,
    'offerId': offerId,
    'userId': userId,
    'platform': platform.name,
    'launchUrl': url.toString(),
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
}
