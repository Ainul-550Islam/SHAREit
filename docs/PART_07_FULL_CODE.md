# Part 7 — File 31–35

Complete source based on Part 6. All five new files are in order, followed by full integration replacements. No production credentials/providers/deployment are implied.

## File 31 — `lib/config/backend_config.dart` — NEW

```dart
import 'dart:io';

import '../services/share_coin_service.dart'
    show ShareCoinOperation, ShareCoinRewardOperation;

enum ApiEnvironment { development, staging, production }

class BackendConfigurationException implements Exception {
  const BackendConfigurationException();
  @override
  String toString() =>
      'Backend configuration is missing or invalid. No credentials are included in this error.';
}

class BackendConfig {
  BackendConfig({
    required this.enabled,
    required this.environment,
    Uri? baseUrl,
    this.apiVersion = 'v1',
    this.requestTimeout = const Duration(seconds: 20),
    this.connectTimeout = const Duration(seconds: 10),
    this.downloadTimeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(seconds: 15),
    this.allowDevelopmentLoopbackHttp = false,
    this.maxRequestBytes = 64 * 1024,
    this.maxResponseBytes = 512 * 1024,
    this.maxConcurrentRequests = 6,
    this.healthPath = 'health',
    this.adConfigurationPath = 'ads/configuration',
    this.analyticsPath,
    Iterable<ShareCoinOperation>? capabilities,
    Iterable<ShareCoinRewardOperation>? rewardCapabilities,
    this.configurationIssue,
  }) : baseUrl = _base(baseUrl, environment, allowDevelopmentLoopbackHttp),
       capabilities = Set<ShareCoinOperation>.unmodifiable(
         capabilities ?? ShareCoinOperation.values,
       ),
       rewardCapabilities = Set<ShareCoinRewardOperation>.unmodifiable(
         rewardCapabilities ?? ShareCoinRewardOperation.values,
       ) {
    if (enabled && this.baseUrl == null ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(apiVersion) ||
        maxRequestBytes < 1024 ||
        maxRequestBytes > 1024 * 1024 ||
        maxResponseBytes < 1024 ||
        maxResponseBytes > 2 * 1024 * 1024 ||
        maxConcurrentRequests < 1 ||
        maxConcurrentRequests > 16) {
      throw const BackendConfigurationException();
    }
    for (final duration in [
      requestTimeout,
      connectTimeout,
      downloadTimeout,
      uploadTimeout,
    ]) {
      if (duration <= Duration.zero || duration > const Duration(minutes: 2)) {
        throw const BackendConfigurationException();
      }
    }
    validatePath(healthPath);
    validatePath(adConfigurationPath);
    if (analyticsPath != null) validatePath(analyticsPath!);
  }

  factory BackendConfig.disabled({String? reason}) => BackendConfig(
    enabled: false,
    environment: ApiEnvironment.production,
    capabilities: const [],
    rewardCapabilities: const [],
    configurationIssue: reason,
  );

  factory BackendConfig.fromEnvironment() {
    const enabled = bool.fromEnvironment(
      'SHAREBONDHU_BACKEND_ENABLED',
      defaultValue: false,
    );
    const base = String.fromEnvironment('SHAREBONDHU_API_BASE_URL');
    const environment = String.fromEnvironment(
      'SHAREBONDHU_API_ENV',
      defaultValue: 'production',
    );
    const version = String.fromEnvironment(
      'SHAREBONDHU_API_VERSION',
      defaultValue: 'v1',
    );
    const loopback = bool.fromEnvironment(
      'SHAREBONDHU_ALLOW_LOOPBACK_HTTP',
      defaultValue: false,
    );
    if (!enabled) {
      return BackendConfig.disabled(
        reason: 'Backend disabled. Supply non-secret configuration when ready.',
      );
    }
    try {
      final env = ApiEnvironment.values
          .where((value) => value.name == environment)
          .firstOrNull;
      if (env == null || base.isEmpty) {
        throw const BackendConfigurationException();
      }
      return BackendConfig(
        enabled: true,
        environment: env,
        baseUrl: Uri.parse(base),
        apiVersion: version,
        allowDevelopmentLoopbackHttp: loopback,
      );
    } catch (_) {
      return BackendConfig.disabled(
        reason: 'Invalid environment configuration. Backend access is disabled safely.',
      );
    }
  }

  final bool enabled, allowDevelopmentLoopbackHttp;
  final ApiEnvironment environment;
  final Uri? baseUrl;
  final String apiVersion, healthPath, adConfigurationPath;
  final String? analyticsPath, configurationIssue;
  final Duration requestTimeout, connectTimeout, downloadTimeout, uploadTimeout;
  final int maxRequestBytes, maxResponseBytes, maxConcurrentRequests;
  final Set<ShareCoinOperation> capabilities;
  final Set<ShareCoinRewardOperation> rewardCapabilities;

  static Uri? _base(Uri? value, ApiEnvironment environment, bool allowHttp) {
    if (value == null) return null;
    if (value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.host.isEmpty ||
        value.port < 1 ||
        value.port > 65535 ||
        value.toString().length > 2048) {
      throw const BackendConfigurationException();
    }
    final loopback =
        value.host == 'localhost' ||
        value.host == '127.0.0.1' ||
        value.host == '::1';
    final developmentHttp =
        environment == ApiEnvironment.development &&
        allowHttp &&
        loopback &&
        value.scheme == 'http';
    if (value.scheme != 'https' && !developmentHttp) {
      throw const BackendConfigurationException();
    }
    if (!loopback) {
      if (InternetAddress.tryParse(value.host) != null ||
          !value.host.contains('.') ||
          value.host.endsWith('.local') ||
          value.host.endsWith('.localhost')) {
        throw const BackendConfigurationException();
      }
      for (final label in value.host.split('.')) {
        if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
            .hasMatch(label)) {
          throw const BackendConfigurationException();
        }
      }
    } else if (environment != ApiEnvironment.development) {
      throw const BackendConfigurationException();
    }
    final segments = value.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.any(
      (segment) => !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment),
    )) {
      throw const BackendConfigurationException();
    }
    final path = value.path.isEmpty
        ? '/'
        : value.path.endsWith('/')
        ? value.path
        : '${value.path}/';
    return value.replace(path: path);
  }

  static void validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('?') ||
        path.contains('#') ||
        path
            .split('/')
            .any(
              (part) =>
                  !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$')
                      .hasMatch(part) ||
                  part == '.' ||
                  part == '..',
            )) {
      throw const BackendConfigurationException();
    }
  }

  Uri endpoint(String path, {Map<String, String> query = const {}}) {
    if (!enabled || baseUrl == null) {
      throw const BackendConfigurationException();
    }
    validatePath(path);
    final uri = baseUrl!.resolve('$apiVersion/$path');
    if (uri.origin != baseUrl!.origin || !uri.path.startsWith(baseUrl!.path)) {
      throw const BackendConfigurationException();
    }
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  bool permits(Uri uri) =>
      enabled &&
      baseUrl != null &&
      uri.origin == baseUrl!.origin &&
      uri.path.startsWith('${baseUrl!.path}$apiVersion/') &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;

  @override
  String toString() =>
      'BackendConfig(${environment.name}, enabled: $enabled, secrets: absent)';
}
```

## File 32 — `lib/services/auth_session_service.dart` — NEW

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/backend_config.dart';
import '../models/share_coin_models.dart' show coinId, coinTime;
import '../models/user_models.dart';

enum AuthStatus {
  unauthenticated,
  authenticating,
  authenticated,
  refreshing,
  expired,
  signedOut,
  restricted,
  error,
}

enum AuthErrorCode {
  unavailable,
  unauthenticated,
  expired,
  restricted,
  cancelled,
  stale,
  invalidResponse,
  disposed,
}

enum RequestCancelReason { logout, replaced, background, timeout, disposed }

enum ApiErrorCode {
  configuration,
  unauthenticated,
  restricted,
  network,
  timeout,
  cancelled,
  stale,
  malformed,
  notFound,
  conflict,
  rateLimited,
  server,
  invalidRequest,
}

class AuthSessionException implements Exception {
  const AuthSessionException(this.code);
  final AuthErrorCode code;
  String get message => switch (code) {
    AuthErrorCode.unavailable =>
      'Authentication provider or backend configuration is unavailable.',
    AuthErrorCode.unauthenticated =>
      'Sign in with a configured authentication provider.',
    AuthErrorCode.expired => 'The API session expired. Sign in again.',
    AuthErrorCode.restricted => 'This account is restricted.',
    AuthErrorCode.cancelled => 'The authentication operation was cancelled.',
    AuthErrorCode.stale => 'The account or authentication attempt changed.',
    AuthErrorCode.invalidResponse => 'The authentication response was invalid.',
    AuthErrorCode.disposed => 'The authentication session is closed.',
  };
  @override
  String toString() => message;
}

class SecretToken {
  SecretToken(String value) : _value = value {
    if (!RegExp(r'^[\x21-\x7e]{16,8192}$').hasMatch(value)) {
      throw const AuthSessionException(AuthErrorCode.invalidResponse);
    }
  }
  final String _value;
  // Only an actual SDK/transport adapter should expose a token to its request.
  // Never pass this value to logs, analytics, persistence or UI.
  T use<T>(T Function(String value) action) => action(_value);
  @override
  String toString() => 'SecretToken(redacted)';
}

