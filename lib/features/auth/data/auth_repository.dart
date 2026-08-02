import 'dart:io' show Platform;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/token_store.dart';
import '../domain/session.dart';

class AuthRepository {
  const AuthRepository({required this.api, required this.tokens});

  final ApiClient api;
  final TokenStore tokens;

  static String get devicePlatform {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Web';
  }

  /// Authenticates and persists the returned API key/secret pair.
  Future<UserProfile> login({
    required String username,
    required String password,
    required String appVersion,
    String? fcmToken,
  }) async {
    final result = await api.post<Map<String, dynamic>>(
      'auth',
      'login',
      body: {
        'usr': username,
        'pwd': password,
        'device': devicePlatform,
        'app_version': appVersion,
        'fcm_token': fcmToken,
      },
    );

    final data = result.data;

    await tokens.saveSession(
      apiKey: data['api_key'] as String,
      apiSecret: data['api_secret'] as String,
      user: data['name'] as String,
      persona: (data['persona'] as String?) ?? 'Student',
      baseUrl: api.config.baseUrl,
    );

    return UserProfile.fromJson(data);
  }

  /// One round-trip cold start: tenant branding, persona, feature flags.
  Future<Authenticated> bootstrap({required String appVersion}) async {
    final result = await api.get<Map<String, dynamic>>(
      'auth',
      'bootstrap',
      query: {'app_version': appVersion},
    );

    final data = result.data;

    if (data['upgrade_required'] == true) {
      throw const ApiException(
        code: ApiErrorCode.appUpgradeRequired,
        message: 'A newer version of the app is required.',
      );
    }

    return Authenticated(
      user: UserProfile.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      ),
      tenant: TenantConfig.fromBootstrap(data),
    );
  }

  Future<void> registerDevice({
    required String fcmToken,
    required String appVersion,
  }) => api.post<Map<String, dynamic>>(
    'auth',
    'register_device',
    body: {
      'fcm_token': fcmToken,
      'device': devicePlatform,
      'app_version': appVersion,
    },
  );

  Future<void> logout() async {
    try {
      await api.post<Map<String, dynamic>>('auth', 'logout');
    } on ApiException {
      // A failed server logout must never trap the user in the app.
    } finally {
      await tokens.clear();
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) => api.post<Map<String, dynamic>>(
    'auth',
    'change_password',
    body: {'old_password': oldPassword, 'new_password': newPassword},
  );

  Future<bool> get hasStoredSession => tokens.hasSession;
}
