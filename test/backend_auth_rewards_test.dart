import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/config/backend_config.dart';
import 'package:sharebondhu/models/offerwall_models.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/share_coin_models.dart';
import 'package:sharebondhu/models/user_models.dart';
import 'package:sharebondhu/screens/home_screen.dart';
import 'package:sharebondhu/screens/share_coin_home_screen.dart';
import 'package:sharebondhu/services/auth_session_service.dart';
import 'package:sharebondhu/services/authenticated_backend_repository.dart';
import 'package:sharebondhu/services/connectivity_service.dart';
import 'package:sharebondhu/services/rewarded_ad_provider.dart';
import 'package:sharebondhu/services/share_coin_service.dart';

import 'transfer_progress_test.dart' as p5;

final authTestTime = DateTime.utc(2026, 9, 9, 12);
BackendConfig testBackendConfig({
  Duration timeout = const Duration(seconds: 2),
  Iterable<ShareCoinOperation>? capabilities,
}) => BackendConfig(
  enabled: true,
  environment: ApiEnvironment.staging,
  baseUrl: Uri.parse('https://api.example.org/api/'),
  requestTimeout: timeout,
  capabilities: capabilities,
);

// Test-only provider. No production login, JWT validation or credential exists here.
class TestAuthProvider implements AuthProviderAdapter {
  TestAuthProvider({this.method = AuthenticationMethod.google});
  @override
  final AuthenticationMethod method;
  @override
  bool get configured => true;
  int logins = 0, refreshes = 0, logouts = 0;
  String userId = 'user-1';
  AccountStatus status = AccountStatus.active;
  bool hasRefresh = true;
  DateTime now = authTestTime;
  Duration lifetime = const Duration(hours: 1);
  Future<AuthGrant> Function(AuthAttempt)? loginHandler;
  Future<AuthGrant> Function(AuthGrant, AuthAttempt)? refreshHandler;
  AuthGrant grant({String? user, int revision = 0}) => AuthGrant(
    user: p5.coinFixtureUser(id: user ?? userId, status: status),
    method: method,
    backendSessionId: 'backend-session-${user ?? userId}',
    accessToken: SecretToken('synthetic-access-token-$revision'),
    refreshToken: hasRefresh
        ? SecretToken('synthetic-refresh-token-$revision')
        : null,
    serverTime: now,
    accessExpiresAt: now.add(lifetime),
    refreshExpiresAt: hasRefresh ? now.add(const Duration(days: 7)) : null,
  );
  @override
  Future<AuthGrant> signIn(AuthAttempt attempt) async {
    logins += 1;
    return loginHandler == null ? grant() : loginHandler!(attempt);
  }

  @override
  Future<AuthGrant> refresh(AuthGrant current, AuthAttempt attempt) async {
    refreshes += 1;
    return refreshHandler == null
        ? grant(revision: refreshes)
        : refreshHandler!(current, attempt);
  }

  @override
  Future<void> signOut(AuthGrant? current) async {
    logouts += 1;
  }
}

class TestApiTransport implements BackendTransport {
  final List<BackendHttpRequest> requests = [];
  Future<BackendHttpResponse> Function(BackendHttpRequest, RequestCancellation)?
  handler;
  bool closed = false;
  int cancelled = 0;
  Map<String, dynamic> wallet = p5.coinFixtureBalance().toJson();
  Map<String, dynamic> user = p5.coinFixtureUser().toJson();
  Map<String, dynamic> event = p5
      .coinFixtureReward(status: RewardEventStatus.pending)
      .toJson();
  Map<String, dynamic> transaction = p5.coinFixtureTransaction().toJson()
    ..['referenceId'] = 'placement-1';
  WithdrawalStatus withdrawalStatus = WithdrawalStatus.pending;
  BackendHttpResponse json(Object data, {int status = 200}) =>
      BackendHttpResponse(
        statusCode: status,
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(data))),
      );
  Map<String, Object?> envelope(Map<String, Object?> data) => {
    'userId': user['userId'],
    'serverTime': authTestTime.toIso8601String(),
    'version': 'api-revision-1',
    'data': data,
  };
  Map<String, Object?> page(
    List<Map<String, Object?>> items,
    BackendHttpRequest request,
  ) => {
    'items': items,
    'page': PageInfo(
      page: int.parse(request.uri.queryParameters['page'] ?? '1'),
      pageSize: int.parse(request.uri.queryParameters['pageSize'] ?? '20'),
      total: items.length,
      hasNext: false,
    ).toJson(),
  };
  @override
  Future<BackendHttpResponse> send(
    BackendHttpRequest request,
    RequestCancellation cancellation,
  ) async {
    if (closed) throw const ApiException(ApiErrorCode.cancelled);
    requests.add(request);
    final remove = cancellation.listen(() => cancelled += 1);
    try {
      if (handler != null) return await handler!(request, cancellation);
      return respond(request);
    } finally {
      remove();
    }
  }

  BackendHttpResponse respond(BackendHttpRequest request) {
    final path = request.uri.path.replaceFirst('/api/v1/', '');
    final args = request.body == null
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(request.body!)) as Map<String, dynamic>;
    if (path == 'health') return json({'status': 'ok', 'apiVersion': 'v1'});
    if (path == 'users/me') return json(envelope(user));
    if (path == 'wallet') return json(envelope(wallet));
    if (path == 'wallet/transactions') {
      return json(envelope(page([transaction], request)));
    }
    if (path.startsWith('wallet/transactions/')) {
      return json(envelope(transaction));
    }
    if (path == 'rewards/events' && request.method == 'POST') {
      event = Map<String, dynamic>.from(args)
        ..['status'] = RewardEventStatus.pending.name;
      return json(envelope(event));
    }
    if (path.startsWith('rewards/events/')) return json(envelope(event));
    if (path == 'offers') {
      return json(envelope(page([p5.coinFixtureOffer().toJson()], request)));
    }
    if (path.startsWith('offers/')) {
      return json(
        envelope(p5.coinFixtureOffer(id: path.split('/')[1]).toJson()),
      );
    }
    if (path == 'promotions') {
      return json(
        envelope(page([p5.coinFixturePromotion().toJson()], request)),
      );
    }
    if (path == 'withdrawals/policy') {
      return json(
        envelope(p5.coinFixturePolicy(user: user['userId'] as String).toJson()),
      );
    }
    if (path == 'withdrawals' && request.method == 'POST') {
      return json(
        envelope(
          p5
              .coinFixtureWithdrawal(
                user: user['userId'] as String,
                key: args['idempotencyKey'] as String,
                coins: args['coins'] as int,
                status: withdrawalStatus,
              )
              .toJson(),
        ),
      );
    }
    if (path == 'withdrawals') {
      return json(
        envelope(
          page([
            p5.coinFixtureWithdrawal(status: withdrawalStatus).toJson(),
          ], request),
        ),
      );
    }
    if (path.startsWith('withdrawals/')) {
      return json(
        envelope(p5.coinFixtureWithdrawal(status: withdrawalStatus).toJson()),
      );
    }
    return json({
      'error': {'code': 'not_found'},
    }, status: 404);
  }

  @override
  void close() {
    closed = true;
  }
}