class RequestCancellation {
  RequestCancelReason? _reason;
  final Set<VoidCallback> _listeners = {};
  bool get cancelled => _reason != null;
  RequestCancelReason? get reason => _reason;
  VoidCallback listen(VoidCallback listener) {
    if (cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel(RequestCancelReason reason) {
    if (cancelled) return;
    _reason = reason;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }

  void check() {
    if (cancelled) throw const AuthSessionException(AuthErrorCode.cancelled);
  }
}

class AuthAttempt {
  AuthAttempt({required this.generation, required this.cancellation})
    : attemptId = _sessionId();
  final int generation;
  final String attemptId;
  final RequestCancellation cancellation;
  @override
  String toString() =>
      'AuthAttempt(generation: $generation, credentials: absent)';
}

class AuthGrant {
  AuthGrant({
    required this.user,
    required this.method,
    required String backendSessionId,
    required this.accessToken,
    this.refreshToken,
    required DateTime serverTime,
    required DateTime accessExpiresAt,
    DateTime? refreshExpiresAt,
  }) : backendSessionId = coinId(backendSessionId, 'backendSessionId'),
       serverTime = coinTime(serverTime, 'serverTime'),
       accessExpiresAt = coinTime(accessExpiresAt, 'accessExpiresAt'),
       refreshExpiresAt = refreshExpiresAt == null
           ? null
           : coinTime(refreshExpiresAt, 'refreshExpiresAt') {
    if (!accessExpiresAt.isAfter(serverTime) ||
        accessExpiresAt.difference(serverTime) > const Duration(days: 7) ||
        refreshToken == null && refreshExpiresAt != null ||
        refreshExpiresAt != null && !refreshExpiresAt.isAfter(serverTime)) {
      throw const AuthSessionException(AuthErrorCode.invalidResponse);
    }
  }
  final ShareCoinUser user;
  final AuthenticationMethod method;
  final String backendSessionId;
  final SecretToken accessToken;
  final SecretToken? refreshToken;
  final DateTime serverTime, accessExpiresAt;
  final DateTime? refreshExpiresAt;
  @override
  String toString() => 'AuthGrant(tokens and identity redacted)';
}

abstract interface class AuthProviderAdapter {
  AuthenticationMethod get method;
  bool get configured;
  // SDK + backend exchange must verify identity and return backend API tokens,
  // not blindly decoded Google/Apple/client JWT claims.
  Future<AuthGrant> signIn(AuthAttempt attempt);
  Future<AuthGrant> refresh(AuthGrant current, AuthAttempt attempt);
  Future<void> signOut(AuthGrant? current);
}

class UnavailableAuthProvider implements AuthProviderAdapter {
  const UnavailableAuthProvider(this.method);
  @override
  final AuthenticationMethod method;
  @override
  bool get configured => false;
  @override
  Future<AuthGrant> signIn(AuthAttempt attempt) =>
      Future.error(const AuthSessionException(AuthErrorCode.unavailable));
  @override
  Future<AuthGrant> refresh(AuthGrant current, AuthAttempt attempt) =>
      Future.error(const AuthSessionException(AuthErrorCode.unavailable));
  @override
  Future<void> signOut(AuthGrant? current) async {}
}

class AuthSessionSnapshot {
  const AuthSessionSnapshot({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.scope,
    this.expiresAt,
    this.canRefresh = false,
    this.foreground = true,
    this.generation = 0,
    this.tokenRevision = 0,
    this.error,
  });
  final AuthStatus status;
  final ShareCoinUser? user;
  final AccountScope? scope;
  final DateTime? expiresAt;
  final bool canRefresh, foreground;
  final int generation, tokenRevision;
  final AuthErrorCode? error;
  Map<String, Object?> toJson() => {
    'status': status.name,
    'user': user?.toJson(),
    'scope': scope?.toJson(),
    'expiresAt': expiresAt?.toIso8601String(),
    'canRefresh': canRefresh,
    'foreground': foreground,
    'generation': generation,
    'tokenRevision': tokenRevision,
    'error': error?.name,
  };
  @override
  String toString() =>
      'AuthSessionSnapshot(${status.name}, generation: $generation, tokens: redacted)';
}

class AuthLease {
  const AuthLease({
    required this.scope,
    required this.generation,
    required this.revision,
    required this.token,
    required this.canWrite,
  });
  final AccountScope scope;
  final int generation, revision;
  final SecretToken token;
  final bool canWrite;
  @override
  String toString() => 'AuthLease(credentials redacted)';
}

String _sessionId() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class AuthSessionService extends ValueNotifier<AuthSessionSnapshot> {
  AuthSessionService({
    required this.config,
    Iterable<AuthProviderAdapter> providers = const [],
    this.clock,
    this.refreshSkew = const Duration(seconds: 30),
    this.operationTimeout = const Duration(minutes: 2),
    this.autoExpire = true,
  }) : _providers = {
         for (final provider in providers) provider.method: provider,
       },
       super(const AuthSessionSnapshot()) {
    if (_providers.length != providers.length ||
        refreshSkew < Duration.zero ||
        refreshSkew > const Duration(minutes: 5) ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 5)) {
      throw ArgumentError('Invalid authentication configuration.');
    }
  }
  final BackendConfig config;
  final Map<AuthenticationMethod, AuthProviderAdapter> _providers;
  final Duration Function()? clock;
  final Duration refreshSkew, operationTimeout;
  final bool autoExpire;
  final Stopwatch _watch = Stopwatch()..start();
  AuthGrant? _grant;
  AccountScope? _scope;
  AuthAttempt? _attempt;
  Future<AuthSessionSnapshot>? _login;
  Future<AuthSessionSnapshot>? _refresh;
  AuthenticationMethod? _loginMethod;
  Timer? _expiry;
  int _generation = 0, _revision = 0;
  bool _closed = false, _foreground = true;
  DateTime? _serverAnchor;
  Duration _anchorTick = Duration.zero, _lastTick = Duration.zero;

  List<AuthenticationMethod> get availableMethods => List.unmodifiable(
    _providers.values
        .where((p) => p.configured && config.enabled)
        .map((p) => p.method),
  );
  AccountScope? get scope => value.scope;
  bool get closed => _closed;
  Duration get _now {
    final now = clock?.call() ?? _watch.elapsed;
    if (now > _lastTick) _lastTick = now;
    return _lastTick;
  }

  DateTime? get serverEstimate => _serverAnchor?.add(_now - _anchorTick);
  bool get _canRefresh =>
      _grant?.refreshToken != null &&
      (_grant!.refreshExpiresAt == null ||
          serverEstimate != null &&
              serverEstimate!.isBefore(_grant!.refreshExpiresAt!));
  bool get _accessValid =>
      _grant != null &&
      serverEstimate != null &&
      serverEstimate!.isBefore(_grant!.accessExpiresAt);
  bool get _blockedAccount =>
      _grant?.user.status == AccountStatus.suspended ||
      _grant?.user.status == AccountStatus.deleted;

  void _publish(AuthStatus status, {AuthErrorCode? error}) {
    if (_closed) return;
    value = AuthSessionSnapshot(
      status: status,
      user: _grant?.user,
      scope: _blockedAccount || !_accessValid && !_canRefresh ? null : _scope,
      expiresAt: _grant?.accessExpiresAt,
      canRefresh: _canRefresh,
      foreground: _foreground,
      generation: _generation,
      tokenRevision: _revision,
      error: error,
    );
  }

  void _clear(RequestCancelReason reason) {
    _generation += 1;
    _revision += 1;
    _attempt?.cancellation.cancel(reason);
    _attempt = null;
    _login = null;
    _refresh = null;
    _expiry?.cancel();
    _expiry = null;
    _grant = null;
    _scope = null;
    _serverAnchor = null;
  }

  void _check(AuthAttempt attempt) {
    if (_closed) throw const AuthSessionException(AuthErrorCode.disposed);
    if (attempt.generation != _generation || attempt.cancellation.cancelled) {
      throw const AuthSessionException(AuthErrorCode.stale);
    }
  }

  void _accept(AuthGrant grant, {bool refreshing = false}) {
    if (refreshing &&
        (_grant?.user.userId != grant.user.userId ||
            _grant?.backendSessionId != grant.backendSessionId ||
            _grant?.method != grant.method)) {
      throw const AuthSessionException(AuthErrorCode.invalidResponse);
    }
    _grant = grant;
    _scope ??= AccountScope(userId: grant.user.userId, sessionId: _sessionId());
    _serverAnchor = grant.serverTime;
    _anchorTick = _now;
    _revision += 1;
    _expiry?.cancel();
    if (autoExpire) {
      _expiry = Timer(
        grant.accessExpiresAt.difference(grant.serverTime),
        expireIfNeeded,
      );
    }
    _publish(
      grant.user.mayRequestRewards
          ? AuthStatus.authenticated
          : AuthStatus.restricted,
    );
  }

  Future<AuthSessionSnapshot> signIn(AuthenticationMethod method) {
    if (_closed) {
      return Future.error(const AuthSessionException(AuthErrorCode.disposed));
    }
    if (!_foreground) {
      return Future.error(const AuthSessionException(AuthErrorCode.cancelled));
    }
    final provider = _providers[method];
    if (!config.enabled || provider == null || !provider.configured) {
      _publish(AuthStatus.error, error: AuthErrorCode.unavailable);
      return Future.error(
        const AuthSessionException(AuthErrorCode.unavailable),
      );
    }
    if (_login != null && _loginMethod == method) return _login!;
    _clear(RequestCancelReason.replaced);
    final attempt = AuthAttempt(
      generation: _generation,
      cancellation: RequestCancellation(),
    );
    _attempt = attempt;
    _loginMethod = method;
    final result = Completer<AuthSessionSnapshot>();
    _login = result.future;
    _publish(AuthStatus.authenticating);
    Future<void>(() async {
      try {
        _check(attempt);
        final grant = await provider.signIn(attempt).timeout(operationTimeout);
        _check(attempt);
        if (grant.method != method) {
          throw const AuthSessionException(AuthErrorCode.invalidResponse);
        }
        _accept(grant);
        result.complete(value);
      } catch (error) {
        final safe = error is AuthSessionException
            ? error
            : const AuthSessionException(AuthErrorCode.unavailable);
        if (!_closed && attempt.generation == _generation) {
          _grant = null;
          _scope = null;
          _publish(AuthStatus.error, error: safe.code);
        }
        result.completeError(safe);
      } finally {
        if (identical(_login, result.future)) _login = null;
      }
    });
    return result.future;
  }

  Future<AuthSessionSnapshot> refreshSession({int? rejectedRevision}) {
    if (_closed) {
      return Future.error(const AuthSessionException(AuthErrorCode.disposed));
    }
    if (!_foreground) {
      return Future.error(const AuthSessionException(AuthErrorCode.cancelled));
    }
    if (rejectedRevision != null &&
        rejectedRevision != _revision &&
        _accessValid) {
      return Future.value(value);
    }
    if (_refresh != null) return _refresh!;
    final current = _grant;
    final provider = current == null ? null : _providers[current.method];
    if (current == null ||
        !_canRefresh ||
        provider == null ||
        !provider.configured) {
      _clear(RequestCancelReason.replaced);
      _publish(AuthStatus.expired, error: AuthErrorCode.expired);
      return Future.error(const AuthSessionException(AuthErrorCode.expired));
    }
    final attempt = AuthAttempt(
      generation: _generation,
      cancellation: RequestCancellation(),
    );
    _attempt = attempt;
    final result = Completer<AuthSessionSnapshot>();
    _refresh = result.future;
    _publish(AuthStatus.refreshing);
    Future<void>(() async {
      try {
        _check(attempt);
        final grant = await provider
            .refresh(current, attempt)
            .timeout(operationTimeout);
        _check(attempt);
        _accept(grant, refreshing: true);
        result.complete(value);
      } catch (error) {
        final safe = error is AuthSessionException
            ? error
            : const AuthSessionException(AuthErrorCode.expired);
        if (!_closed && attempt.generation == _generation) {
          _clear(RequestCancelReason.replaced);
          _publish(AuthStatus.expired, error: safe.code);
        }
        result.completeError(safe);
      } finally {
        if (identical(_refresh, result.future)) _refresh = null;
      }
    });
    return result.future;
  }

  Future<AuthLease> acquire({bool write = false}) async {
    if (_closed) throw const AuthSessionException(AuthErrorCode.disposed);
    if (!_foreground) throw const AuthSessionException(AuthErrorCode.cancelled);
    final epoch = _generation;
    if (_grant == null) {
      throw const AuthSessionException(AuthErrorCode.unauthenticated);
    }
    if (_blockedAccount || write && !_grant!.user.mayRequestRewards) {
      throw const AuthSessionException(AuthErrorCode.restricted);
    }
    if (!_accessValid ||
        _canRefresh &&
            !serverEstimate!
                .add(refreshSkew)
                .isBefore(_grant!.accessExpiresAt)) {
      await refreshSession();
    }
    if (_closed || epoch != _generation || !_foreground) {
      throw const AuthSessionException(AuthErrorCode.stale);
    }
    if (!_accessValid || _scope == null) {
      throw const AuthSessionException(AuthErrorCode.expired);
    }
    return AuthLease(
      scope: _scope!,
      generation: _generation,
      revision: _revision,
      token: _grant!.accessToken,
      canWrite: _grant!.user.mayRequestRewards,
    );
  }

  bool matches(AuthLease lease) =>
      !_closed &&
      _foreground &&
      lease.generation == _generation &&
      lease.scope.key == scope?.key;
  void invalidate(AuthLease lease) {
    if (!_closed &&
        lease.generation == _generation &&
        lease.revision == _revision) {
      _clear(RequestCancelReason.replaced);
      _publish(AuthStatus.expired, error: AuthErrorCode.expired);
    }
  }

  void expireIfNeeded() {
    if (_closed || _grant == null || _accessValid) return;
    if (!_canRefresh) _clear(RequestCancelReason.replaced);
    _publish(AuthStatus.expired, error: AuthErrorCode.expired);
  }

  Future<void> logout() async {
    if (_closed) return;
    final grant = _grant;
    final provider = grant == null ? null : _providers[grant.method];
    _clear(RequestCancelReason.logout);
    _publish(AuthStatus.signedOut);
    try {
      await provider?.signOut(grant).timeout(operationTimeout);
    } catch (_) {}
  }

  void suspend() {
    if (_closed) return;
    _foreground = false;
    _publish(value.status, error: value.error);
  }

  void resume() {
    if (_closed) return;
    _foreground = true;
    expireIfNeeded();
    _publish(value.status, error: value.error);
  }

  @override
  void dispose() {
    if (_closed) return;
    _clear(RequestCancelReason.disposed);
    _publish(AuthStatus.signedOut);
    _closed = true;
    _watch.stop();
    super.dispose();
  }
}

class ApiException implements Exception {
  const ApiException(
    this.code, {
    this.statusCode,
    this.serverCode,
    this.dispatched = false,
    this.uncertain = false,
  });
  final ApiErrorCode code;
  final int? statusCode;
  final String? serverCode;
  final bool dispatched, uncertain;
  @override
  String toString() =>
      'Backend request failed (${code.name}); credentials and response content redacted.';
}

class BackendHttpRequest {
  BackendHttpRequest({
    required this.method,
    required this.uri,
    required this.config,
    this.authorization,
    this.body,
    this.idempotencyKey,
  });
  final String method;
  final Uri uri;
  final BackendConfig config;
  final SecretToken? authorization;
  final Uint8List? body;
  final String? idempotencyKey;
  @override
  String toString() =>
      'BackendHttpRequest($method, credentials and payload redacted)';
}

class BackendHttpResponse {
  BackendHttpResponse({
    required this.statusCode,
    required this.bytes,
    this.contentType = 'application/json',
  });
  final int statusCode;
  final Uint8List bytes;
  final String contentType;
  @override
  String toString() =>
      'BackendHttpResponse(status: $statusCode, body redacted)';
}

abstract interface class BackendTransport {
  Future<BackendHttpResponse> send(
    BackendHttpRequest request,
    RequestCancellation cancellation,
  );
  void close();
}

class IoBackendTransport implements BackendTransport {
  final Set<HttpClient> _clients = {};
  bool _closed = false;
  @override
  Future<BackendHttpResponse> send(
    BackendHttpRequest request,
    RequestCancellation cancellation,
  ) async {
    if (_closed ||
        cancellation.cancelled ||
        !request.config.permits(request.uri)) {
      throw const ApiException(ApiErrorCode.cancelled);
    }
    final client = HttpClient()
      ..connectionTimeout = request.config.connectTimeout
      ..autoUncompress = false;
    client.findProxy = (_) => 'DIRECT';
    _clients.add(client);
    HttpClientRequest? active;
    final unlisten = cancellation.listen(() {
      try {
        active?.abort();
      } catch (_) {}
      client.close(force: true);
    });
    try {
      active = await client
          .openUrl(request.method, request.uri)
          .timeout(request.config.connectTimeout);
      if (cancellation.cancelled) {
        throw const ApiException(ApiErrorCode.cancelled);
      }
      unawaited(
        active.done.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
      active.followRedirects = false;
      active.headers.set(HttpHeaders.acceptHeader, 'application/json');
      active.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.authorization?.use(
        (token) => active!.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $token',
        ),
      );
      if (request.idempotencyKey != null) {
        active.headers.set('Idempotency-Key', request.idempotencyKey!);
      }
      if (request.body != null) {
        active.headers.contentType = ContentType.json;
        active.contentLength = request.body!.length;
        active.add(request.body!);
        await active.flush().timeout(request.config.uploadTimeout);
      }
      final response = await active.close().timeout(
        request.config.requestTimeout,
      );
      if (response.contentLength > request.config.maxResponseBytes) {
        throw const ApiException(ApiErrorCode.malformed);
      }
      final result = BytesBuilder(copy: false);
      await for (final bytes in response.timeout(
        request.config.downloadTimeout,
      )) {
        if (cancellation.cancelled) {
          throw const ApiException(ApiErrorCode.cancelled);
        }
        if (result.length + bytes.length > request.config.maxResponseBytes) {
          throw const ApiException(ApiErrorCode.malformed);
        }
        result.add(bytes);
      }
      return BackendHttpResponse(
        statusCode: response.statusCode,
        bytes: result.takeBytes(),
        contentType: response.headers.contentType?.mimeType ?? '',
      );
    } finally {
      unlisten();
      _clients.remove(client);
      client.close(force: true);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class AuthenticatedApiClient {
  AuthenticatedApiClient({
    required this.config,
    required this.auth,
    BackendTransport? transport,
  }) : transport = transport ?? IoBackendTransport() {
    if (config.baseUrl != auth.config.baseUrl ||
        config.apiVersion != auth.config.apiVersion ||
        config.enabled != auth.config.enabled) {
      throw const BackendConfigurationException();
    }
    auth.addListener(_authChanged);
  }
  final BackendConfig config;
  final AuthSessionService auth;
  final BackendTransport transport;
  final Map<RequestCancellation, AuthLease?> _active = {};
  bool _closed = false;
  int get activeRequests => _active.length;
  void _authChanged() {
    for (final entry in _active.entries.toList()) {
      final lease = entry.value;
      if (!auth.value.foreground || lease != null && !auth.matches(lease)) {
        entry.key.cancel(
          !auth.value.foreground
              ? RequestCancelReason.background
              : RequestCancelReason.logout,
        );
      }
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) async {
    if (_closed || !config.enabled) {
      throw const ApiException(ApiErrorCode.configuration);
    }
    if (method != 'GET' && method != 'POST' ||
        method == 'GET' && body != null ||
        method == 'POST' && (body == null || idempotencyKey == null)) {
      throw const ApiException(ApiErrorCode.invalidRequest);
    }
    if (idempotencyKey != null) coinId(idempotencyKey, 'idempotencyKey');
    final params = <String, String>{};
    for (final item in query.entries) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(item.key) ||
          RegExp(
            r'token|password|secret|authorization|credential|cookie',
            caseSensitive: false,
          ).hasMatch(item.key)) {
        throw const ApiException(ApiErrorCode.invalidRequest);
      }
      final value = item.value;
      if (value == null) continue;
      if (value is! String && value is! int && value is! bool ||
          value.toString().length > 2048) {
        throw const ApiException(ApiErrorCode.invalidRequest);
      }
      params[item.key] = value.toString();
    }
    late Uri uri;
    late Uint8List? bytes;
    try {
      uri = config.endpoint(path, query: params);
      bytes = body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body)));
      if (bytes != null && bytes.length > config.maxRequestBytes) {
        throw const FormatException();
      }
    } catch (_) {
      throw const ApiException(ApiErrorCode.invalidRequest);
    }
    AuthLease? lease;
    try {
      if (authenticated) lease = await auth.acquire(write: method == 'POST');
    } on AuthSessionException catch (error) {
      throw _authError(error);
    }
    final originalGeneration = lease?.generation;
    final originalScope = lease?.scope.key;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (_closed || authenticated && (lease == null || !auth.matches(lease))) {
        throw const ApiException(ApiErrorCode.stale);
      }
      if (_active.length >= config.maxConcurrentRequests) {
        throw const ApiException(ApiErrorCode.rateLimited);
      }
      final cancellation = RequestCancellation();
      _active[cancellation] = lease;
      final deadline = Timer(
        config.requestTimeout,
        () => cancellation.cancel(RequestCancelReason.timeout),
      );
      BackendHttpResponse response;
      var dispatched = false;
      try {
        if (_closed ||
            !auth.value.foreground ||
            authenticated && !auth.matches(lease!)) {
          throw const ApiException(ApiErrorCode.stale);
        }
        dispatched = true;
        response = await transport
            .send(
              BackendHttpRequest(
                method: method,
                uri: uri,
                config: config,
                authorization: lease?.token,
                body: bytes,
                idempotencyKey: idempotencyKey,
              ),
              cancellation,
            )
            .timeout(config.requestTimeout);
        if (cancellation.cancelled || authenticated && !auth.matches(lease!)) {
          throw const ApiException(ApiErrorCode.stale);
        }
      } catch (error) {
        final code =
            cancellation.reason == RequestCancelReason.timeout ||
                error is TimeoutException
            ? ApiErrorCode.timeout
            : cancellation.cancelled
            ? ApiErrorCode.cancelled
            : error is ApiException
            ? error.code
            : ApiErrorCode.network;
        throw ApiException(
          code,
          dispatched: dispatched,
          uncertain: method == 'POST' && dispatched,
        );
      } finally {
        deadline.cancel();
        _active.remove(cancellation);
      }
      if (response.statusCode == 401 && authenticated && lease != null) {
        if (method == 'GET' && attempt == 0) {
          try {
            await auth.refreshSession(rejectedRevision: lease.revision);
            if (auth.value.generation != originalGeneration ||
                auth.scope?.key != originalScope) {
              throw const AuthSessionException(AuthErrorCode.stale);
            }
            lease = await auth.acquire();
            continue;
          } on AuthSessionException catch (error) {
            throw _authError(error);
          }
        }
        auth.invalidate(lease);
        throw ApiException(
          ApiErrorCode.unauthenticated,
          statusCode: 401,
          dispatched: true,
        );
      }
      if (response.statusCode != 200) {
        final serverCode = _serverCode(response);
        final code = switch (response.statusCode) {
          400 || 422 => ApiErrorCode.invalidRequest,
          403 => ApiErrorCode.restricted,
          404 => ApiErrorCode.notFound,
          409 => ApiErrorCode.conflict,
          429 => ApiErrorCode.rateLimited,
          _ => ApiErrorCode.server,
        };
        throw ApiException(
          code,
          statusCode: response.statusCode,
          serverCode: serverCode,
          dispatched: true,
          uncertain:
              method == 'POST' &&
              (response.statusCode >= 500 ||
                  response.statusCode >= 300 && response.statusCode < 400),
        );
      }
      try {
        return _decode(response);
      } catch (_) {
        throw ApiException(
          ApiErrorCode.malformed,
          dispatched: true,
          uncertain: method == 'POST',
        );
      }
    }
    throw const ApiException(ApiErrorCode.unauthenticated);
  }

  Map<String, dynamic> _decode(BackendHttpResponse response) {
    if (response.bytes.length > config.maxResponseBytes ||
        !(response.contentType == 'application/json' ||
            response.contentType.endsWith('+json'))) {
      throw const FormatException();
    }
    final text = utf8.decode(response.bytes);
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final rune in text.runes) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (rune == 92) {
          escaped = true;
        } else if (rune == 34) {
          quoted = false;
        }
      } else if (rune == 34) {
        quoted = true;
      } else if (rune == 123 || rune == 91) {
        depth += 1;
        if (depth > 32) throw const FormatException();
      } else if (rune == 125 || rune == 93) {
        depth -= 1;
        if (depth < 0) throw const FormatException();
      }
    }
    if (quoted || depth != 0) throw const FormatException();
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic>) throw const FormatException();
    return data;
  }

  String? _serverCode(BackendHttpResponse response) {
    try {
      final json = _decode(response);
      final error = json['error'];
      final code = error is Map<String, dynamic> ? error['code'] : json['code'];
      const allowed = {
        'unauthenticated',
        'restricted',
        'conflict',
        'below_minimum',
        'insufficient_balance',
        'payout_unavailable',
        'policy_changed',
        'not_found',
        'rate_limited',
        'invalid_request',
        'invalid_provider_signature',
        'expired_offer',
        'cooldown',
        'daily_limit',
        'duplicate_event',
      };
      return code is String && allowed.contains(code) ? code : null;
    } catch (_) {
      return null;
    }
  }

  ApiException _authError(AuthSessionException error) =>
      ApiException(switch (error.code) {
        AuthErrorCode.restricted => ApiErrorCode.restricted,
        AuthErrorCode.stale => ApiErrorCode.stale,
        AuthErrorCode.cancelled ||
        AuthErrorCode.disposed => ApiErrorCode.cancelled,
        _ => ApiErrorCode.unauthenticated,
      });
  void dispose() {
    if (_closed) return;
    _closed = true;
    auth.removeListener(_authChanged);
    for (final cancellation in _active.keys.toList()) {
      cancellation.cancel(RequestCancelReason.disposed);
    }
    _active.clear();
    transport.close();
  }
}
```

## File 33 — `lib/services/authenticated_backend_repository.dart` — NEW

```dart
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
```

## File 34 — `lib/services/rewarded_ad_provider.dart` — NEW

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../screens/reward_center_screen.dart' show RewardedAdAdapter;
import 'share_coin_service.dart'
    show ShareCoinException, CoinErrorCode, newCoinRequestId;

enum AdProviderState {
  unavailable,
  loading,
  ready,
  showing,
  completed,
  dismissed,
  failed,
}

enum AdEvidenceResult { loaded, shown, completed, dismissed, failed }

class AdLoadContext {
  AdLoadContext({
    required this.attemptId,
    required this.rewardSessionId,
    required this.userId,
    required this.provider,
    required this.adUnit,
  });
  final String attemptId, rewardSessionId, userId, provider, adUnit;
  // A real SDK driver must bind userId + rewardSessionId to provider SSV
  // custom data and send verification evidence to the backend, not this UI.
  @override
  String toString() =>
      'AdLoadContext(provider: $provider, session identifiers redacted)';
}

class AdProviderEvidence {
  AdProviderEvidence({
    required String attemptId,
    required String rewardSessionId,
    required String provider,
    required String adUnit,
    required int sequence,
    required this.result,
    required DateTime timestamp,
    String? providerEventId,
  }) : attemptId = coinId(attemptId, 'attemptId'),
       rewardSessionId = coinId(rewardSessionId, 'rewardSessionId'),
       provider = coinId(provider, 'provider'),
       adUnit = coinText(adUnit, 'adUnit', max: 160),
       sequence = coinInt(sequence, 'sequence', min: 1),
       timestamp = coinTime(timestamp, 'evidence timestamp'),
       providerEventId = coinOptionalId(providerEventId, 'providerEventId') {
    if (result == AdEvidenceResult.completed && providerEventId == null) {
      throw const CoinModelException('provider completion reference');
    }
  }
  final String attemptId, rewardSessionId, provider, adUnit;
  final String? providerEventId;
  final int sequence;
  final AdEvidenceResult result;
  final DateTime timestamp;
  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'rewardSessionId': rewardSessionId,
    'provider': provider,
    'adUnit': adUnit,
    'providerEventId': providerEventId,
    'sequence': sequence,
    'result': result.name,
    'timestamp': timestamp.toIso8601String(),
  };
  @override
  String toString() =>
      'AdProviderEvidence(${result.name}, no trusted coin amount)';
}

abstract interface class RewardedAdSdkDriver {
  bool get configured;
  String? get provider;
  Stream<AdProviderEvidence> get evidence;
  Future<void> load(AdLoadContext context);
  Future<void> show(AdLoadContext context);
  Future<void> dismiss();
  Future<void> dispose();
}

class UnavailableRewardedAdSdkDriver implements RewardedAdSdkDriver {
  const UnavailableRewardedAdSdkDriver();
  @override
  bool get configured => false;
  @override
  String? get provider => null;
  @override
  Stream<AdProviderEvidence> get evidence =>
      const Stream<AdProviderEvidence>.empty();
  @override
  Future<void> load(AdLoadContext context) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> show(AdLoadContext context) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> dismiss() async {}
  @override
  Future<void> dispose() async {}
}

RewardedAdAdapter createSafeRewardedAdProvider() => RewardedAdProvider();

// Implements the existing Part 6 adapter. No financial amount is emitted.
// The default driver cannot load, play or complete an ad.
class RewardedAdProvider extends ValueNotifier<AdProviderState>
    implements RewardedAdAdapter {
  RewardedAdProvider({
    RewardedAdSdkDriver? driver,
    this.loadTimeout = const Duration(seconds: 30),
  }) : driver = driver ?? const UnavailableRewardedAdSdkDriver(),
       super(AdProviderState.unavailable) {
    if (loadTimeout <= Duration.zero ||
        loadTimeout > const Duration(minutes: 2)) {
      throw ArgumentError('Invalid ad timeout.');
    }
    _subscription = this.driver.evidence.listen(
      _evidence,
      onError: (Object error, StackTrace stack) {
        if (!_closed && !_completed) _fail();
      },
    );
  }
  final RewardedAdSdkDriver driver;
  final Duration loadTimeout;
  final StreamController<RewardedAdEvent> _events =
      StreamController<RewardedAdEvent>.broadcast();
  final StreamController<AdProviderEvidence> _evidenceEvents =
      StreamController<AdProviderEvidence>.broadcast();
  late final StreamSubscription<AdProviderEvidence> _subscription;
  AdLoadContext? _context;
  Completer<void>? _ready;
  Future<void>? _loading;
  int _generation = 0, _sequence = 0;
  bool _closed = false,
      _showRequested = false,
      _shown = false,
      _completed = false;
  AdProviderEvidence? _lastEvidence;
  @override
  bool get configured =>
      !_closed && driver.configured && driver.provider != null;
  @override
  String? get provider => driver.provider;
  @override
  Stream<RewardedAdEvent> get events => _events.stream;
  Stream<AdProviderEvidence> get completionEvidence => _evidenceEvents.stream;
  AdProviderEvidence? get lastEvidence => _lastEvidence;

  void _state(AdProviderState state) {
    if (!_closed) value = state;
  }

  void _emitEvent(RewardedAdEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  void _fail() {
    if (_closed || _completed) return;
    _state(AdProviderState.failed);
    final pending = _ready;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const ShareCoinException(CoinErrorCode.unavailable),
      );
    }
    final context = _context;
    if (context != null && !_events.isClosed) {
      _emitEvent(
        RewardedAdEvent(
          sessionId: context.rewardSessionId,
          type: RewardedAdEventType.failed,
        ),
      );
    }
  }

  @override
  Future<void> load(RewardSession session, AdConfiguration configuration) {
    if (!configured) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.notConfigured),
      );
    }
    if (_loading != null && _context?.rewardSessionId == session.sessionId) {
      return _loading!;
    }
    if (_loading != null || _showRequested && !_completed) {
      return Future.error(const ShareCoinException(CoinErrorCode.conflict));
    }
    if (session.source != CoinSource.adReward ||
        session.provider != provider ||
        configuration.provider != provider ||
        !configuration.rewardedEnabled ||
        configuration.premium ||
        configuration.units['rewarded'] == null) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final context = AdLoadContext(
      attemptId: newCoinRequestId(),
      rewardSessionId: session.sessionId,
      userId: session.userId,
      provider: session.provider,
      adUnit: configuration.units['rewarded']!,
    );
    final generation = ++_generation;
    _context = context;
    _sequence = 0;
    _shown = false;
    _showRequested = false;
    _completed = false;
    _lastEvidence = null;
    final ready = Completer<void>();
    _ready = ready;
    unawaited(
      ready.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    final complete = Completer<void>();
    _loading = complete.future;
    _state(AdProviderState.loading);
    Future<void>(() async {
      try {
        await driver.load(context).timeout(loadTimeout);
        await ready.future.timeout(loadTimeout);
        if (_closed ||
            generation != _generation ||
            value != AdProviderState.ready) {
          throw const ShareCoinException(CoinErrorCode.disposed);
        }
        complete.complete();
      } catch (_) {
        if (!_closed && generation == _generation) _fail();
        complete.completeError(
          const ShareCoinException(CoinErrorCode.unavailable),
        );
      } finally {
        if (identical(_loading, complete.future)) _loading = null;
      }
    });
    return complete.future;
  }

  @override
  Future<void> show(String sessionId) async {
    final context = _context;
    if (_closed ||
        context == null ||
        context.rewardSessionId != sessionId ||
        value != AdProviderState.ready ||
        _showRequested) {
      throw const ShareCoinException(CoinErrorCode.invalidRequest);
    }
    _showRequested = true;
    try {
      await driver.show(context);
    } catch (_) {
      _fail();
      throw const ShareCoinException(CoinErrorCode.unavailable);
    }
  }

  void _evidence(AdProviderEvidence evidence) {
    final context = _context;
    if (_closed ||
        context == null ||
        evidence.attemptId != context.attemptId ||
        evidence.rewardSessionId != context.rewardSessionId ||
        evidence.provider != context.provider ||
        evidence.adUnit != context.adUnit ||
        evidence.sequence <= _sequence ||
        _completed) {
      return;
    }
    switch (evidence.result) {
      case AdEvidenceResult.loaded:
        if (value != AdProviderState.loading) return;
        _sequence = evidence.sequence;
        _state(AdProviderState.ready);
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.ready,
          ),
        );
      case AdEvidenceResult.shown:
        if (!_showRequested || _shown || value != AdProviderState.ready) return;
        _sequence = evidence.sequence;
        _shown = true;
        _state(AdProviderState.showing);
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.shown,
          ),
        );
      case AdEvidenceResult.completed:
        if (!_shown ||
            !_showRequested ||
            value != AdProviderState.showing ||
            evidence.providerEventId == null) {
          return;
        }
        _sequence = evidence.sequence;
        _completed = true;
        _lastEvidence = evidence;
        _state(AdProviderState.completed);
        if (!_closed && !_evidenceEvents.isClosed) {
          _evidenceEvents.add(evidence);
        }
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.completed,
            providerEventId: evidence.providerEventId,
          ),
        );
      case AdEvidenceResult.dismissed:
        if (!_shown) {
          _fail();
          return;
        }
        _sequence = evidence.sequence;
        _state(AdProviderState.dismissed);
        _showRequested = false;
        _emitEvent(
          RewardedAdEvent(
            sessionId: context.rewardSessionId,
            type: RewardedAdEventType.skipped,
          ),
        );
      case AdEvidenceResult.failed:
        _fail();
    }
  }

  @override
  Future<void> dismiss() async {
    if (_closed) return;
    _generation += 1;
    _context = null;
    _showRequested = false;
    _shown = false;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const ShareCoinException(CoinErrorCode.disposed));
    }
    _state(AdProviderState.dismissed);
    try {
      await driver.dismiss();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    _context = null;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const ShareCoinException(CoinErrorCode.disposed));
    }
    await _subscription.cancel();
    try {
      await driver.dispose();
    } catch (_) {}
    await _events.close();
    await _evidenceEvents.close();
    super.dispose();
  }
}
```

