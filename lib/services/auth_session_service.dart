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
