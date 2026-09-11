import 'dart:convert';
import 'dart:io';

const int maxShareCoinInteger = 9007199254740991;

class CoinModelException implements Exception {
  const CoinModelException(this.field);
  final String field;
  @override
  String toString() => 'Invalid ShareCoin data: $field.';
}

int coinInt(
  Object? value,
  String field, {
  int min = 0,
  int max = maxShareCoinInteger,
}) {
  if (value is! int || value < min || value > max) {
    throw CoinModelException(field);
  }
  return value;
}

String coinText(Object? value, String field, {int max = 240}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value != value.trim() ||
      utf8.encode(value).length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
      RegExp('[\u202a-\u202e\u2066-\u2069]').hasMatch(value)) {
    throw CoinModelException(field);
  }
  return value;
}

String coinId(Object? value, String field) {
  final id = coinText(value, field, max: 128);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(id)) {
    throw CoinModelException(field);
  }
  return id;
}

String? coinOptionalId(Object? value, String field) =>
    value == null ? null : coinId(value, field);
bool coinBool(Object? value, String field) {
  if (value is! bool) throw CoinModelException(field);
  return value;
}

Map<String, dynamic> coinObject(Object? value, String field) {
  if (value is! Map<String, dynamic>) throw CoinModelException(field);
  return value;
}

List<dynamic> coinArray(Object? value, String field, {int max = 100}) {
  if (value is! List || value.length > max) throw CoinModelException(field);
  return value;
}

T coinEnum<T extends Enum>(Object? value, List<T> values, String field) {
  for (final entry in values) {
    if (entry.name == value) return entry;
  }
  throw CoinModelException(field);
}

DateTime coinTime(Object? value, String field) {
  if (value is DateTime) {
    if (!value.isUtc || value.year < 2000 || value.year > 2199) {
      throw CoinModelException(field);
    }
    return value;
  }
  if (value is! String) throw CoinModelException(field);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$',
  ).firstMatch(value);
  final time = DateTime.tryParse(value);
  if (match == null ||
      time == null ||
      time.year != int.parse(match[1]!) ||
      time.month != int.parse(match[2]!) ||
      time.day != int.parse(match[3]!) ||
      time.hour != int.parse(match[4]!) ||
      time.minute != int.parse(match[5]!) ||
      time.second != int.parse(match[6]!)) {
    throw CoinModelException(field);
  }
  return coinTime(time, field);
}

DateTime? coinOptionalTime(Object? value, String field) =>
    value == null ? null : coinTime(value, field);

Uri? coinHttpsUrl(Object? value, String field) {
  if (value == null) return null;
  final text = value is Uri
      ? value.toString()
      : coinText(value, field, max: 2048);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.port != 443 ||
      InternetAddress.tryParse(uri.host) != null ||
      !uri.host.contains('.') ||
      uri.host.endsWith('.local') ||
      uri.host.endsWith('.localhost') ||
      !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(uri.host)) {
    throw CoinModelException(field);
  }
  return uri;
}

Map<String, String> coinMetadata(Object? value) {
  if (value == null) return const <String, String>{};
  final map = coinObject(value, 'metadata');
  const allowed = <String>{
    'placement',
    'campaign',
    'offer',
    'providerReference',
    'variant',
    'platform',
    'country',
    'trace',
  };
  if (map.length > allowed.length) throw const CoinModelException('metadata');
  final result = <String, String>{};
  for (final entry in map.entries) {
    if (!allowed.contains(entry.key)) {
      throw const CoinModelException('metadata key');
    }
    result[entry.key] = coinId(entry.value, 'metadata value');
  }
  return Map<String, String>.unmodifiable(result);
}

List<String> coinTextList(
  Object? value,
  String field, {
  int max = 20,
  int textMax = 500,
}) => List<String>.unmodifiable(
  coinArray(
    value,
    field,
    max: max,
  ).map((item) => coinText(item, field, max: textMax)),
);

void coinUnique(Iterable<String> values, String field) {
  final list = values.toList();
  if (list.toSet().length != list.length) throw CoinModelException(field);
}

int coinCheckedInt(BigInt value, String field) {
  if (value.isNegative || value > BigInt.from(maxShareCoinInteger)) {
    throw CoinModelException(field);
  }
  return value.toInt();
}

enum CoinDirection { credit, debit }

enum CoinSource {
  adReward,
  offerReward,
  promotionReward,
  referralReward,
  dailyReward,
  bonus,
  withdrawal,
  reversal,
  administrativeAdjustment,
}

enum CoinTransactionStatus {
  pending,
  approved,
  completed,
  rejected,
  reversed,
  cancelled,
}

enum RewardEventStatus {
  created,
  submitted,
  pending,
  approved,
  rejected,
  cancelled,
}

enum WithdrawalStatus {
  requested,
  pending,
  approved,
  processing,
  paid,
  rejected,
  cancelled,
}

enum PayoutMethod { bkash, nagad, rocket, paypal, bank }

enum OfferStatus {
  available,
  started,
  pending,
  completed,
  rejected,
  expired,
  unavailable,
}

enum OfferCategory {
  installApps,
  games,
  registerAndEarn,
  surveys,
  shopping,
  finance,
  education,
  entertainment,
  featured,
  limitedTime,
}

enum OfferPlatform { android, ios }

enum OfferSort { recommended, rewardHigh, rewardLow, timeShort }

enum PromotionStatus {
  scheduled,
  active,
  paused,
  expired,
  completed,
  unavailable,
}