## File 35 — `test/backend_auth_rewards_test.dart` — NEW

```dart
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
```

## Required integration replacements — complete files

## File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.7.0+7

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: 12.2.0
  basic_utils: 5.8.2
  crypto: 3.0.7
  path_provider: 2.1.6
  share_plus: 13.3.0
  qr_flutter: 4.1.0
  mobile_scanner: 7.4.0
  path: 1.9.1
  url_launcher: 6.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0

flutter:
  uses-material-design: true
```

## File 25 — `lib/screens/share_coin_home_screen.dart` — UPDATED

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../services/connectivity_service.dart';
import '../services/share_coin_service.dart';
import '../config/backend_config.dart';
import '../services/auth_session_service.dart';
import '../services/authenticated_backend_repository.dart';
import '../services/rewarded_ad_provider.dart';
import '../services/offerwall_service.dart';
import 'offerwall_screen.dart';
import 'reward_center_screen.dart';

enum ShareCoinFileAction { send, receive, saved, history }

class ShareCoinHomeScreen extends StatefulWidget {
  const ShareCoinHomeScreen({
    super.key,
    this.service,
    this.onFileAction,
    this.offerPolicy,
    this.adFactory = createSafeRewardedAdProvider,
    this.backendConfig,
    this.auth,
    this.linkLauncher = launchRewardLink,
  });
  final ShareCoinService? service;
  final BackendConfig? backendConfig;
  final AuthSessionService? auth;
  final ValueChanged<ShareCoinFileAction>? onFileAction;
  final OfferResourcePolicy? offerPolicy;
  final RewardedAdAdapter Function() adFactory;
  final RewardLinkLauncher linkLauncher;
  @override
  State<ShareCoinHomeScreen> createState() => _ShareCoinHomeScreenState();
}

class _ShareCoinHomeScreenState extends State<ShareCoinHomeScreen>
    with WidgetsBindingObserver {
  late final ShareCoinService _service;
  late final bool _ownsService;
  AuthSessionService? _auth;
  AuthenticatedShareCoinBackend? _backend;
  bool _ownsAuth = false;
  CoinData<ShareCoinBalance>? _wallet;
  CoinData<ShareCoinUser>? _user;
  String? _scopeKey;
  String? _notice;
  String? _busyAction;
  bool _loading = false;
  bool _closed = false;
  bool _navigating = false;
  int _generation = 0;
  bool get _canUpdate => mounted && !_closed;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    if (widget.service != null) {
      _service = widget.service!;
      _auth = widget.auth;
    } else {
      final config =
          widget.backendConfig ??
          widget.auth?.config ??
          BackendConfig.fromEnvironment();
      _ownsAuth = widget.auth == null;
      _auth = widget.auth ?? AuthSessionService(config: config);
      _backend = AuthenticatedShareCoinBackend(config: config, auth: _auth!);
      _service = ShareCoinService(
        backend: _backend,
        requestTimeout:
            config.requestTimeout +
            _auth!.operationTimeout +
            const Duration(seconds: 1),
      );
    }
    _auth?.addListener(_authChanged);
    _scopeKey = _service.accountKey;
    _service.addListener(_serviceChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _authChanged() {
    if (!_canUpdate) return;
    _serviceChanged();
    setState(() {});
  }

  Future<void> _account() async {
    final auth = _auth;
    if (auth == null) {
      await _info(
        'Account integration',
        'This service was supplied externally. Its authentication adapter owns account management.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<AuthSessionSnapshot>(
        valueListenable: auth,
        builder: (context, state, child) => AlertDialog(
          title: const Text('Account / API session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Session: ${state.status.name}',
                  key: const ValueKey('auth-session-status'),
                ),
                if (state.user != null) Text(state.user!.displayName),
                if (state.error != null)
                  Text(AuthSessionException(state.error!).message),
                const SizedBox(height: 12),
                const Text(
                  'No login provider or production credentials are bundled. A real adapter must verify identity through the configured backend.',
                ),
                const SizedBox(height: 12),
                for (final method in AuthenticationMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      key: ValueKey('auth-sign-in-${method.name}'),
                      onPressed:
                          !auth.availableMethods.contains(method) ||
                              state.status == AuthStatus.authenticating ||
                              state.status == AuthStatus.refreshing
                          ? null
                          : () async {
                              try {
                                await auth.signIn(method);
                              } catch (_) {}
                              if (_canUpdate) unawaited(_refresh());
                            },
                      child: Text(switch (method) {
                        AuthenticationMethod.google => 'Google',
                        AuthenticationMethod.apple => 'Apple',
                        AuthenticationMethod.emailOtp => 'Email / OTP',
                        AuthenticationMethod.phoneOtp => 'Phone / OTP',
                      }),
                    ),
                  ),
                if (state.scope != null)
                  FilledButton(
                    key: const ValueKey('auth-sign-out'),
                    onPressed: () async {
                      await auth.logout();
                    },
                    child: const Text('Sign out'),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _serviceChanged() {
    if (!_canUpdate) return;
    final next = _service.accountKey;
    if (next != _scopeKey) {
      _generation += 1;
      setState(() {
        _scopeKey = next;
        _wallet = null;
        _user = null;
        _busyAction = null;
        _loading = false;
        _notice = 'Account changed. Refresh to load this account.';
      });
    } else if (_service.cachedWallet == null && _wallet != null) {
      setState(() => _wallet = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      _auth?.suspend();
      _service.suspend();
      if (_canUpdate) {
        setState(() {
          _loading = false;
          _busyAction = null;
          _notice =
              'ShareCoin refresh paused. File sharing has its own lifecycle.';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _auth?.resume();
      _service.resume();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_serviceChanged);
    _auth?.removeListener(_authChanged);
    if (_ownsService) _service.dispose();
    _backend?.dispose();
    if (_ownsAuth) _auth?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || _busyAction != null) return;
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      await _service.connectivity.refresh();
      if (!_service.backendConfigured) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Backend and sign-in integration are not configured. No real funds are shown.',
          );
        }
        return;
      }
      if (!_service.hasAccount) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Account setup required. No authentication provider is integrated in this foundation.',
          );
        }
        return;
      }
      final user = await _service.getCurrentUser();
      final wallet = await _service.getCurrentWallet();
      if (_canUpdate &&
          generation == _generation &&
          scope == _service.accountKey) {
        setState(() {
          _user = user;
          _wallet = wallet;
          _scopeKey = scope;
        });
      }
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        setState(() {
          _wallet = _service.cachedWallet;
          _notice = _errorText(error);
        });
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _errorText(Object error) => error is ShareCoinException
      ? error.message
      : 'ShareCoin could not load this information. No local reward or payout was created.';
  String _time(DateTime date) => date.toLocal().toString().split('.').first;
  String _coins(int coins) => coins.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );

  void _fileAction(ShareCoinFileAction action) {
    final callback = widget.onFileAction;
    if (callback != null) {
      callback(action);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(action);
    }
  }

  Future<void> _info(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _details(
    String title,
    Future<List<Widget>> Function() load,
  ) async {
    if (_busyAction != null || _loading) return;
    final scope = _service.accountKey;
    final generation = ++_generation;
    setState(() => _busyAction = title);
    try {
      final rows = await load();
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: _service,
          builder: (context, child) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: scope != _service.accountKey
                  ? const Text('Account changed. Close this view and refresh.')
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                      ),
                      child: ListView(shrinkWrap: true, children: rows),
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info(title, _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
      }
    }
  }

  Widget _origin<T>(CoinData<T> data) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      '${data.cached ? 'Cached data' : 'Backend response'} · ${_time(data.serverTime)}',
      style: const TextStyle(fontSize: 12),
    ),
  );

  Future<void> _openOfferwall() async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => OfferwallScreen(
            service: _service,
            policy: widget.offerPolicy,
            launcher: widget.linkLauncher,
            onCatalogInfo: _offers,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

  Future<void> _openRewardCenter(
    RewardCenterMode mode,
    VoidCallback configuration,
  ) async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => RewardCenterScreen(
            service: _service,
            mode: mode,
            policy: widget.offerPolicy,
            adFactory: widget.adFactory,
            launcher: widget.linkLauncher,
            onConfiguration: configuration,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

  Future<void> _ads() => _details('Watch Ads', () async {
    final data = await _service.getAdConfiguration();
    return <Widget>[
      _origin(data),
      Text('Provider: ${data.data.provider ?? 'Not configured'}'),
      Text(
        'Rewarded ads: ${data.data.rewardedEnabled && !data.data.premium ? 'Enabled in backend configuration' : 'Disabled'}',
      ),
      Text(
        'Cooldown: ${data.data.cooldownSeconds}s · Daily limit: ${data.data.dailyLimit}',
      ),
      Text('Premium/no-ads: ${data.data.premium ? 'Yes' : 'No'}'),
      const SizedBox(height: 12),
      const Text(
        'No ad SDK is bundled. A configured provider completion is only an event claim; the backend must verify it before crediting ShareCoin.',
      ),
    ];
  });

  Future<void> _offers() => _details('Offers', () async {
    final data = await _service.getOffers(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text(
        'Catalog foundation. Starting/installing an app is not proof of earning a reward.',
      ),
      if (data.data.items.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('No offers returned for this account.'),
        ),
      for (final offer in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.apps_rounded),
          title: Text(offer.title),
          subtitle: Text(
            '${offer.publisher} · ${offer.category.name}\nPotential reward: ${offer.rewardCoins} ShareCoin · ${offer.status.name}',
          ),
        ),
      if (data.data.info.hasNext)
        Text(
          'Showing ${data.data.items.length} of ${data.data.info.total}. The service supports paginated queries; this dashboard is a bounded catalog preview.',
        ),
    ];
  });

  Future<void> _promotions() => _details('Promotions', () async {
    final data = await _service.getPromotions(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text('Opening a campaign never credits coins in this client.'),
      if (data.data.items.isEmpty) const Text('No promotions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined),
          title: Text(item.title),
          subtitle: Text(
            '${item.advertiser}\nPotential reward: ${item.rewardCoins} ShareCoin · ${item.status.name}\nEnds ${_time(item.endsAt)}',
          ),
        ),
    ];
  });

  Future<void> _daily() => _details('Daily Reward', () async {
    final data = await _service.getDailyRewardConfiguration();
    return <Widget>[
      _origin(data),
      Text('Backend streak day: ${data.data.streakDay}'),
      Text(
        'Backend eligibility: ${data.data.eligible ? 'Eligible according to this response' : 'Not eligible'}',
      ),
      for (var index = 0; index < data.data.dayRewards.length; index += 1)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Day ${index + 1}'),
          trailing: Text('${data.data.dayRewards[index]} ShareCoin'),
        ),
      Text('Next eligible: ${_time(data.data.nextEligibleAt)}'),
      const SizedBox(height: 12),
      const Text(
        'This is the server-configured policy view, not a local claim button. Device date does not award money.',
      ),
    ];
  });

  Future<void> _referral() => _details('Referral', () async {
    final data = await _service.getReferral();
    return <Widget>[
      _origin(data),
      SelectableText(
        data.data.referralCode,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      Text(
        'Invited: ${data.data.invitedCount} · Pending: ${data.data.pendingCount} · Qualified: ${data.data.qualifiedCount}',
      ),
      Text('Backend referral earnings: ${data.data.earnedCoins} ShareCoin'),
      Text('Status: ${data.data.status.name}'),
      if (data.data.referralUrl != null)
        SelectableText(data.data.referralUrl.toString()),
      const SizedBox(height: 12),
      const Text(
        'Referrals require backend qualification and anti-abuse checks. Multiple local accounts do not earn rewards.',
      ),
      TextButton(
        onPressed: () async {
          if (data.accountKey == _service.accountKey) {
            await Clipboard.setData(
              ClipboardData(text: data.data.referralCode),
            );
          }
        },
        child: const Text('Copy referral code'),
      ),
    ];
  });

  Future<void> _transactions() => _details('Transactions', () async {
    final data = await _service.getTransactionHistory(
      query: OfferQuery(pageSize: 30),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty) const Text('No transactions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          isThreeLine: true,
          title: Text(item.signedAmount),
          subtitle: Text(
            '${item.source.name} · ${item.status.name}\n${_time(item.createdAt)} · ${item.transactionId}\n${item.description}',
          ),
        ),
      if (data.data.info.hasNext)
        const Text(
          'More transactions are available through the paginated service. Rejected and reversed entries are not hidden.',
        ),
    ];
  });

  Future<void> _withdrawals() => _details('Withdrawal History', () async {
    final data = await _service.getWithdrawalHistory(
      query: OfferQuery(pageSize: 20),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty)
        const Text('No withdrawal records returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${item.requestedCoins} ShareCoin · ${item.status.name}'),
          subtitle: Text(
            '${item.method.name} · ${item.maskedDestination}\n${item.rate.formatMinor(item.finalPayoutMinor)} · ${item.withdrawalId}\n${item.rejectionReason ?? 'Status provided by the backend'}',
          ),
        ),
    ];
  });

  Future<void> _withdraw() async {
    if (_busyAction != null || _loading) return;
    if (!_service.backendConfigured ||
        !_service.hasAccount ||
        !_service.connectivity.value.canRequestRewards) {
      await _info(
        'Withdrawals unavailable',
        'A backend-authenticated account, reachable ShareCoin service, fresh balance, payout policy and connected saved destination are required. No submission was made. bKash, Nagad, Rocket, PayPal and Bank are configuration options only, not connected providers.',
      );
      return;
    }
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() => _busyAction = 'Withdraw');
    try {
      final user = await _service.getCurrentUser(allowCached: false);
      if (!user.data.mayRequestRewards) {
        throw const ShareCoinException(CoinErrorCode.restricted);
      }
      final wallet = await _service.getCurrentWallet(allowCached: false);
      final policy = await _service.getWithdrawalPolicy(allowCached: false);
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _WithdrawalDialog(
          service: _service,
          wallet: wallet,
          policy: policy,
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info('Withdraw', _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('share-coin-home'),
      appBar: AppBar(
        title: const Text('ShareCoin'),
        toolbarHeight: 70,
        actions: <Widget>[
          IconButton(
            key: const ValueKey('refresh-share-coin'),
            onPressed: _loading || _busyAction != null ? null : _refresh,
            tooltip: 'Refresh ShareCoin status',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            key: const ValueKey('share-coin-account'),
            tooltip: 'Account session',
            onPressed: _account,
            icon: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  _balance(theme),
                  if (_loading || _busyAction != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_notice != null) _CoinNotice(message: _notice!),
                  const SizedBox(height: 22),
                  _section('Earn', 'Actions create claims, not local money.'),
                  _grid(<Widget>[
                    _tile(
                      'Watch Ads',
                      Icons.play_circle_outline_rounded,
                      () => _openRewardCenter(RewardCenterMode.ad, _ads),
                      'Provider / backend required',
                      key: 'coin-watch-ads',
                    ),
                    _tile(
                      'Offers',
                      Icons.apps_rounded,
                      _openOfferwall,
                      'Paginated Offerwall',
                      key: 'coin-offers',
                    ),
                    _tile(
                      'Promotions',
                      Icons.campaign_outlined,
                      () => _openRewardCenter(
                        RewardCenterMode.promotions,
                        _promotions,
                      ),
                      'Campaign verification',
                      key: 'coin-promotions',
                    ),
                    _tile(
                      'Daily Reward',
                      Icons.calendar_today_outlined,
                      () => _openRewardCenter(RewardCenterMode.daily, _daily),
                      'Server eligibility',
                      key: 'coin-daily',
                    ),
                    _tile(
                      'Referral',
                      Icons.people_outline_rounded,
                      _referral,
                      'Qualified invites',
                      key: 'coin-referral',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Wallet',
                    'Only backend-confirmed records are displayed.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Transactions',
                      Icons.receipt_long_outlined,
                      () => _openRewardCenter(
                        RewardCenterMode.transactions,
                        _transactions,
                      ),
                      'Credits, debits, reversals',
                      key: 'coin-transactions',
                    ),
                    _tile(
                      'Withdraw',
                      Icons.account_balance_outlined,
                      _withdraw,
                      'Backend/provider required',
                      key: 'coin-withdraw',
                    ),
                    _tile(
                      'Withdrawal History',
                      Icons.history_rounded,
                      () => _openRewardCenter(
                        RewardCenterMode.withdrawals,
                        _withdrawals,
                      ),
                      'Server payout status',
                      key: 'coin-withdrawal-history',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'File Sharing',
                    'Internet rewards never block your nearby files.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Send Files',
                      Icons.upload_rounded,
                      () => _fileAction(ShareCoinFileAction.send),
                      'Original file flow',
                      key: 'coin-send-files',
                      local: true,
                    ),
                    _tile(
                      'Receive Files',
                      Icons.download_rounded,
                      () => _fileAction(ShareCoinFileAction.receive),
                      'QR or manual pairing',
                      key: 'coin-receive-files',
                      local: true,
                    ),
                    _tile(
                      'Saved Files',
                      Icons.folder_copy_outlined,
                      () => _fileAction(ShareCoinFileAction.saved),
                      'Your received copies',
                      key: 'coin-saved-files',
                      local: true,
                    ),
                    _tile(
                      'History',
                      Icons.fact_check_outlined,
                      () => _fileAction(ShareCoinFileAction.history),
                      'Existing history & SHA-256',
                      key: 'coin-file-history',
                      local: true,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Status',
                    'Local interfaces, internet and backend are separate.',
                  ),
                  ValueListenableBuilder<ConnectivitySnapshot>(
                    valueListenable: _service.connectivity,
                    builder: (context, status, child) => Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Internet: ${status.internetLabel}',
                            key: const ValueKey('coin-internet-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Wi-Fi/local network: ${status.localLabel}',
                            key: const ValueKey('coin-local-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'ShareCoin service: ${status.serviceLabel}',
                            key: const ValueKey('coin-service-status'),
                          ),
                          if (status.stale)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('Status is stale or checking.'),
                            ),
                          const SizedBox(height: 12),
                          const Text(
                            'An IPv4 interface does not prove Wi-Fi type or peer reachability. No public internet probe is configured by default.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Foundation only. No ad attribution, login provider, advertiser payout or cash withdrawal provider is connected by this build. '
                    'ShareCoin is not locally redeemable money. File sharing keeps its existing TLS and approval rules.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _balance(ThemeData theme) {
    final wallet = _wallet;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF164D3C),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.toll_outlined, color: Color(0xFFD5F391)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SHAREBONDHU REWARDS',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'ShareCoin Balance',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            wallet == null
                ? 'Wallet unavailable'
                : '${_coins(wallet.data.available)} ShareCoin',
            key: const ValueKey('share-coin-balance'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (wallet == null)
            Text(
              !_service.hasAccount
                  ? 'Account setup required. A backend-confirmed wallet is needed before any funds can be shown.'
                  : 'Connect to the ShareCoin service and refresh to confirm the current balance.',
              style: TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pending: ${_coins(wallet.data.pending)} ShareCoin',
                  style: const TextStyle(color: Color(0xFFE0EDE5)),
                ),
                const SizedBox(height: 8),
                Text(
                  '${wallet.cached ? 'CACHED · not a live spendable-balance check' : 'Backend response'}\nLast updated: ${_time(wallet.data.updatedAt)}',
                  style: const TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
                ),
              ],
            ),
          if (_user != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${_user!.data.displayName} · ${_user!.data.status.name}',
                style: const TextStyle(color: Color(0xFFD5F391)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _grid(List<Widget> tiles) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560
          ? 3
          : constraints.maxWidth >= 340 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tiles
            .map((tile) => SizedBox(width: width, child: tile))
            .toList(),
      );
    },
  );

  Widget _tile(
    String title,
    IconData icon,
    VoidCallback action,
    String description, {
    required String key,
    bool local = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(18),
        onTap: local || !_loading && _busyAction == null ? action : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colors.primary, size: 26),
              const SizedBox(height: 13),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinNotice extends StatelessWidget {
  const _CoinNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(message),
  );
}

class _WithdrawalDialog extends StatefulWidget {
  const _WithdrawalDialog({
    required this.service,
    required this.wallet,
    required this.policy,
  });
  final ShareCoinService service;
  final CoinData<ShareCoinBalance> wallet;
  final CoinData<WithdrawalPolicy> policy;
  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final TextEditingController _amount = TextEditingController();
  late final ShareCoinReconciler _reconciler;
  PayoutMethodConfig? _method;
  String _idempotencyKey = newCoinRequestId();
  String? _error;
  bool _sending = false;
  bool _uncertain = false;
  WithdrawalRequest? _result;
  bool get _ownerMatches =>
      widget.wallet.accountKey == widget.service.accountKey;

  @override
  void initState() {
    super.initState();
    _reconciler = ShareCoinReconciler(service: widget.service);
    _method = widget.policy.data.methods
        .where((method) => method.usable)
        .firstOrNull;
    _amount.text = widget.policy.data.minimumCoins.toString();
    widget.service.addListener(_update);
    widget.service.connectivity.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_update);
    widget.service.connectivity.removeListener(_update);
    _reconciler.dispose();
    _amount.dispose();
    super.dispose();
  }

  int? get _coins {
    try {
      return coinInt(int.tryParse(_amount.text.trim()), 'coins', min: 1);
    } catch (_) {
      return null;
    }
  }

  int? get _finalMinor {
    final coins = _coins;
    final method = _method;
    if (coins == null || method == null) return null;
    try {
      final value = widget.policy.data.rate.grossMinor(coins) - method.feeMinor;
      return value >= 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _edited() {
    if (!_sending && !_uncertain && _result == null) {
      setState(() {
        _idempotencyKey = newCoinRequestId();
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    final coins = _coins;
    final method = _method;
    final payout = _finalMinor;
    if (_sending ||
        _uncertain ||
        _result != null ||
        !_ownerMatches ||
        !widget.service.connectivity.value.canRequestRewards) {
      return;
    }
    if (coins == null || method == null || payout == null) {
      setState(
        () => _error = 'Enter a valid whole-coin amount and choose a connected destination.',
      );
      return;
    }
    if (coins < widget.policy.data.minimumCoins) {
      setState(() => _error = 'Amount is below the withdrawal minimum.');
      return;
    }
    if (coins > widget.wallet.data.available) {
      setState(() => _error = 'Amount exceeds the displayed backend balance.');
      return;
    }
    setState(() => _sending = true);
    try {
      final response = await widget.service.requestWithdrawal(
        WithdrawalIntent(
          userId: widget.wallet.data.userId,
          coins: coins,
          method: method.method,
          destinationReference: method.destinationReference!,
          policyVersion: widget.policy.data.version,
          expectedFeeMinor: method.feeMinor,
          expectedFinalMinor: payout,
          idempotencyKey: _idempotencyKey,
        ),
      );
      if (mounted && _ownerMatches) setState(() => _result = response.data);
      try {
        final sync = await _reconciler.reconcileWithdrawal(
          withdrawalId: response.data.withdrawalId,
        );
        if (mounted && _ownerMatches) setState(() => _result = sync.request);
      } catch (_) {
        if (mounted && _ownerMatches) {
          setState(
            () => _error = 'Request recorded. Refresh status and wallet to finish synchronization.',
          );
        }
      }
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(() {
          _error = error is ShareCoinException
              ? error.message
              : 'The request could not be confirmed.';
          _uncertain = error is! ShareCoinException || error.outcomeUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkRequest() async {
    if (_sending || !_uncertain || !_ownerMatches) return;
    setState(() => _sending = true);
    try {
      final result = await widget.service.getWithdrawalByKey(_idempotencyKey);
      if (mounted && _ownerMatches) {
        setState(() {
          _result = result.data;
          _uncertain = false;
          _error = null;
        });
      }
      try {
        final sync = await _reconciler.reconcileWithdrawal(
          idempotencyKey: _idempotencyKey,
        );
        if (mounted && _ownerMatches) setState(() => _result = sync.request);
      } catch (_) {
        if (mounted && _ownerMatches) {
          setState(
            () => _error = 'Backend status received. Wallet/history synchronization is still required.',
          );
        }
      }
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(
          () => _error = error is ShareCoinException
              ? error.message
              : 'The request status is still unknown.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy.data;
    final method = _method;
    final payout = _finalMinor;
    final online = widget.service.connectivity.value.canRequestRewards;
    return AlertDialog(
      title: const Text('Withdrawal request'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: !_ownerMatches
              ? const Text('Account changed. Close this form and refresh.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Backend balance: ${widget.wallet.data.available} ShareCoin',
                    ),
                    Text('Minimum: ${policy.minimumCoins} ShareCoin'),
                    Text(
                      'Rate: ${policy.rate.coinUnits} ShareCoin = ${policy.rate.formatMinor(policy.rate.minorUnits)}',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('coin-withdraw-amount'),
                      controller: _amount,
                      enabled: !_sending && !_uncertain && _result == null,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _edited(),
                      decoration: const InputDecoration(
                        labelText: 'Requested ShareCoin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (policy.methods.isNotEmpty)
                      DropdownButtonFormField<PayoutMethod>(
                        initialValue: method?.method,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Payout method',
                          border: OutlineInputBorder(),
                        ),
                        items: policy.methods
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.method,
                                enabled: entry.usable,
                                child: Text(
                                  '${entry.method.name}${entry.usable ? '' : ' · not connected'}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sending || _uncertain || _result != null
                            ? null
                            : (value) {
                                setState(
                                  () => _method = policy.methods
                                      .where((entry) => entry.method == value)
                                      .firstOrNull,
                                );
                                _edited();
                              },
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Saved destination: ${method?.maskedDestination ?? 'Not configured'}',
                    ),
                    Text(
                      'Processing fee: ${method == null ? 'Unavailable' : policy.rate.formatMinor(method.feeMinor)}',
                    ),
                    Text(
                      'Estimated final payout: ${payout == null ? 'Unavailable' : policy.rate.formatMinor(payout)}',
                    ),
                    if (policy.activeRequestIds.isNotEmpty)
                      const Text(
                        'Another withdrawal is active. Submission is disabled.',
                      ),
                    if (!online)
                      const Text(
                        'Service unavailable. No offline withdrawal submission.',
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Submission requests backend validation; it is not proof of payout. The server must recheck the balance, fees, policy and destination.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!),
                      ),
                    if (_uncertain)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SelectableText(
                          'Check backend withdrawal history using request key: $_idempotencyKey. Do not create another request blindly.',
                        ),
                      ),
                    if (_result != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Backend status: ${_result!.status.name}\nReference: ${_result!.withdrawalId}\nBalance must be refreshed from the backend.',
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_uncertain)
          OutlinedButton(
            key: const ValueKey('check-coin-withdrawal-status'),
            onPressed: _sending || !_ownerMatches || !online
                ? null
                : _checkRequest,
            child: const Text('Check request status'),
          ),
        if (_result == null)
          FilledButton(
            key: const ValueKey('submit-coin-withdrawal'),
            onPressed:
                !_ownerMatches ||
                    _sending ||
                    _uncertain ||
                    !online ||
                    method == null ||
                    policy.activeRequestIds.isNotEmpty
                ? null
                : _submit,
            child: Text(_sending ? 'Submitting request' : 'Request withdrawal'),
          ),
      ],
    );
  }
}
```

