# Part 5 — File 21–25

## Part 5A — File 21–23

## File 21 — `lib/models/share_coin_models.dart` — NEW

```dart
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
```

## File 22 — `lib/models/user_models.dart` — NEW

```dart
import 'share_coin_models.dart';

enum AccountStatus {
  active,
  restricted,
  suspended,
  deleted,
  pendingVerification,
}

enum AuthenticationMethod { google, apple, emailOtp, phoneOtp }

enum ReferralStatus { active, restricted, unavailable }

// Correlation scope supplied by a future authentication adapter. This is not
// an access token, a password, or proof that a backend authenticated the user.
class AccountScope {
  AccountScope({required String userId, required String sessionId})
    : userId = coinId(userId, 'userId'),
      sessionId = coinId(sessionId, 'sessionId');
  final String userId, sessionId;
  String get key => '$userId|$sessionId';
  Map<String, Object?> toJson() => {'userId': userId, 'sessionId': sessionId};
  factory AccountScope.fromJson(Map<String, dynamic> json) => AccountScope(
    userId: coinId(json['userId'], 'userId'),
    sessionId: coinId(json['sessionId'], 'sessionId'),
  );
  @override
  String toString() => 'AccountScope(identity redacted)';
}

class ShareCoinUser {
  ShareCoinUser({
    required String userId,
    required String displayName,
    required String username,
    required this.status,
    required DateTime createdAt,
    DateTime? lastActiveAt,
    required String version,
    String? referralCode,
    Uri? avatarUrl,
    Map<String, bool> features = const {},
    Iterable<AuthenticationMethod> linkedMethods = const [],
  }) : userId = coinId(userId, 'userId'),
       displayName = coinText(displayName, 'displayName', max: 120),
       username = coinText(username, 'username', max: 32),
       createdAt = coinTime(createdAt, 'createdAt'),
       lastActiveAt = coinOptionalTime(lastActiveAt, 'lastActiveAt'),
       version = coinId(version, 'version'),
       referralCode = coinOptionalId(referralCode, 'referralCode'),
       avatarUrl = coinHttpsUrl(avatarUrl, 'avatarUrl'),
       features = Map<String, bool>.unmodifiable(features),
       linkedMethods = List<AuthenticationMethod>.unmodifiable(linkedMethods) {
    if (!RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(username)) {
      throw const CoinModelException('username');
    }
    if (lastActiveAt != null && lastActiveAt.isBefore(createdAt)) {
      throw const CoinModelException('lastActiveAt');
    }
    if (features.length > 32 || this.linkedMethods.length > 4) {
      throw const CoinModelException('account configuration');
    }
    for (final key in features.keys) {
      coinId(key, 'feature key');
    }
    coinUnique(
      this.linkedMethods.map((method) => method.name),
      'linked authentication methods',
    );
  }
  final String userId, displayName, username, version;
  final String? referralCode;
  final Uri? avatarUrl;
  final AccountStatus status;
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final Map<String, bool> features;
  final List<AuthenticationMethod> linkedMethods;
  bool get mayRequestRewards => status == AccountStatus.active;
  factory ShareCoinUser.fromJson(Map<String, dynamic> j) => ShareCoinUser(
    userId: coinId(j['userId'], 'userId'),
    displayName: coinText(j['displayName'], 'displayName', max: 120),
    username: coinText(j['username'], 'username', max: 32),
    status: coinEnum(j['status'], AccountStatus.values, 'status'),
    createdAt: coinTime(j['createdAt'], 'createdAt'),
    lastActiveAt: coinOptionalTime(j['lastActiveAt'], 'lastActiveAt'),
    version: coinId(j['version'], 'version'),
    referralCode: coinOptionalId(j['referralCode'], 'referralCode'),
    avatarUrl: coinHttpsUrl(j['avatarUrl'], 'avatarUrl'),
    features: coinObject(
      j['features'],
      'features',
    ).map((key, value) => MapEntry(key, coinBool(value, 'feature'))),
    linkedMethods: coinArray(j['linkedMethods'], 'linkedMethods', max: 4).map(
      (method) => coinEnum(method, AuthenticationMethod.values, 'linkedMethod'),
    ),
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'username': username,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'lastActiveAt': lastActiveAt?.toIso8601String(),
    'version': version,
    'referralCode': referralCode,
    'avatarUrl': avatarUrl?.toString(),
    'features': features,
    'linkedMethods': linkedMethods.map((method) => method.name).toList(),
  };
}

class ReferralSummary {
  ReferralSummary({
    required String userId,
    required String referralCode,
    required int invitedCount,
    required int pendingCount,
    required int qualifiedCount,
    required int earnedCoins,
    required this.status,
    Uri? referralUrl,
    required DateTime updatedAt,
  }) : userId = coinId(userId, 'userId'),
       referralCode = coinId(referralCode, 'referralCode'),
       invitedCount = coinInt(invitedCount, 'invitedCount'),
       pendingCount = coinInt(pendingCount, 'pendingCount'),
       qualifiedCount = coinInt(qualifiedCount, 'qualifiedCount'),
       earnedCoins = coinInt(earnedCoins, 'earnedCoins'),
       referralUrl = coinHttpsUrl(referralUrl, 'referralUrl'),
       updatedAt = coinTime(updatedAt, 'updatedAt') {
    if (BigInt.from(pendingCount) + BigInt.from(qualifiedCount) >
        BigInt.from(invitedCount)) {
      throw const CoinModelException('referral counts');
    }
  }
  final String userId, referralCode;
  final int invitedCount, pendingCount, qualifiedCount, earnedCoins;
  final ReferralStatus status;
  final Uri? referralUrl;
  final DateTime updatedAt;
  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
    userId: coinId(j['userId'], 'userId'),
    referralCode: coinId(j['referralCode'], 'referralCode'),
    invitedCount: coinInt(j['invitedCount'], 'invitedCount'),
    pendingCount: coinInt(j['pendingCount'], 'pendingCount'),
    qualifiedCount: coinInt(j['qualifiedCount'], 'qualifiedCount'),
    earnedCoins: coinInt(j['earnedCoins'], 'earnedCoins'),
    status: coinEnum(j['status'], ReferralStatus.values, 'status'),
    referralUrl: coinHttpsUrl(j['referralUrl'], 'referralUrl'),
    updatedAt: coinTime(j['updatedAt'], 'updatedAt'),
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'referralCode': referralCode,
    'invitedCount': invitedCount,
    'pendingCount': pendingCount,
    'qualifiedCount': qualifiedCount,
    'earnedCoins': earnedCoins,
    'status': status.name,
    'referralUrl': referralUrl?.toString(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
```

## File 23 — `lib/services/share_coin_service.dart` — NEW

```dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
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
        'invalid_request' => CoinErrorCode.invalidRequest,
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
  }) async {
    try {
      _current(scope, generation);
      if (mutation && _suspended) {
        throw const ShareCoinException(CoinErrorCode.offline);
      }
      final envelope = await _backend
          .execute(
            operation,
            scope,
            Map<String, Object?>.unmodifiable(arguments),
          )
          .timeout(requestTimeout);
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
  }) => _read(
    ShareCoinOperation.offers,
    (j, scope) =>
        CoinPage<Offer>.fromJson(j, Offer.fromJson, (value) => value.offerId),
    arguments: (query ?? OfferQuery()).toJson(),
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

  Future<CoinData<AdConfiguration>> getAdConfiguration() => _read(
    ShareCoinOperation.adsConfiguration,
    (j, scope) => AdConfiguration.fromJson(j),
  );
  Future<CoinData<DailyRewardConfiguration>> getDailyRewardConfiguration() =>
      _read(
        ShareCoinOperation.dailyConfiguration,
        (j, scope) => DailyRewardConfiguration.fromJson(j),
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
```