class ShareCoinBalance {
  ShareCoinBalance({
    required String userId,
    required int available,
    required int pending,
    required int lifetimeEarned,
    required int lifetimeWithdrawn,
    required int lifetimeSpent,
    required DateTime updatedAt,
    required String version,
    String unit = 'ShareCoin',
  }) : userId = coinId(userId, 'userId'),
       available = coinInt(available, 'available'),
       pending = coinInt(pending, 'pending'),
       lifetimeEarned = coinInt(lifetimeEarned, 'lifetimeEarned'),
       lifetimeWithdrawn = coinInt(lifetimeWithdrawn, 'lifetimeWithdrawn'),
       lifetimeSpent = coinInt(lifetimeSpent, 'lifetimeSpent'),
       updatedAt = coinTime(updatedAt, 'updatedAt'),
       version = coinId(version, 'version'),
       unit = coinText(unit, 'unit') {
    if (unit != 'ShareCoin') throw const CoinModelException('unit');
    coinCheckedInt(
      BigInt.from(available) + BigInt.from(pending),
      'total balance',
    );
  }
  final String userId, version, unit;
  final int available,
      pending,
      lifetimeEarned,
      lifetimeWithdrawn,
      lifetimeSpent;
  final DateTime updatedAt;
  factory ShareCoinBalance.fromJson(Map<String, dynamic> j) => ShareCoinBalance(
    userId: coinId(j['userId'], 'userId'),
    available: coinInt(j['available'], 'available'),
    pending: coinInt(j['pending'], 'pending'),
    lifetimeEarned: coinInt(j['lifetimeEarned'], 'lifetimeEarned'),
    lifetimeWithdrawn: coinInt(j['lifetimeWithdrawn'], 'lifetimeWithdrawn'),
    lifetimeSpent: coinInt(j['lifetimeSpent'], 'lifetimeSpent'),
    updatedAt: coinTime(j['updatedAt'], 'updatedAt'),
    version: coinId(j['version'], 'version'),
    unit: coinText(j['unit'], 'unit'),
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'available': available,
    'pending': pending,
    'lifetimeEarned': lifetimeEarned,
    'lifetimeWithdrawn': lifetimeWithdrawn,
    'lifetimeSpent': lifetimeSpent,
    'updatedAt': updatedAt.toIso8601String(),
    'version': version,
    'unit': unit,
  };
}

class ShareCoinTransaction {
  ShareCoinTransaction({
    required String transactionId,
    required String userId,
    required int amount,
    required this.direction,
    required this.source,
    required this.status,
    required String description,
    required DateTime createdAt,
    DateTime? completedAt,
    String? referenceId,
    required String idempotencyKey,
    Map<String, String> metadata = const {},
  }) : transactionId = coinId(transactionId, 'transactionId'),
       userId = coinId(userId, 'userId'),
       amount = coinInt(amount, 'amount', min: 1),
       description = coinText(description, 'description', max: 1000),
       createdAt = coinTime(createdAt, 'createdAt'),
       completedAt = coinOptionalTime(completedAt, 'completedAt'),
       referenceId = coinOptionalId(referenceId, 'referenceId'),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey'),
       metadata = coinMetadata(metadata) {
    if (completedAt != null && completedAt.isBefore(createdAt)) {
      throw const CoinModelException('completedAt');
    }
    if (status == CoinTransactionStatus.completed && completedAt == null) {
      throw const CoinModelException('completedAt');
    }
  }
  final String transactionId, userId, description, idempotencyKey;
  final String? referenceId;
  final int amount;
  final CoinDirection direction;
  final CoinSource source;
  final CoinTransactionStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final Map<String, String> metadata;
  String get signedAmount =>
      '${direction == CoinDirection.credit ? '+' : '-'}$amount ShareCoin';
  factory ShareCoinTransaction.fromJson(Map<String, dynamic> j) =>
      ShareCoinTransaction(
        transactionId: coinId(j['transactionId'], 'transactionId'),
        userId: coinId(j['userId'], 'userId'),
        amount: coinInt(j['amount'], 'amount', min: 1),
        direction: coinEnum(j['direction'], CoinDirection.values, 'direction'),
        source: coinEnum(j['source'], CoinSource.values, 'source'),
        status: coinEnum(j['status'], CoinTransactionStatus.values, 'status'),
        description: coinText(j['description'], 'description', max: 1000),
        createdAt: coinTime(j['createdAt'], 'createdAt'),
        completedAt: coinOptionalTime(j['completedAt'], 'completedAt'),
        referenceId: coinOptionalId(j['referenceId'], 'referenceId'),
        idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
        metadata: coinMetadata(j['metadata']),
      );
  Map<String, Object?> toJson() => {
    'transactionId': transactionId,
    'userId': userId,
    'amount': amount,
    'direction': direction.name,
    'source': source.name,
    'status': status.name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'referenceId': referenceId,
    'idempotencyKey': idempotencyKey,
    'metadata': metadata,
  };
}