## File 27 — `lib/services/offerwall_service.dart` — UPDATED

```dart
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
```

## File 29 — `lib/screens/reward_center_screen.dart` — UPDATED

```dart
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
```

## Existing Source Verified

The matching ShareBondhu_Part_06.zip was the authoritative baseline: version 0.6.0+6, 140 entries and 258 documented passing tests. The initial source was byte-identical. Existing Dart APIs/models/services/screens/tests, backend contracts, dependencies and native configuration were inspected before integration.

## Changed Files

NEW: Files 31–35 in order. UPDATED: File 1 (version only), File 25 (optional auth/config/repository/account UI and withdrawal sync), File 27 (offer/wallet reconciliation), File 29 (reward/reversal reconciliation). Complete replacements are included above. Documentation/index/reports are updated; historical archives/guides remain immutable.

All original test files, the single ShareCoinService (File 23), original domain/transfer/history code, native configuration/permissions and pubspec.lock remain byte-identical. Existing functions/classes in updated integration files are retained.

## Dependencies

**No new dependency.** HTTP uses dart:io and existing Flutter facilities. No auth/secure-storage/ad SDK was added. Version is 0.7.0+7; tested Flutter 3.47.2 / Dart 3.13.2.

## Existing Logic Preserved

Keep the original sharing home, file picker/selection, QR/manual pairing, explicit sender action and receiver approval, all five original LAN endpoints, TLS pins/tokens/validation, streaming/SHA-256/atomic commit/receipt, progress/result, cancellation/retry, Saved Files/history and native export. Backend logout does not delete local received files, and reward connectivity does not gate the local transfer path.

