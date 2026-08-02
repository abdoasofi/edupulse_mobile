import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists Frappe API credentials in the platform keystore/keychain.
///
/// The `api_secret` is returned exactly once, at login — it cannot be read
/// back from the server afterwards — so losing it means re-authenticating.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _kApiKey = 'edupulse.api_key';
  static const _kApiSecret = 'edupulse.api_secret';
  static const _kBaseUrl = 'edupulse.base_url';
  static const _kUser = 'edupulse.user';
  static const _kPersona = 'edupulse.persona';

  Future<void> saveSession({
    required String apiKey,
    required String apiSecret,
    required String user,
    required String persona,
    String? baseUrl,
  }) async {
    await Future.wait([
      _storage.write(key: _kApiKey, value: apiKey),
      _storage.write(key: _kApiSecret, value: apiSecret),
      _storage.write(key: _kUser, value: user),
      _storage.write(key: _kPersona, value: persona),
      if (baseUrl != null) _storage.write(key: _kBaseUrl, value: baseUrl),
    ]);
  }

  /// Frappe token auth: `Authorization: token <api_key>:<api_secret>`.
  Future<String?> authHeader() async {
    final key = await _storage.read(key: _kApiKey);
    final secret = await _storage.read(key: _kApiSecret);

    if (key == null || secret == null) return null;
    return 'token $key:$secret';
  }

  Future<bool> get hasSession async =>
      (await _storage.read(key: _kApiKey)) != null;

  Future<String?> get user => _storage.read(key: _kUser);
  Future<String?> get persona => _storage.read(key: _kPersona);
  Future<String?> get baseUrl => _storage.read(key: _kBaseUrl);

  Future<void> setBaseUrl(String value) =>
      _storage.write(key: _kBaseUrl, value: value);

  Future<void> clear() async {
    // Preserve the tenant base URL so the login screen stays on the right school.
    final tenant = await baseUrl;
    await _storage.deleteAll();
    if (tenant != null) await setBaseUrl(tenant);
  }
}