class RewardEvent {
  RewardEvent({
    required String eventId,
    required String userId,
    required this.source,
    required String provider,
    required String providerEventId,
    required String targetId,
    required int requestedCoins,
    required DateTime occurredAt,
    required this.status,
    required String idempotencyKey,
    String? transactionId,
    Map<String, String> metadata = const {},
  }) : eventId = coinId(eventId, 'eventId'),
       userId = coinId(userId, 'userId'),
       provider = coinId(provider, 'provider'),
       providerEventId = coinId(providerEventId, 'providerEventId'),
       targetId = coinId(targetId, 'targetId'),
       requestedCoins = coinInt(requestedCoins, 'requestedCoins', min: 1),
       occurredAt = coinTime(occurredAt, 'occurredAt'),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey'),
       transactionId = coinOptionalId(transactionId, 'transactionId'),
       metadata = coinMetadata(metadata) {
    if (<CoinSource>{
      CoinSource.withdrawal,
      CoinSource.reversal,
      CoinSource.administrativeAdjustment,
    }.contains(source)) {
      throw const CoinModelException('reward source');
    }
    if (status == RewardEventStatus.approved && transactionId == null) {
      throw const CoinModelException('approved transactionId');
    }
    if (status != RewardEventStatus.approved && transactionId != null) {
      throw const CoinModelException('unexpected transactionId');
    }
  }
  final String eventId,
      userId,
      provider,
      providerEventId,
      targetId,
      idempotencyKey;
  final String? transactionId;
  final CoinSource source;
  final RewardEventStatus status;
  final int requestedCoins;
  final DateTime occurredAt;
  final Map<String, String> metadata;
  String get actionKey => '${source.name}|$provider|$providerEventId|$targetId';
  factory RewardEvent.fromJson(Map<String, dynamic> j) => RewardEvent(
    eventId: coinId(j['eventId'], 'eventId'),
    userId: coinId(j['userId'], 'userId'),
    source: coinEnum(j['source'], CoinSource.values, 'source'),
    provider: coinId(j['provider'], 'provider'),
    providerEventId: coinId(j['providerEventId'], 'providerEventId'),
    targetId: coinId(j['targetId'], 'targetId'),
    requestedCoins: coinInt(j['requestedCoins'], 'requestedCoins', min: 1),
    occurredAt: coinTime(j['occurredAt'], 'occurredAt'),
    status: coinEnum(j['status'], RewardEventStatus.values, 'status'),
    idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
    transactionId: coinOptionalId(j['transactionId'], 'transactionId'),
    metadata: coinMetadata(j['metadata']),
  );
  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'userId': userId,
    'source': source.name,
    'provider': provider,
    'providerEventId': providerEventId,
    'targetId': targetId,
    'requestedCoins': requestedCoins,
    'occurredAt': occurredAt.toIso8601String(),
    'status': status.name,
    'idempotencyKey': idempotencyKey,
    'transactionId': transactionId,
    'metadata': metadata,
  };
}

class CoinConversionRate {
  CoinConversionRate({
    required int coinUnits,
    required int minorUnits,
    required String currency,
    int scale = 2,
  }) : coinUnits = coinInt(coinUnits, 'coinUnits', min: 1),
       minorUnits = coinInt(minorUnits, 'minorUnits', min: 1),
       currency = coinText(currency, 'currency', max: 3),
       scale = coinInt(scale, 'scale', max: 6) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const CoinModelException('currency');
    }
  }
  final int coinUnits, minorUnits, scale;
  final String currency;
  int grossMinor(int coins) => coinCheckedInt(
    BigInt.from(coinInt(coins, 'coins')) *
        BigInt.from(minorUnits) ~/
        BigInt.from(coinUnits),
    'converted payout',
  );
  String formatMinor(int amount) {
    coinInt(amount, 'money');
    if (scale == 0) return '$amount $currency';
    final digits = amount.toString().padLeft(scale + 1, '0');
    return '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)} $currency';
  }

  factory CoinConversionRate.fromJson(Map<String, dynamic> j) =>
      CoinConversionRate(
        coinUnits: coinInt(j['coinUnits'], 'coinUnits', min: 1),
        minorUnits: coinInt(j['minorUnits'], 'minorUnits', min: 1),
        currency: coinText(j['currency'], 'currency', max: 3),
        scale: coinInt(j['scale'], 'scale', max: 6),
      );
  Map<String, Object?> toJson() => {
    'coinUnits': coinUnits,
    'minorUnits': minorUnits,
    'currency': currency,
    'scale': scale,
  };
}

class PayoutMethodConfig {
  PayoutMethodConfig({
    required this.method,
    required this.enabled,
    required this.providerConnected,
    required int feeMinor,
    String? destinationReference,
    String? maskedDestination,
  }) : feeMinor = coinInt(feeMinor, 'feeMinor'),
       destinationReference = coinOptionalId(
         destinationReference,
         'destinationReference',
       ),
       maskedDestination = maskedDestination == null
           ? null
           : coinText(maskedDestination, 'maskedDestination', max: 100) {
    if (maskedDestination != null && !maskedDestination.contains('*')) {
      throw const CoinModelException('destination must be masked');
    }
    if ((destinationReference == null) != (maskedDestination == null)) {
      throw const CoinModelException('destination configuration');
    }
  }
  final PayoutMethod method;
  final bool enabled, providerConnected;
  final int feeMinor;
  final String? destinationReference, maskedDestination;
  bool get usable =>
      enabled && providerConnected && destinationReference != null;
  factory PayoutMethodConfig.fromJson(Map<String, dynamic> j) =>
      PayoutMethodConfig(
        method: coinEnum(j['method'], PayoutMethod.values, 'method'),
        enabled: coinBool(j['enabled'], 'enabled'),
        providerConnected: coinBool(
          j['providerConnected'],
          'providerConnected',
        ),
        feeMinor: coinInt(j['feeMinor'], 'feeMinor'),
        destinationReference: coinOptionalId(
          j['destinationReference'],
          'destinationReference',
        ),
        maskedDestination: j['maskedDestination'] == null
            ? null
            : coinText(j['maskedDestination'], 'maskedDestination', max: 100),
      );
  Map<String, Object?> toJson() => {
    'method': method.name,
    'enabled': enabled,
    'providerConnected': providerConnected,
    'feeMinor': feeMinor,
    'destinationReference': destinationReference,
    'maskedDestination': maskedDestination,
  };
}