Limits remain 50 files, 2 GiB/file, 4 GiB/batch, 10-minute invitation and 60-second receiver approval. The existing ShareCoin models/service, Offerwall, Reward Center, referral/withdrawal and connectivity foundation remain.

## Backend API Contract

AuthenticatedShareCoinBackend now implements concrete HTTP mappings for the existing conceptual Part 5/6 contracts. They are **not remotely verified production endpoints**. All are relative to the configured base/API version:

- GET health, users/me, wallet, wallet/transactions, wallet/transactions/{transactionId}
- POST rewards/events; GET rewards/events and rewards/events/{eventId}
- GET offers and offers/{offerId}; POST offers/{offerId}/start; GET offers/{offerId}/status
- GET offers/starts/{startId}/launch; GET promotions
- POST rewards/sessions; GET rewards/sessions/status
- GET withdrawals/policy; POST withdrawals; GET withdrawals, withdrawals/{withdrawalId}, withdrawals/by-key/{idempotencyKey}
- GET users/me/referral, ads/configuration, rewards/daily/configuration

The original LAN transfer endpoints are untouched. Strict v1 envelope/DTO validation uses existing models and rejects malformed/unsafe financial data. The full config/auth/transport/schema contract is in `docs/PART_07_BACKEND_AUTH_CONTRACT.md`.