class AuthFixture {
  AuthFixture({BackendConfig? config})
    : config = config ?? testBackendConfig() {
    auth = AuthSessionService(
      config: this.config,
      providers: [provider],
      clock: () => elapsed,
      autoExpire: false,
      refreshSkew: Duration.zero,
    );
    client = AuthenticatedApiClient(
      config: this.config,
      auth: auth,
      transport: transport,
    );
    backend = AuthenticatedShareCoinBackend(
      config: this.config,
      auth: auth,
      client: client,
    );
    network = ConnectivityService(
      localProbe: () async => ['192.168.1.2'],
      serviceProbe: backend.checkService,
    );
    service = ShareCoinService(backend: backend, connectivity: network);
    reconciler = ShareCoinReconciler(service: service);
    addTearDown(() {
      reconciler.dispose();
      service.dispose();
      network.dispose();
      backend.dispose();
      client.dispose();
      auth.dispose();
    });
  }
  final BackendConfig config;
  final TestAuthProvider provider = TestAuthProvider();
  final TestApiTransport transport = TestApiTransport();
  Duration elapsed = Duration.zero;
  late final AuthSessionService auth;
  late final AuthenticatedApiClient client;
  late final AuthenticatedShareCoinBackend backend;
  late final ConnectivityService network;
  late final ShareCoinService service;
  late final ShareCoinReconciler reconciler;
  Future<void> login() async {
    await auth.signIn(AuthenticationMethod.google);
  }

  void approveReward({
    CoinTransactionStatus status = CoinTransactionStatus.completed,
  }) {
    transport.event = p5
        .coinFixtureReward(status: RewardEventStatus.approved)
        .toJson();
    transport.transaction = p5.coinFixtureTransaction(status: status).toJson()
      ..['transactionId'] = 'reward-transaction-1'
      ..['referenceId'] = 'placement-1';
  }
}

class TestSdkDriver implements RewardedAdSdkDriver {
  final StreamController<AdProviderEvidence> stream =
      StreamController<AdProviderEvidence>.broadcast(sync: true);
  AdLoadContext? context;
  int sequence = 0, loads = 0, shows = 0;
  bool readyAutomatically = true, closed = false;
  @override
  bool get configured => true;
  @override
  String get provider => 'test-provider';
  @override
  Stream<AdProviderEvidence> get evidence => stream.stream;
  void emit(AdEvidenceResult result, {String? attempt, int? seq}) {
    final current = context!;
    stream.add(
      AdProviderEvidence(
        attemptId: attempt ?? current.attemptId,
        rewardSessionId: current.rewardSessionId,
        provider: provider,
        adUnit: current.adUnit,
        sequence: seq ?? ++sequence,
        result: result,
        timestamp: authTestTime,
        providerEventId: result == AdEvidenceResult.completed
            ? 'provider-proof-event'
            : null,
      ),
    );
  }

  @override
  Future<void> load(AdLoadContext value) async {
    context = value;
    sequence = 0;
    loads += 1;
    if (readyAutomatically) emit(AdEvidenceResult.loaded);
  }

  @override
  Future<void> show(AdLoadContext value) async {
    shows += 1;
    emit(AdEvidenceResult.shown);
  }

  @override
  Future<void> dismiss() async {}
  @override
  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    await stream.close();
  }
}