class WithdrawalPolicy {
  WithdrawalPolicy({
    required String userId,
    required String version,
    required int minimumCoins,
    required this.rate,
    required Iterable<PayoutMethodConfig> methods,
    required Iterable<String> activeRequestIds,
  }) : userId = coinId(userId, 'userId'),
       version = coinId(version, 'version'),
       minimumCoins = coinInt(minimumCoins, 'minimumCoins', min: 1),
       methods = List<PayoutMethodConfig>.unmodifiable(methods),
       activeRequestIds = List<String>.unmodifiable(
         activeRequestIds.map((id) => coinId(id, 'activeRequestId')),
       ) {
    if (this.methods.length > 5 || this.activeRequestIds.length > 20) {
      throw const CoinModelException('withdrawal policy size');
    }
    coinUnique(this.methods.map((m) => m.method.name), 'payout methods');
    coinUnique(this.activeRequestIds, 'active withdrawals');
  }
  final String userId, version;
  final int minimumCoins;
  final CoinConversionRate rate;
  final List<PayoutMethodConfig> methods;
  final List<String> activeRequestIds;
  factory WithdrawalPolicy.fromJson(Map<String, dynamic> j) => WithdrawalPolicy(
    userId: coinId(j['userId'], 'userId'),
    version: coinId(j['version'], 'version'),
    minimumCoins: coinInt(j['minimumCoins'], 'minimumCoins', min: 1),
    rate: CoinConversionRate.fromJson(coinObject(j['rate'], 'rate')),
    methods: coinArray(
      j['methods'],
      'methods',
      max: 5,
    ).map((m) => PayoutMethodConfig.fromJson(coinObject(m, 'method'))),
    activeRequestIds: coinArray(
      j['activeRequestIds'],
      'activeRequestIds',
      max: 20,
    ).map((id) => coinId(id, 'activeRequestId')),
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'version': version,
    'minimumCoins': minimumCoins,
    'rate': rate.toJson(),
    'methods': methods.map((m) => m.toJson()).toList(),
    'activeRequestIds': activeRequestIds,
  };
}

class WithdrawalIntent {
  WithdrawalIntent({
    required String userId,
    required int coins,
    required this.method,
    required String destinationReference,
    required String policyVersion,
    required int expectedFeeMinor,
    required int expectedFinalMinor,
    required String idempotencyKey,
  }) : userId = coinId(userId, 'userId'),
       coins = coinInt(coins, 'coins', min: 1),
       destinationReference = coinId(
         destinationReference,
         'destinationReference',
       ),
       policyVersion = coinId(policyVersion, 'policyVersion'),
       expectedFeeMinor = coinInt(expectedFeeMinor, 'expectedFeeMinor'),
       expectedFinalMinor = coinInt(expectedFinalMinor, 'expectedFinalMinor'),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey');
  final String userId, destinationReference, policyVersion, idempotencyKey;
  final int coins, expectedFeeMinor, expectedFinalMinor;
  final PayoutMethod method;
  Map<String, Object?> toJson() => {
    'userId': userId,
    'coins': coins,
    'method': method.name,
    'destinationReference': destinationReference,
    'policyVersion': policyVersion,
    'expectedFeeMinor': expectedFeeMinor,
    'expectedFinalMinor': expectedFinalMinor,
    'idempotencyKey': idempotencyKey,
  };
  factory WithdrawalIntent.fromJson(Map<String, dynamic> j) => WithdrawalIntent(
    userId: coinId(j['userId'], 'userId'),
    coins: coinInt(j['coins'], 'coins', min: 1),
    method: coinEnum(j['method'], PayoutMethod.values, 'method'),
    destinationReference: coinId(
      j['destinationReference'],
      'destinationReference',
    ),
    policyVersion: coinId(j['policyVersion'], 'policyVersion'),
    expectedFeeMinor: coinInt(j['expectedFeeMinor'], 'expectedFeeMinor'),
    expectedFinalMinor: coinInt(j['expectedFinalMinor'], 'expectedFinalMinor'),
    idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
  );
}

