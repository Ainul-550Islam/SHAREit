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
