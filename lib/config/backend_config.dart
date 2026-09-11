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