class WithdrawalRequest {
  WithdrawalRequest({
    required String withdrawalId,
    required String userId,
    required int requestedCoins,
    required this.rate,
    required int feeMinor,
    required int finalPayoutMinor,
    required this.method,
    required String maskedDestination,
    required this.status,
    required DateTime requestedAt,
    required DateTime updatedAt,
    String? serverReference,
    String? rejectionReason,
    required String idempotencyKey,
  }) : withdrawalId = coinId(withdrawalId, 'withdrawalId'),
       userId = coinId(userId, 'userId'),
       requestedCoins = coinInt(requestedCoins, 'requestedCoins', min: 1),
       feeMinor = coinInt(feeMinor, 'feeMinor'),
       finalPayoutMinor = coinInt(finalPayoutMinor, 'finalPayoutMinor'),
       maskedDestination = coinText(
         maskedDestination,
         'maskedDestination',
         max: 100,
       ),
       requestedAt = coinTime(requestedAt, 'requestedAt'),
       updatedAt = coinTime(updatedAt, 'updatedAt'),
       serverReference = coinOptionalId(serverReference, 'serverReference'),
       rejectionReason = rejectionReason == null
           ? null
           : coinText(rejectionReason, 'rejectionReason', max: 500),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey') {
    if (!maskedDestination.contains('*') ||
        updatedAt.isBefore(requestedAt) ||
        feeMinor > rate.grossMinor(requestedCoins) ||
        finalPayoutMinor != rate.grossMinor(requestedCoins) - feeMinor) {
      throw const CoinModelException('withdrawal totals/dates');
    }
    if (status == WithdrawalStatus.paid && serverReference == null) {
      throw const CoinModelException('paid serverReference');
    }
    if (status == WithdrawalStatus.rejected && rejectionReason == null) {
      throw const CoinModelException('rejectionReason');
    }
  }
  final String withdrawalId, userId, maskedDestination, idempotencyKey;
  final String? serverReference, rejectionReason;
  final int requestedCoins, feeMinor, finalPayoutMinor;
  final CoinConversionRate rate;
  final PayoutMethod method;
  final WithdrawalStatus status;
  final DateTime requestedAt, updatedAt;
  bool get active => <WithdrawalStatus>{
    WithdrawalStatus.requested,
    WithdrawalStatus.pending,
    WithdrawalStatus.approved,
    WithdrawalStatus.processing,
  }.contains(status);
  bool canTransitionTo(WithdrawalStatus next) {
    if (next == status) return true;
    return switch (status) {
      WithdrawalStatus.requested => <WithdrawalStatus>{
        WithdrawalStatus.pending,
        WithdrawalStatus.approved,
        WithdrawalStatus.processing,
        WithdrawalStatus.paid,
        WithdrawalStatus.rejected,
        WithdrawalStatus.cancelled,
      }.contains(next),
      WithdrawalStatus.pending => <WithdrawalStatus>{
        WithdrawalStatus.approved,
        WithdrawalStatus.processing,
        WithdrawalStatus.paid,
        WithdrawalStatus.rejected,
        WithdrawalStatus.cancelled,
      }.contains(next),
      WithdrawalStatus.approved =>
        next == WithdrawalStatus.processing ||
            next == WithdrawalStatus.paid ||
            next == WithdrawalStatus.rejected,
      WithdrawalStatus.processing =>
        next == WithdrawalStatus.paid || next == WithdrawalStatus.rejected,
      WithdrawalStatus.paid ||
      WithdrawalStatus.rejected ||
      WithdrawalStatus.cancelled => false,
    };
  }

  factory WithdrawalRequest.fromJson(Map<String, dynamic> j) =>
      WithdrawalRequest(
        withdrawalId: coinId(j['withdrawalId'], 'withdrawalId'),
        userId: coinId(j['userId'], 'userId'),
        requestedCoins: coinInt(j['requestedCoins'], 'requestedCoins', min: 1),
        rate: CoinConversionRate.fromJson(coinObject(j['rate'], 'rate')),
        feeMinor: coinInt(j['feeMinor'], 'feeMinor'),
        finalPayoutMinor: coinInt(j['finalPayoutMinor'], 'finalPayoutMinor'),
        method: coinEnum(j['method'], PayoutMethod.values, 'method'),
        maskedDestination: coinText(
          j['maskedDestination'],
          'maskedDestination',
          max: 100,
        ),
        status: coinEnum(j['status'], WithdrawalStatus.values, 'status'),
        requestedAt: coinTime(j['requestedAt'], 'requestedAt'),
        updatedAt: coinTime(j['updatedAt'], 'updatedAt'),
        serverReference: coinOptionalId(
          j['serverReference'],
          'serverReference',
        ),
        rejectionReason: j['rejectionReason'] == null
            ? null
            : coinText(j['rejectionReason'], 'rejectionReason', max: 500),
        idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
      );
  Map<String, Object?> toJson() => {
    'withdrawalId': withdrawalId,
    'userId': userId,
    'requestedCoins': requestedCoins,
    'rate': rate.toJson(),
    'feeMinor': feeMinor,
    'finalPayoutMinor': finalPayoutMinor,
    'method': method.name,
    'maskedDestination': maskedDestination,
    'status': status.name,
    'requestedAt': requestedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'serverReference': serverReference,
    'rejectionReason': rejectionReason,
    'idempotencyKey': idempotencyKey,
  };
}

class AdConfiguration {
  AdConfiguration({
    required this.rewardedEnabled,
    required this.bannerEnabled,
    required this.interstitialEnabled,
    required int cooldownSeconds,
    required int dailyLimit,
    required this.premium,
    String? provider,
    Map<String, String> units = const {},
  }) : cooldownSeconds = coinInt(
         cooldownSeconds,
         'cooldownSeconds',
         max: 86400,
       ),
       dailyLimit = coinInt(dailyLimit, 'dailyLimit', max: 1000),
       provider = coinOptionalId(provider, 'provider'),
       units = Map<String, String>.unmodifiable(units) {
    if (units.length > 3 ||
        units.keys.any(
          (k) => !<String>{'rewarded', 'banner', 'interstitial'}.contains(k),
        )) {
      throw const CoinModelException('ad units');
    }
    for (final unit in units.values) {
      coinText(unit, 'ad unit', max: 160);
    }
    if ((rewardedEnabled || bannerEnabled || interstitialEnabled) &&
        provider == null) {
      throw const CoinModelException('ad provider');
    }
    if (rewardedEnabled &&
        (dailyLimit == 0 || !units.containsKey('rewarded'))) {
      throw const CoinModelException('rewarded configuration');
    }
    if (bannerEnabled && !units.containsKey('banner') ||
        interstitialEnabled && !units.containsKey('interstitial')) {
      throw const CoinModelException('ad placement');
    }
  }
  factory AdConfiguration.disabled() => AdConfiguration(
    rewardedEnabled: false,
    bannerEnabled: false,
    interstitialEnabled: false,
    cooldownSeconds: 0,
    dailyLimit: 0,
    premium: false,
  );
  final bool rewardedEnabled, bannerEnabled, interstitialEnabled, premium;
  final int cooldownSeconds, dailyLimit;
  final String? provider;
  final Map<String, String> units;
  bool get adsAllowed =>
      !premium && (rewardedEnabled || bannerEnabled || interstitialEnabled);
  factory AdConfiguration.fromJson(Map<String, dynamic> j) => AdConfiguration(
    rewardedEnabled: coinBool(j['rewardedEnabled'], 'rewardedEnabled'),
    bannerEnabled: coinBool(j['bannerEnabled'], 'bannerEnabled'),
    interstitialEnabled: coinBool(
      j['interstitialEnabled'],
      'interstitialEnabled',
    ),
    cooldownSeconds: coinInt(
      j['cooldownSeconds'],
      'cooldownSeconds',
      max: 86400,
    ),
    dailyLimit: coinInt(j['dailyLimit'], 'dailyLimit', max: 1000),
    premium: coinBool(j['premium'], 'premium'),
    provider: coinOptionalId(j['provider'], 'provider'),
    units: coinObject(
      j['units'],
      'units',
    ).map((key, value) => MapEntry(key, coinText(value, 'ad unit', max: 160))),
  );
  Map<String, Object?> toJson() => {
    'rewardedEnabled': rewardedEnabled,
    'bannerEnabled': bannerEnabled,
    'interstitialEnabled': interstitialEnabled,
    'cooldownSeconds': cooldownSeconds,
    'dailyLimit': dailyLimit,
    'premium': premium,
    'provider': provider,
    'units': units,
  };
}