Production/staging require HTTPS. Only explicit development loopback HTTP is allowed; no native cleartext exception or certificate bypass was added. No remote production host/secrets are hard-coded. Invalid/missing environment configuration disables backend access.

## Authentication Flow

**Configured Provider Login → Backend-Validated AuthGrant → Session → Authenticated API → User Scope → Logout**

No Google/Apple/OTP SDK is falsely integrated. Tokens are opaque, memory-only and redacted from diagnostics/JSON snapshots. Refresh is single-flight and preserves identity; old results cannot resurrect logged-out/switched accounts. Logout invalidates scope/cache and cancels authenticated requests before provider cleanup. GET may refresh/retry once; financial POST is never automatically replayed.

## Reward Flow

**Action → Provider Evidence → Existing RewardEvent → Backend Verification → Owned Transaction → Fresh Wallet → Reconciled Display**

ShareCoinReconciler wraps the existing service; it never computes a wallet increment. Completed display requires the matching ledger transaction and a fresh owned noncached wallet. Pending/rejected/reversed/unknown outcomes remain distinct. Local synchronization markers are not a financial ledger and are invalidated on account change.

RewardedAdProvider implements the existing adapter over a real SDK-driver boundary. Default driver unavailable; no playback or completion is simulated. Evidence carries provider/unit/session/event/time/outcome, not a trusted coin amount.