RewardSession authAdSession() => RewardSession(
  sessionId: 'ad-session',
  userId: 'user-1',
  eventId: 'ad-event',
  idempotencyKey: 'claim-key',
  requestKey: 'prepare-key',
  source: CoinSource.adReward,
  provider: 'test-provider',
  targetId: 'placement-1',
  rewardCoins: 150,
  issuedAt: authTestTime,
  expiresAt: authTestTime.add(const Duration(minutes: 5)),
  notBefore: authTestTime,
  availability: RewardAvailability.eligible,
  usedToday: 0,
  dailyLimit: 5,
);
AdConfiguration authAdConfig() => AdConfiguration(
  rewardedEnabled: true,
  bannerEnabled: false,
  interstitialEnabled: false,
  cooldownSeconds: 30,
  dailyLimit: 5,
  premium: false,
  provider: 'test-provider',
  units: const {'rewarded': 'development-unit-only'},
);
Matcher apiFailure(ApiErrorCode code) =>
    isA<ApiException>().having((error) => error.code, 'code', code);
Matcher authFailure(AuthErrorCode code) =>
    isA<AuthSessionException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Part 7 backend configuration', () {
    test('01 typed configuration normalizes the API prefix', () {
      final config = testBackendConfig();
      expect(
        config.endpoint('wallet').toString(),
        'https://api.example.org/api/v1/wallet',
      );
      expect(
        config.permits(Uri.parse('https://elsewhere.example/api/v1/wallet')),
        isFalse,
      );
    });
    test(
      '02 production and staging require HTTPS even with development flag',
      () {
        for (final environment in [
          ApiEnvironment.production,
          ApiEnvironment.staging,
        ]) {
          expect(
            () => BackendConfig(
              enabled: true,
              environment: environment,
              baseUrl: Uri.parse('http://127.0.0.1:9000/'),
              allowDevelopmentLoopbackHttp: true,
            ),
            throwsA(isA<BackendConfigurationException>()),
          );
        }
      },
    );
    test(
      '03 explicit development loopback HTTP is the only cleartext option',
      () {
        final config = BackendConfig(
          enabled: true,
          environment: ApiEnvironment.development,
          baseUrl: Uri.parse('http://127.0.0.1:9000/'),
          allowDevelopmentLoopbackHttp: true,
        );
        expect(config.endpoint('wallet').scheme, 'http');
        expect(
          () => BackendConfig(
            enabled: true,
            environment: ApiEnvironment.development,
            baseUrl: Uri.parse('http://10.0.0.2/'),
            allowDevelopmentLoopbackHttp: true,
          ),
          throwsA(isA<BackendConfigurationException>()),
        );
      },
    );
    test(
      '04 malformed URLs credentials queries and traversal are rejected',
      () {
        for (final text in [
          'https://user:secret@api.example.org/',
          'https://api..example.org/',
          'https://api.example.org/?token=secret',
          'https://api.example.org/api/%2Fprivate',
          'file:///private',
        ]) {
          expect(
            () => BackendConfig(
              enabled: true,
              environment: ApiEnvironment.production,
              baseUrl: Uri.parse(text),
            ),
            throwsA(isA<BackendConfigurationException>()),
          );
        }
        expect(
          () => testBackendConfig().endpoint('../wallet'),
          throwsA(isA<BackendConfigurationException>()),
        );
      },
    );
    test(
      '05 invalid timeouts and missing enabled configuration fail safely',
      () {
        expect(
          () => BackendConfig(
            enabled: true,
            environment: ApiEnvironment.production,
          ),
          throwsA(isA<BackendConfigurationException>()),
        );
        expect(
          () => BackendConfig(
            enabled: false,
            environment: ApiEnvironment.production,
            requestTimeout: Duration.zero,
          ),
          throwsA(isA<BackendConfigurationException>()),
        );
        expect(BackendConfig.fromEnvironment().enabled, isFalse);
      },
    );
    test('API token audience cannot be redirected to a different configured origin', () {
      final f = AuthFixture();
      final other = BackendConfig(
        enabled: true,
        environment: ApiEnvironment.production,
        baseUrl: Uri.parse('https://other.example.org/'),
      );
      expect(
        () => AuthenticatedApiClient(config: other, auth: f.auth),
        throwsA(isA<BackendConfigurationException>()),
      );
    });
  });

  group('Part 7 authentication session', () {
    test('06 unauthenticated session has no bearer or account scope', () async {
      final f = AuthFixture();
      expect(f.auth.value.status, AuthStatus.unauthenticated);
      expect(f.auth.scope, isNull);
      await expectLater(
        f.client.request('GET', 'wallet'),
        throwsA(apiFailure(ApiErrorCode.unauthenticated)),
      );
      expect(f.transport.requests, isEmpty);
    });
    test(
      '07 login transition comes from a configured provider result',
      () async {
        final f = AuthFixture();
        final pending = Completer<AuthGrant>();
        f.provider.loginHandler = (_) => pending.future;
        final login = f.auth.signIn(AuthenticationMethod.google);
        expect(f.auth.value.status, AuthStatus.authenticating);
        pending.complete(f.provider.grant());
        await login;
        expect(f.auth.value.status, AuthStatus.authenticated);
        expect(f.auth.scope!.userId, 'user-1');
      },
    );
    test(
      '08 logout invalidates scope immediately before provider cleanup',
      () async {
        final f = AuthFixture();
        await f.login();
        final epoch = f.auth.value.generation;
        final result = f.auth.logout();
        expect(f.auth.scope, isNull);
        expect(f.auth.value.status, AuthStatus.signedOut);
        await result;
        expect(f.auth.value.generation, greaterThan(epoch));
        expect(f.provider.logouts, 1);
      },
    );
    test('09 expiry never turns an expired nonrefreshable token into authentication', () async {
      final f = AuthFixture();
      f.provider.hasRefresh = false;
      f.provider.lifetime = const Duration(seconds: 1);
      await f.login();
      f.elapsed = const Duration(seconds: 2);
      f.auth.expireIfNeeded();
      expect(f.auth.value.status, AuthStatus.expired);
      expect(f.auth.scope, isNull);
    });
    test(
      '10 and 11 concurrent token refresh requests are single-flight',
      () async {
        final f = AuthFixture();
        await f.login();
        final pending = Completer<AuthGrant>();
        f.provider.refreshHandler = (grant, attempt) => pending.future;
        final first = f.auth.refreshSession();
        final second = f.auth.refreshSession();
        expect(identical(first, second), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(f.provider.refreshes, 1);
        pending.complete(f.provider.grant(revision: 1));
        await Future.wait([first, second]);
        expect(f.auth.value.status, AuthStatus.authenticated);
      },
    );
    test(
      '12 late login callbacks cannot resurrect a logged-out session',
      () async {
        final f = AuthFixture();
        final pending = Completer<AuthGrant>();
        f.provider.loginHandler = (_) => pending.future;
        final login = f.auth.signIn(AuthenticationMethod.google);
        final rejected = expectLater(
          login,
          throwsA(authFailure(AuthErrorCode.stale)),
        );
        await Future<void>.delayed(Duration.zero);
        await f.auth.logout();
        pending.complete(f.provider.grant());
        await rejected;
        expect(f.auth.value.status, AuthStatus.signedOut);
        expect(f.auth.scope, isNull);
      },
    );
    test('13 refresh cannot silently switch accounts', () async {
      final f = AuthFixture();
      await f.login();
      f.provider.refreshHandler = (_, attempt) async =>
          f.provider.grant(user: 'user-2', revision: 1);
      await expectLater(
        f.auth.refreshSession(),
        throwsA(authFailure(AuthErrorCode.invalidResponse)),
      );
      expect(f.auth.scope, isNull);
    });
    test('14 token grant lease snapshot and errors are redacted', () async {
      final f = AuthFixture();
      await f.login();
      final lease = await f.auth.acquire();
      final texts = [
        SecretToken('synthetic-access-token-0').toString(),
        f.provider.grant().toString(),
        lease.toString(),
        f.auth.value.toString(),
        jsonEncode(f.auth.value.toJson()),
        const ApiException(ApiErrorCode.network).toString(),
      ];
      expect(
        texts.any(
          (text) =>
              text.contains('synthetic-access-token') ||
              text.contains('synthetic-refresh-token'),
        ),
        isFalse,
      );
    });
    test(
      'duplicate sign-in taps do not open two provider operations',
      () async {
        final f = AuthFixture();
        await Future.wait([
          f.auth.signIn(AuthenticationMethod.google),
          f.auth.signIn(AuthenticationMethod.google),
        ]);
        expect(f.provider.logins, 1);
      },
    );
    test('unconfigured providers never manufacture authentication', () async {
      final auth = AuthSessionService(config: testBackendConfig());
      addTearDown(auth.dispose);
      await expectLater(
        auth.signIn(AuthenticationMethod.apple),
        throwsA(authFailure(AuthErrorCode.unavailable)),
      );
      expect(auth.scope, isNull);
      expect(auth.availableMethods, isEmpty);
    });
    test(
      'background session blocks requests and resumes without another login',
      () async {
        final f = AuthFixture();
        await f.login();
        final key = f.auth.scope!.key;
        f.auth.suspend();
        await expectLater(
          f.client.request('GET', 'wallet'),
          throwsA(apiFailure(ApiErrorCode.cancelled)),
        );
        f.auth.resume();
        await f.client.request('GET', 'wallet');
        expect(f.auth.scope!.key, key);
        expect(f.provider.logins, 1);
      },
    );
    test('restricted accounts may not issue financial mutations', () async {
      final f = AuthFixture();
      f.provider.status = AccountStatus.restricted;
      await f.login();
      expect(f.auth.value.status, AuthStatus.restricted);
      await expectLater(
        f.client.request(
          'POST',
          'withdrawals',
          body: {},
          idempotencyKey: 'key',
        ),
        throwsA(apiFailure(ApiErrorCode.restricted)),
      );
      expect(f.transport.requests, isEmpty);
    });
    test(
      'expired access can refresh without changing the account cache scope',
      () async {
        final f = AuthFixture();
        f.provider.lifetime = const Duration(seconds: 2);
        await f.login();
        final scope = f.auth.scope!.key;
        f.elapsed = const Duration(seconds: 3);
        f.provider.now = authTestTime.add(const Duration(seconds: 3));
        await f.client.request('GET', 'wallet');
        expect(f.provider.refreshes, 1);
        expect(f.auth.scope!.key, scope);
      },
    );
  });

  group('Part 7 authenticated HTTP and repository', () {
    test(
      '15 malformed JSON HTML and deeply nested payloads are rejected',
      () async {
        final f = AuthFixture();
        await f.login();
        for (final response in [
          BackendHttpResponse(
            statusCode: 200,
            bytes: Uint8List.fromList(utf8.encode('{bad')),
          ),
          BackendHttpResponse(
            statusCode: 200,
            contentType: 'text/html',
            bytes: Uint8List.fromList(utf8.encode('<html>login</html>')),
          ),
          BackendHttpResponse(
            statusCode: 200,
            bytes: Uint8List.fromList(
              utf8.encode(
                '${List.filled(40, '[').join()}0${List.filled(40, ']').join()}',
              ),
            ),
          ),
        ]) {
          f.transport.handler = (_, cancellation) async => response;
          await expectLater(
            f.client.request('GET', 'wallet'),
            throwsA(apiFailure(ApiErrorCode.malformed)),
          );
        }
      },
    );
    test(
      '16 invalid wallet response and unknown financial fields fail validation',
      () async {
        final f = AuthFixture();
        await f.login();
        f.transport.wallet['creditLocally'] = 1000;
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(p5.coinError(CoinErrorCode.malformed)),
        );
        expect(f.service.cachedWallet, isNull);
      },
    );
    test('17 negative wallet amounts are never cached', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.wallet['available'] = -1;
      await expectLater(
        f.service.getCurrentWallet(),
        throwsA(p5.coinError(CoinErrorCode.malformed)),
      );
    });
    test('18 invalid or overflowing transaction amounts cannot enter the ledger view', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.transaction['amount'] = maxShareCoinInteger + 1;
      await expectLater(
        f.service.getTransactionHistory(),
        throwsA(p5.coinError(CoinErrorCode.malformed)),
      );
    });
    test('19 reward submissions retain one idempotency key through the authenticated repository', () async {
      final f = AuthFixture();
      await f.login();
      final event = p5.coinFixtureReward();
      final results = await Future.wait([
        f.service.submitRewardEvent(event),
        f.service.submitRewardEvent(event),
      ]);
      final posts = f.transport.requests
          .where((request) => request.method == 'POST')
          .toList();
      expect(posts.length, 1);
      expect(posts.single.idempotencyKey, event.idempotencyKey);
      expect(results.first.data.status, RewardEventStatus.pending);
    });
    test('36 and 37 logout hides cached wallet without deleting local sharing history', () async {
      final f = AuthFixture();
      await f.login();
      await f.service.getCurrentWallet();
      expect(f.service.cachedWallet, isNotNull);
      await f.auth.logout();
      expect(f.backend.scope, isNull);
      expect(f.service.cachedWallet, isNull);
      expect(f.backend.configured, isTrue);
    });
    test(
      '38 logout cancels authenticated requests and rejects stale responses',
      () async {
        final f = AuthFixture();
        await f.login();
        final pending = Completer<BackendHttpResponse>();
        final started = Completer<void>();
        f.transport.handler = (request, cancellation) {
          started.complete();
          return pending.future;
        };
        final request = f.client.request('GET', 'wallet');
        final rejected = expectLater(
          request,
          throwsA(apiFailure(ApiErrorCode.cancelled)),
        );
        await started.future;
        await f.auth.logout();
        pending.complete(
          f.transport.json(f.transport.envelope(f.transport.wallet)),
        );
        await rejected;
        expect(f.transport.cancelled, greaterThan(0));
      },
    );
    test('39 disposed clients reject late completions', () async {
      final f = AuthFixture();
      await f.login();
      final pending = Completer<BackendHttpResponse>();
      final started = Completer<void>();
      f.transport.handler = (request, cancellation) {
        started.complete();
        return pending.future;
      };
      final call = f.client.request('GET', 'wallet');
      final rejected = expectLater(call, throwsA(isA<ApiException>()));
      await started.future;
      f.client.dispose();
      pending.complete(f.transport.json({}));
      await rejected;
    });
    test('40 disabled capabilities do not issue an endpoint request', () async {
      final f = AuthFixture(
        config: testBackendConfig(capabilities: [ShareCoinOperation.wallet]),
      );
      await f.login();
      await expectLater(
        f.backend.execute(
          ShareCoinOperation.offers,
          f.auth.scope!,
          OfferQuery().toJson(),
        ),
        throwsA(p5.coinError(CoinErrorCode.notConfigured)),
      );
      expect(f.transport.requests, isEmpty);
    });
    test('41 network timeout aborts a request and reports uncertainty for a dispatched write', () async {
      final f = AuthFixture(
        config: testBackendConfig(timeout: const Duration(milliseconds: 40)),
      );
      await f.login();
      f.transport.handler = (_, cancellation) =>
          Completer<BackendHttpResponse>().future;
      await expectLater(
        f.client.request(
          'POST',
          'rewards/events',
          body: {},
          idempotencyKey: 'key',
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', ApiErrorCode.timeout)
              .having((error) => error.uncertain, 'uncertain', isTrue),
        ),
      );
      expect(f.transport.cancelled, greaterThan(0));
    });
    test('42 one unauthorized GET refreshes once and retries without exposing the token', () async {
      final f = AuthFixture();
      await f.login();
      var calls = 0;
      f.transport.handler = (request, cancellation) async => ++calls == 1
          ? f.transport.json({
              'error': {'code': 'unauthenticated'},
            }, status: 401)
          : f.transport.respond(request);
      await f.client.request('GET', 'wallet');
      expect(f.provider.refreshes, 1);
      expect(calls, 2);
    });
    test(
      'repeated unauthorized GET invalidates the session after one retry',
      () async {
        final f = AuthFixture();
        await f.login();
        f.transport.handler = (_, cancellation) async =>
            f.transport.json({}, status: 401);
        await expectLater(
          f.client.request('GET', 'wallet'),
          throwsA(apiFailure(ApiErrorCode.unauthenticated)),
        );
        expect(f.transport.requests.length, 2);
        expect(f.auth.scope, isNull);
      },
    );
    test('financial POST is not automatically replayed after unauthorized response', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.handler = (_, cancellation) async =>
          f.transport.json({}, status: 401);
      await expectLater(
        f.client.request(
          'POST',
          'withdrawals',
          body: {},
          idempotencyKey: 'key',
        ),
        throwsA(apiFailure(ApiErrorCode.unauthenticated)),
      );
      expect(f.transport.requests.length, 1);
    });
    test('43 safe server error mapping retains no raw server text', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.handler = (request, cancellation) async =>
          request.uri.path.endsWith('/health')
          ? f.transport.respond(request)
          : f.transport.json({
              'error': {
                'code': 'rate_limited',
                'message': 'synthetic-access-token-0',
              },
            }, status: 429);
      try {
        await f.service.getCurrentWallet();
        fail('Expected rate limit.');
      } on ShareCoinException catch (error) {
        expect(error.code, CoinErrorCode.rateLimited);
        expect(error.toString(), isNot(contains('synthetic-access-token')));
      }
    });
    test('redirects never forward a bearer token to another origin', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.handler = (_, cancellation) async =>
          f.transport.json({}, status: 302);
      await expectLater(
        f.client.request('GET', 'wallet'),
        throwsA(apiFailure(ApiErrorCode.server)),
      );
      expect(f.transport.requests.length, 1);
      expect(f.transport.requests.single.uri.host, 'api.example.org');
    });
    test(
      'cross-account envelope and duplicate ledger IDs are rejected',
      () async {
        final f = AuthFixture();
        await f.login();
        f.transport.handler = (request, cancellation) async =>
            request.uri.path.endsWith('/health')
            ? f.transport.respond(request)
            : f.transport.json(
                f.transport.envelope(f.transport.wallet)
                  ..['userId'] = 'other-user',
              );
        await expectLater(
          f.service.getCurrentWallet(),
          throwsA(p5.coinError(CoinErrorCode.malformed)),
        );
        f.transport.handler = (request, cancellation) async =>
            request.uri.path.endsWith('/health')
            ? f.transport.respond(request)
            : f.transport.json(
                f.transport.envelope(
                  f.transport.page([
                    f.transport.transaction,
                    f.transport.transaction,
                  ], request),
                ),
              );
        await expectLater(
          f.service.getTransactionHistory(),
          throwsA(p5.coinError(CoinErrorCode.malformed)),
        );
      },
    );
  });

  group('Part 7 security race regressions', () {
    test(
      'an old unauthorized read cannot retry under a newly signed-in account',
      () async {
        final f = AuthFixture();
        await f.login();
        final pending = Completer<BackendHttpResponse>();
        final started = Completer<void>();
        f.transport.handler = (request, cancellation) {
          started.complete();
          return pending.future;
        };
        final request = f.client.request('GET', 'wallet');
        final rejected = expectLater(request, throwsA(isA<ApiException>()));
        await started.future;
        await f.auth.logout();
        f.provider.userId = 'user-2';
        await f.login();
        pending.complete(f.transport.json({}, status: 401));
        await rejected;
        expect(f.transport.requests.length, 1);
        expect(f.auth.scope!.userId, 'user-2');
      },
    );
    test('concurrent unauthorized reads share one refresh and preserve their account scope', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.handler = (request, cancellation) async {
        final old = request.authorization!.use((value) => value.endsWith('-0'));
        return old
            ? f.transport.json({}, status: 401)
            : f.transport.respond(request);
      };
      await Future.wait([
        f.client.request('GET', 'wallet'),
        f.client.request('GET', 'users/me'),
      ]);
      expect(f.provider.refreshes, 1);
      expect(f.transport.requests.length, 4);
    });
    test(
      'token-shaped query parameters are rejected before transport',
      () async {
        final f = AuthFixture();
        await f.login();
        await expectLater(
          f.client.request(
            'GET',
            'wallet',
            query: {'access_token': 'synthetic-token'},
          ),
          throwsA(apiFailure(ApiErrorCode.invalidRequest)),
        );
        expect(f.transport.requests, isEmpty);
      },
    );
  });

  group('Part 7 ledger and withdrawal reconciliation', () {
    test('20 pending reward is not reconciled into a credit', () async {
      final f = AuthFixture();
      await f.login();
      final result = await f.reconciler.reconcileReward('event-1');
      expect(result.state, RewardCreditState.pending);
      expect(result.reconciled, isFalse);
      expect(f.reconciler.isRewardReconciled('event-1'), isFalse);
    });
    test(
      '21 24 and 25 approval requires matching transaction and a fresh wallet',
      () async {
        final f = AuthFixture();
        await f.login();
        f.approveReward();
        final result = await f.reconciler.reconcileReward('event-1');
        expect(result.reconciled, isTrue);
        expect(result.transaction!.amount, 250);
        expect(result.wallet!.cached, isFalse);
        expect(f.reconciler.isRewardReconciled('event-1'), isTrue);
        final paths = f.transport.requests
            .map((request) => request.uri.path)
            .toList();
        expect(
          paths.indexOf('/api/v1/wallet/transactions/reward-transaction-1'),
          lessThan(paths.lastIndexOf('/api/v1/wallet')),
        );
        expect(result.wallet!.data.available, 10000);
      },
    );
    test('22 rejected reward remains visible without credit', () async {
      final f = AuthFixture();
      await f.login();
      f.transport.event = p5
          .coinFixtureReward(status: RewardEventStatus.rejected)
          .toJson();
      final result = await f.reconciler.reconcileReward('event-1');
      expect(result.state, RewardCreditState.rejected);
      expect(result.reconciled, isFalse);
    });
    test('23 reversed reward refreshes the same wallet and is not an approved credit', () async {
      final f = AuthFixture();
      await f.login();
      f.approveReward(status: CoinTransactionStatus.reversed);
      final result = await f.reconciler.reconcileReward('event-1');
      expect(result.state, RewardCreditState.reversed);
      expect(result.wallet, isNotNull);
      expect(result.reconciled, isFalse);
    });
    test('wallet refresh failure leaves approval unreconciled rather than inventing a balance', () async {
      final f = AuthFixture();
      await f.login();
      f.approveReward();
      f.transport.handler = (request, cancellation) async =>
          request.uri.path.endsWith('/wallet')
          ? f.transport.json({}, status: 503)
          : f.transport.respond(request);
      final result = await f.reconciler.reconcileReward('event-1');
      expect(result.state, RewardCreditState.unconfirmed);
      expect(result.wallet, isNull);
    });
    test(
      '26 opening or installing an offer is not a completed ledger transaction',
      () async {
        final f = AuthFixture();
        await f.login();
        final result = await f.reconciler.reconcileOffer('offer-1');
        expect(result.reconciled, isFalse);
        expect(result.transaction, isNull);
      },
    );
    test(
      '31 minimum withdrawal is checked without posting a request',
      () async {
        final f = AuthFixture();
        await f.login();
        await expectLater(
          f.service.requestWithdrawal(p5.coinFixtureIntent(coins: 500)),
          throwsA(p5.coinError(CoinErrorCode.minimum)),
        );
        expect(f.transport.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
    test('32 and 33 withdrawal uses a fresh wallet and a stable idempotency header', () async {
      final f = AuthFixture();
      await f.login();
      await f.service.getCurrentWallet();
      f.transport.wallet['available'] = 500;
      await expectLater(
        f.service.requestWithdrawal(p5.coinFixtureIntent()),
        throwsA(p5.coinError(CoinErrorCode.insufficientBalance)),
      );
      f.transport.wallet['available'] = 10000;
      final results = await Future.wait([
        f.service.requestWithdrawal(p5.coinFixtureIntent()),
        f.service.requestWithdrawal(p5.coinFixtureIntent()),
      ]);
      final posts = f.transport.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(posts.length, 1);
      expect(posts.single.idempotencyKey, 'withdraw-key-1');
      expect(results.singleOrNull, isNull);
    });
    test('34 and 35 withdrawal synchronization displays server pending or rejected state only', () async {
      final f = AuthFixture();
      await f.login();
      final pending = await f.reconciler.reconcileWithdrawal(
        withdrawalId: 'withdrawal-1',
      );
      expect(pending.request.status, WithdrawalStatus.pending);
      expect(pending.wallet.data.available, 10000);
      f.transport.withdrawalStatus = WithdrawalStatus.rejected;
      final rejected = await f.reconciler.reconcileWithdrawal(
        idempotencyKey: 'withdraw-key-1',
      );
      expect(rejected.request.status, WithdrawalStatus.rejected);
      expect(rejected.request.rejectionReason, isNotNull);
    });
    test('logout invalidates reconciliation markers and account-scoped pending results', () async {
      final f = AuthFixture();
      await f.login();
      f.approveReward();
      await f.reconciler.reconcileReward('event-1');
      await f.auth.logout();
      await Future<void>.delayed(Duration.zero);
      expect(f.reconciler.isRewardReconciled('event-1'), isFalse);
    });
  });

  group('Part 7 ad evidence boundary', () {
    test('28 default provider cannot load or simulate playback', () async {
      final provider = RewardedAdProvider();
      addTearDown(provider.dispose);
      expect(provider.configured, isFalse);
      expect(provider.value, AdProviderState.unavailable);
      await expectLater(
        provider.load(authAdSession(), authAdConfig()),
        throwsA(p5.coinError(CoinErrorCode.notConfigured)),
      );
    });
    test(
      '27 29 and 30 completion evidence has no money and is emitted once',
      () async {
        final driver = TestSdkDriver();
        final provider = RewardedAdProvider(driver: driver);
        addTearDown(provider.dispose);
        final legacy = <RewardedAdEvent>[];
        final evidence = <AdProviderEvidence>[];
        final a = provider.events.listen(legacy.add);
        final b = provider.completionEvidence.listen(evidence.add);
        addTearDown(a.cancel);
        addTearDown(b.cancel);
        await provider.load(authAdSession(), authAdConfig());
        await provider.show('ad-session');
        driver.emit(AdEvidenceResult.completed);
        driver.emit(AdEvidenceResult.completed);
        await Future<void>.delayed(Duration.zero);
        expect(
          legacy.where((e) => e.type == RewardedAdEventType.completed).length,
          1,
        );
        expect(evidence.length, 1);
        expect(evidence.single.toJson().keys, isNot(contains('coins')));
        expect(evidence.single.toJson().keys, isNot(contains('amount')));
        expect(provider.value, AdProviderState.completed);
      },
    );
    test(
      'stale and premature provider callbacks cannot complete an ad',
      () async {
        final driver = TestSdkDriver();
        final provider = RewardedAdProvider(driver: driver);
        addTearDown(provider.dispose);
        await provider.load(authAdSession(), authAdConfig());
        driver.emit(AdEvidenceResult.completed, attempt: 'old-attempt');
        expect(provider.value, AdProviderState.ready);
        driver.emit(AdEvidenceResult.completed);
        expect(provider.value, AdProviderState.ready);
      },
    );
    test(
      'provider loading is coalesced and disposal rejects late readiness',
      () async {
        final driver = TestSdkDriver()..readyAutomatically = false;
        final provider = RewardedAdProvider(driver: driver);
        final first = provider.load(authAdSession(), authAdConfig());
        final second = provider.load(authAdSession(), authAdConfig());
        expect(identical(first, second), isTrue);
        final rejected = expectLater(first, throwsA(isA<ShareCoinException>()));
        await Future<void>.delayed(Duration.zero);
        await provider.dispose();
        await rejected;
        expect(driver.loads, 1);
      },
    );
  });

  group('Part 7 real development HTTP and UI regression', () {
    test('real loopback transport uses the configured path and authorization, without redirects', () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<(String, String?)>();
      server.listen((request) async {
        seen.complete((
          request.uri.path,
          request.headers.value(HttpHeaders.authorizationHeader),
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'userId': 'user-1',
            'serverTime': authTestTime.toIso8601String(),
            'version': 'v1',
            'data': p5.coinFixtureBalance().toJson(),
          }),
        );
        await request.response.close();
      });
      final config = BackendConfig(
        enabled: true,
        environment: ApiEnvironment.development,
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
        allowDevelopmentLoopbackHttp: true,
      );
      final provider = TestAuthProvider();
      final auth = AuthSessionService(
        config: config,
        providers: [provider],
        autoExpire: false,
      );
      final backend = AuthenticatedShareCoinBackend(config: config, auth: auth);
      try {
        await auth.signIn(AuthenticationMethod.google);
        final response = await backend.execute(
          ShareCoinOperation.wallet,
          auth.scope!,
          {},
        );
        expect((response['data'] as Map)['available'], 10000);
        final request = await seen.future;
        expect(request.$1, '/v1/wallet');
        expect(request.$2, 'Bearer synthetic-access-token-0');
      } finally {
        backend.dispose();
        auth.dispose();
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    });
    test('real loopback response streaming is interrupted by logout', () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>();
      final release = Completer<void>();
      server.listen((request) async {
        unawaited(
          request.response.done.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {},
          ),
        );
        started.complete();
        await release.future;
        try {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        } catch (_) {}
      });
      final config = BackendConfig(
        enabled: true,
        environment: ApiEnvironment.development,
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
        allowDevelopmentLoopbackHttp: true,
        requestTimeout: const Duration(seconds: 2),
      );
      final provider = TestAuthProvider();
      final auth = AuthSessionService(
        config: config,
        providers: [provider],
        autoExpire: false,
      );
      final client = AuthenticatedApiClient(config: config, auth: auth);
      try {
        await auth.signIn(AuthenticationMethod.google);
        final request = client.request('GET', 'wallet');
        final rejected = expectLater(
          request,
          throwsA(apiFailure(ApiErrorCode.cancelled)),
        );
        await started.future;
        await auth.logout();
        await rejected;
        expect(client.activeRequests, 0);
      } finally {
        release.complete();
        client.dispose();
        auth.dispose();
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    });
    testWidgets(
      '44 configured/unconfigured auth never replaces the file-sharing home',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async => FileSelection(files: []),
              onToggleTheme: () {},
            ),
          ),
        );
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
      '45 the dashboard uses the supplied single ShareCoinService and optional auth session',
      (tester) async {
        final f = AuthFixture();
        await tester.runAsync(f.login);
        await p5.mountCoinDashboard(tester, f.service);
        expect(find.text('10,000 ShareCoin'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('share-coin-account')),
          findsOneWidget,
        );
        await f.auth.logout();
        await tester.pumpAndSettle();
        expect(find.text('10,000 ShareCoin'), findsNothing);
      },
    );
    testWidgets(
      'provider setup UI has disabled real-provider buttons when no SDK is configured',
      (tester) async {
        final auth = AuthSessionService(config: BackendConfig.disabled());
        addTearDown(auth.dispose);
        final connection = ConnectivityService(localProbe: () async => []);
        final service = ShareCoinService(connectivity: connection);
        addTearDown(service.dispose);
        addTearDown(connection.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ShareCoinHomeScreen(service: service, auth: auth),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('share-coin-account')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('auth-sign-in-google')),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('No login provider'), findsOneWidget);
      },
    );
  });
}