class Promotion {
  Promotion({
    required String campaignId,
    required String title,
    required String description,
    required String advertiser,
    required String cta,
    required int rewardCoins,
    required DateTime startsAt,
    required DateTime endsAt,
    required this.status,
    required String trackingId,
    Uri? imageUrl,
  }) : campaignId = coinId(campaignId, 'campaignId'),
       title = coinText(title, 'title'),
       description = coinText(description, 'description', max: 4000),
       advertiser = coinText(advertiser, 'advertiser'),
       cta = coinText(cta, 'cta', max: 80),
       rewardCoins = coinInt(rewardCoins, 'rewardCoins'),
       startsAt = coinTime(startsAt, 'startsAt'),
       endsAt = coinTime(endsAt, 'endsAt'),
       trackingId = coinId(trackingId, 'trackingId'),
       imageUrl = coinHttpsUrl(imageUrl, 'imageUrl') {
    if (!endsAt.isAfter(startsAt)) {
      throw const CoinModelException('campaign dates');
    }
  }
  final String campaignId, title, description, advertiser, cta, trackingId;
  final int rewardCoins;
  final Uri? imageUrl;
  final DateTime startsAt, endsAt;
  final PromotionStatus status;
  bool availableAt(DateTime serverTime) =>
      status == PromotionStatus.active &&
      !serverTime.isBefore(startsAt) &&
      serverTime.isBefore(endsAt);
  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
    campaignId: coinId(j['campaignId'], 'campaignId'),
    title: coinText(j['title'], 'title'),
    description: coinText(j['description'], 'description', max: 4000),
    advertiser: coinText(j['advertiser'], 'advertiser'),
    cta: coinText(j['cta'], 'cta', max: 80),
    rewardCoins: coinInt(j['rewardCoins'], 'rewardCoins'),
    startsAt: coinTime(j['startsAt'], 'startsAt'),
    endsAt: coinTime(j['endsAt'], 'endsAt'),
    status: coinEnum(j['status'], PromotionStatus.values, 'status'),
    trackingId: coinId(j['trackingId'], 'trackingId'),
    imageUrl: coinHttpsUrl(j['imageUrl'], 'imageUrl'),
  );
  Map<String, Object?> toJson() => {
    'campaignId': campaignId,
    'title': title,
    'description': description,
    'advertiser': advertiser,
    'cta': cta,
    'rewardCoins': rewardCoins,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'status': status.name,
    'trackingId': trackingId,
    'imageUrl': imageUrl?.toString(),
  };
}