## Withdrawal Flow

**Fresh Wallet/Policy → Idempotent Request → Backend Validation → Processing → Backend Paid/Rejected Status → Transaction/Wallet Refresh**

Existing minimum/balance/conflict/quote/destination/idempotency checks remain. Request/status acknowledgment is synchronized through the same service. The client never changes pending to paid or subtracts/refunds coins locally. An already-sent write may have been processed even if the client logs out/times out; reconcile its original key.

## Security

The server must still verify authentication/token issuer/audience/signature/expiry/revocation and resource authorization; signed provider/attribution evidence; unique sessions/events/idempotency; server-time/country/referral/quota/risk rules; atomic ledger/wallet/withdrawals; payment/admin/audit/reversal systems; and relevant privacy/legal/provider-policy obligations. Client code is not the financial authority.

No production credentials are embedded. Secure persistent token storage and real SDK/backend revocation remain unimplemented integrations. Analytics configuration does not send analytics. External image/provider URL policy remains as in Part 6.

## Tests

Actually run on Linux:

- Previous tests retained: **258**, unchanged files.
- New File 35 tests: **57**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded --timeout 30s`: **315 tests passed**.

Coverage includes config/HTTPS/URL/timeouts, auth transitions/expiry/refresh races/redaction, account/logout isolation, API cancellation/parsing/errors/401 retry, strict wallet/ledger data, reward/offer/withdrawal reconciliation, no local credit, ad evidence/dedup/disposal and original home reachability.

Two tests use actual development loopback HTTP with synthetic credentials, including socket cancellation. Auth/provider/backend fixtures are test-only. This is not proof of production HTTPS deployment, real auth SDKs, advertiser signatures/attribution, real ads/payouts or physical-device/store behavior.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Use a hot restart after changing these Dart classes. No new native full stop/rebuild is required solely for Part 7 because no plugin or permission changed. Earlier native plugins still need rebuilding if never installed. Android requires the existing compatible SDK/JDK; iPhone compilation requires Mac/Xcode/signing.

## Manual Verification

### Automated

The tests verify client state/contracts/validation and explicit synthetic-provider/transport behavior, plus development loopback networking. Existing TLS/file-sharing regressions remain in the suite.

### Manual — required, not performed here

1. Check the original sharing home/routes while rewards backend is disabled or offline.
2. Open the new account/session view. Default provider buttons must be unavailable; no fake account/balance/login is shown.
3. With an actual staging auth adapter and API, test login, expired/revoked tokens, concurrent refresh, logout mid-request, account switching and background/resume. Inspect only redacted diagnostics.
4. Verify real HTTPS certificates, configured capabilities/routes/envelopes, response limits, error mapping and rejection of redirects/malformed/cross-account financial data.
5. Use legitimate provider evidence for offer/ad/promotion/referral rewards; verify pending/approved/rejected/reversed status, transaction identity, fresh wallet and reconciliation without client arithmetic.
6. Test existing withdrawal minimum/balance/quote/conflict/idempotency and original-key status; actual provider/admin processing must decide paid/rejected. Check ledger and wallet refresh.
7. Integrate a compliant real ad SDK with development units and test evidence ordering, duplicate callbacks, SSV and lifecycle on Android and iPhone. Default unavailable driver is not a playback test.
8. On two real phones, test the existing TLS transfer, QR/manual pairing, approval, progress/cancel/retry, receipt, Saved Files/history and SHA-256 while rewards internet is unavailable. Logout must not remove received copies.

## Known Production Limitations

No real backend deployment, Google/Apple/email/phone authentication SDK, advertiser postback/attribution network, AdMob/other real ad SDK, bKash/Nagad/Rocket/PayPal/bank payout or production cash withdrawal is connected. No production build/signing/store/real-phone verification is claimed.

Tokens/cache/reconciliation markers are memory-only, not secure persistent sessions or financial authority. Backend atomicity, provider evidence and revocation remain mandatory. Real external auth/ad lifecycle and HTTPS deployment need staging/device validation. Existing foreground/private-IPv4/no-resume sharing limitations remain unchanged.

# ▶ Next — Part 8 (File 36–40)