class Offer {
  Offer({
    required String offerId,
    required String title,
    required String shortDescription,
    required String description,
    required String publisher,
    required this.category,
    required int rewardCoins,
    required int estimatedMinutes,
    required Iterable<OfferPlatform> platforms,
    required Iterable<String> countries,
    required this.status,
    required DateTime startsAt,
    required DateTime expiresAt,
    required String provider,
    this.featured = false,
    int sortPriority = 0,
    Uri? iconUrl,
    Uri? installUrl,
    Uri? destinationUrl,
    Uri? trackingUrl,
    Iterable<String> instructions = const [],
    Iterable<String> terms = const [],
    Map<String, String> trackingMetadata = const {},
    String? rewardTransactionId,
  }) : offerId = coinId(offerId, 'offerId'),
       title = coinText(title, 'title'),
       shortDescription = coinText(
         shortDescription,
         'shortDescription',
         max: 500,
       ),
       description = coinText(description, 'description', max: 4000),
       publisher = coinText(publisher, 'publisher'),
       rewardCoins = coinInt(rewardCoins, 'rewardCoins', min: 1),
       estimatedMinutes = coinInt(
         estimatedMinutes,
         'estimatedMinutes',
         max: 525600,
       ),
       platforms = List<OfferPlatform>.unmodifiable(platforms),
       countries = List<String>.unmodifiable(countries),
       startsAt = coinTime(startsAt, 'startsAt'),
       expiresAt = coinTime(expiresAt, 'expiresAt'),
       provider = coinId(provider, 'provider'),
       sortPriority = coinInt(sortPriority, 'sortPriority', max: 1000000),
       iconUrl = coinHttpsUrl(iconUrl, 'iconUrl'),
       installUrl = coinHttpsUrl(installUrl, 'installUrl'),
       destinationUrl = coinHttpsUrl(destinationUrl, 'destinationUrl'),
       trackingUrl = coinHttpsUrl(trackingUrl, 'trackingUrl'),
       instructions = coinTextList(instructions.toList(), 'instructions'),
       terms = coinTextList(terms.toList(), 'terms'),
       trackingMetadata = coinMetadata(trackingMetadata),
       rewardTransactionId = coinOptionalId(
         rewardTransactionId,
         'rewardTransactionId',
       ) {
    if (!expiresAt.isAfter(startsAt) ||
        this.platforms.length > 2 ||
        this.countries.length > 250) {
      throw const CoinModelException('offer availability');
    }
    if (this.countries.any((c) => !RegExp(r'^[A-Z]{2}$').hasMatch(c))) {
      throw const CoinModelException('country');
    }
    coinUnique(this.platforms.map((p) => p.name), 'platforms');
    coinUnique(this.countries, 'countries');
    if (status == OfferStatus.completed && rewardTransactionId == null) {
      throw const CoinModelException('completed offer transaction');
    }
  }
  final String offerId,
      title,
      shortDescription,
      description,
      publisher,
      provider;
  final String? rewardTransactionId;
  final OfferCategory category;
  final int rewardCoins, estimatedMinutes, sortPriority;
  final bool featured;
  final List<OfferPlatform> platforms;
  final List<String> countries, instructions, terms;
  final OfferStatus status;
  final DateTime startsAt, expiresAt;
  final Uri? iconUrl, installUrl, destinationUrl, trackingUrl;
  final Map<String, String> trackingMetadata;
  bool availableAt(DateTime serverTime) =>
      status == OfferStatus.available &&
      !serverTime.isBefore(startsAt) &&
      serverTime.isBefore(expiresAt);
  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
    offerId: coinId(j['offerId'], 'offerId'),
    title: coinText(j['title'], 'title'),
    shortDescription: coinText(
      j['shortDescription'],
      'shortDescription',
      max: 500,
    ),
    description: coinText(j['description'], 'description', max: 4000),
    publisher: coinText(j['publisher'], 'publisher'),
    category: coinEnum(j['category'], OfferCategory.values, 'category'),
    rewardCoins: coinInt(j['rewardCoins'], 'rewardCoins', min: 1),
    estimatedMinutes: coinInt(
      j['estimatedMinutes'],
      'estimatedMinutes',
      max: 525600,
    ),
    platforms: coinArray(
      j['platforms'],
      'platforms',
      max: 2,
    ).map((p) => coinEnum(p, OfferPlatform.values, 'platform')),
    countries: coinTextList(j['countries'], 'countries', max: 250, textMax: 2),
    status: coinEnum(j['status'], OfferStatus.values, 'status'),
    startsAt: coinTime(j['startsAt'], 'startsAt'),
    expiresAt: coinTime(j['expiresAt'], 'expiresAt'),
    provider: coinId(j['provider'], 'provider'),
    featured: coinBool(j['featured'], 'featured'),
    sortPriority: coinInt(j['sortPriority'], 'sortPriority', max: 1000000),
    iconUrl: coinHttpsUrl(j['iconUrl'], 'iconUrl'),
    installUrl: coinHttpsUrl(j['installUrl'], 'installUrl'),
    destinationUrl: coinHttpsUrl(j['destinationUrl'], 'destinationUrl'),
    trackingUrl: coinHttpsUrl(j['trackingUrl'], 'trackingUrl'),
    instructions: coinTextList(j['instructions'], 'instructions'),
    terms: coinTextList(j['terms'], 'terms'),
    trackingMetadata: coinMetadata(j['trackingMetadata']),
    rewardTransactionId: coinOptionalId(
      j['rewardTransactionId'],
      'rewardTransactionId',
    ),
  );
  Map<String, Object?> toJson() => {
    'offerId': offerId,
    'title': title,
    'shortDescription': shortDescription,
    'description': description,
    'publisher': publisher,
    'category': category.name,
    'rewardCoins': rewardCoins,
    'estimatedMinutes': estimatedMinutes,
    'platforms': platforms.map((p) => p.name).toList(),
    'countries': countries,
    'status': status.name,
    'startsAt': startsAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'provider': provider,
    'featured': featured,
    'sortPriority': sortPriority,
    'iconUrl': iconUrl?.toString(),
    'installUrl': installUrl?.toString(),
    'destinationUrl': destinationUrl?.toString(),
    'trackingUrl': trackingUrl?.toString(),
    'instructions': instructions,
    'terms': terms,
    'trackingMetadata': trackingMetadata,
    'rewardTransactionId': rewardTransactionId,
  };
}

class OfferQuery {
  OfferQuery({
    int page = 1,
    int pageSize = 20,
    String? cursor,
    String search = '',
    this.category,
    this.sort = OfferSort.recommended,
    this.platform,
    String? country,
  }) : page = coinInt(page, 'page', min: 1),
       pageSize = coinInt(pageSize, 'pageSize', min: 1, max: 100),
       cursor = cursor == null ? null : coinText(cursor, 'cursor', max: 512),
       search = search.trim().isEmpty
           ? ''
           : coinText(search.trim(), 'search', max: 120),
       country = country {
    if (country != null && !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      throw const CoinModelException('country');
    }
  }
  final int page, pageSize;
  final String? cursor, country;
  final String search;
  final OfferCategory? category;
  final OfferSort sort;
  final OfferPlatform? platform;
  Map<String, Object?> toJson() => {
    'page': page,
    'pageSize': pageSize,
    'cursor': cursor,
    'search': search,
    'category': category?.name,
    'sort': sort.name,
    'platform': platform?.name,
    'country': country,
  };
  factory OfferQuery.fromJson(Map<String, dynamic> j) => OfferQuery(
    page: coinInt(j['page'], 'page', min: 1),
    pageSize: coinInt(j['pageSize'], 'pageSize', min: 1, max: 100),
    cursor: j['cursor'] == null
        ? null
        : coinText(j['cursor'], 'cursor', max: 512),
    search: j['search'] == '' ? '' : coinText(j['search'], 'search', max: 120),
    category: j['category'] == null
        ? null
        : coinEnum(j['category'], OfferCategory.values, 'category'),
    sort: coinEnum(j['sort'], OfferSort.values, 'sort'),
    platform: j['platform'] == null
        ? null
        : coinEnum(j['platform'], OfferPlatform.values, 'platform'),
    country: j['country'] == null
        ? null
        : coinText(j['country'], 'country', max: 2),
  );
}

class PageInfo {
  PageInfo({
    required int page,
    required int pageSize,
    required int total,
    required this.hasNext,
    String? nextCursor,
    String? previousCursor,
  }) : page = coinInt(page, 'page', min: 1),
       pageSize = coinInt(pageSize, 'pageSize', min: 1, max: 100),
       total = coinInt(total, 'total'),
       nextCursor = nextCursor == null
           ? null
           : coinText(nextCursor, 'nextCursor', max: 512),
       previousCursor = previousCursor == null
           ? null
           : coinText(previousCursor, 'previousCursor', max: 512) {
    if (!hasNext && nextCursor != null ||
        hasNext && total == 0 ||
        page == 1 && previousCursor != null) {
      throw const CoinModelException('pagination');
    }
  }
  final int page, pageSize, total;
  final bool hasNext;
  final String? nextCursor, previousCursor;
  factory PageInfo.fromJson(Map<String, dynamic> j) => PageInfo(
    page: coinInt(j['page'], 'page', min: 1),
    pageSize: coinInt(j['pageSize'], 'pageSize', min: 1, max: 100),
    total: coinInt(j['total'], 'total'),
    hasNext: coinBool(j['hasNext'], 'hasNext'),
    nextCursor: j['nextCursor'] == null
        ? null
        : coinText(j['nextCursor'], 'nextCursor', max: 512),
    previousCursor: j['previousCursor'] == null
        ? null
        : coinText(j['previousCursor'], 'previousCursor', max: 512),
  );
  Map<String, Object?> toJson() => {
    'page': page,
    'pageSize': pageSize,
    'total': total,
    'hasNext': hasNext,
    'nextCursor': nextCursor,
    'previousCursor': previousCursor,
  };
}

class CoinPage<T> {
  CoinPage({
    required Iterable<T> items,
    required this.info,
    required String Function(T) id,
  }) : items = List<T>.unmodifiable(items) {
    if (this.items.length > info.pageSize ||
        this.items.length > info.total ||
        (info.hasNext && this.items.isEmpty)) {
      throw const CoinModelException('page items');
    }
    coinUnique(this.items.map(id), 'page IDs');
  }
  final List<T> items;
  final PageInfo info;
  factory CoinPage.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) parse,
    String Function(T) id,
  ) => CoinPage(
    items: coinArray(
      j['items'],
      'items',
    ).map((item) => parse(coinObject(item, 'item'))),
    info: PageInfo.fromJson(coinObject(j['page'], 'page')),
    id: id,
  );
  Map<String, Object?> toJson(Map<String, Object?> Function(T) serialize) => {
    'items': items.map(serialize).toList(),
    'page': info.toJson(),
  };
}

class OfferStart {
  OfferStart({
    required String startId,
    required String offerId,
    required String userId,
    required String idempotencyKey,
    required this.status,
    required DateTime updatedAt,
    String? trackingReference,
  }) : startId = coinId(startId, 'startId'),
       offerId = coinId(offerId, 'offerId'),
       userId = coinId(userId, 'userId'),
       idempotencyKey = coinId(idempotencyKey, 'idempotencyKey'),
       updatedAt = coinTime(updatedAt, 'updatedAt'),
       trackingReference = coinOptionalId(
         trackingReference,
         'trackingReference',
       ) {
    if (status != OfferStatus.started && status != OfferStatus.pending) {
      throw const CoinModelException('start is not completion');
    }
  }
  final String startId, offerId, userId, idempotencyKey;
  final String? trackingReference;
  final OfferStatus status;
  final DateTime updatedAt;
  factory OfferStart.fromJson(Map<String, dynamic> j) => OfferStart(
    startId: coinId(j['startId'], 'startId'),
    offerId: coinId(j['offerId'], 'offerId'),
    userId: coinId(j['userId'], 'userId'),
    idempotencyKey: coinId(j['idempotencyKey'], 'idempotencyKey'),
    status: coinEnum(j['status'], OfferStatus.values, 'status'),
    updatedAt: coinTime(j['updatedAt'], 'updatedAt'),
    trackingReference: coinOptionalId(
      j['trackingReference'],
      'trackingReference',
    ),
  );
  Map<String, Object?> toJson() => {
    'startId': startId,
    'offerId': offerId,
    'userId': userId,
    'idempotencyKey': idempotencyKey,
    'status': status.name,
    'updatedAt': updatedAt.toIso8601String(),
    'trackingReference': trackingReference,
  };
}

class DailyRewardConfiguration {
  DailyRewardConfiguration({
    required Iterable<int> dayRewards,
    required int streakDay,
    required this.eligible,
    required DateTime nextEligibleAt,
    required String version,
  }) : dayRewards = List<int>.unmodifiable(
         dayRewards.map((value) => coinInt(value, 'daily reward')),
       ),
       streakDay = coinInt(streakDay, 'streakDay', min: 1, max: 7),
       nextEligibleAt = coinTime(nextEligibleAt, 'nextEligibleAt'),
       version = coinId(version, 'version') {
    if (this.dayRewards.length != 7) {
      throw const CoinModelException('seven-day policy');
    }
  }
  final List<int> dayRewards;
  final int streakDay;
  final bool eligible;
  final DateTime nextEligibleAt;
  final String version;
  factory DailyRewardConfiguration.fromJson(Map<String, dynamic> j) =>
      DailyRewardConfiguration(
        dayRewards: coinArray(
          j['dayRewards'],
          'dayRewards',
          max: 7,
        ).map((value) => coinInt(value, 'daily reward')),
        streakDay: coinInt(j['streakDay'], 'streakDay', min: 1, max: 7),
        eligible: coinBool(j['eligible'], 'eligible'),
        nextEligibleAt: coinTime(j['nextEligibleAt'], 'nextEligibleAt'),
        version: coinId(j['version'], 'version'),
      );
  Map<String, Object?> toJson() => {
    'dayRewards': dayRewards,
    'streakDay': streakDay,
    'eligible': eligible,
    'nextEligibleAt': nextEligibleAt.toIso8601String(),
    'version': version,
  };
}
