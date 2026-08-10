import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The last successful `auth.bootstrap` payload, kept so the app can open
/// without a server.
///
/// The credentials already survive a restart — [TokenStore] holds them — but
/// the *session* did not: every cold start called `bootstrap`, and a call that
/// could not reach the site produced `Unauthenticated`, which the router reads
/// as "show the login screen". So a student who had downloaded their whole
/// library, on a bus with no signal, was asked to log in to reach files already
/// sitting on the phone.
///
/// Stored verbatim rather than as a parsed object: it is replayed through the
/// same `fromBootstrap` constructor as a live response, so an offline session
/// and an online one cannot drift into being two different shapes.
class SessionCache {
  SessionCache({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _key = 'edupulse.bootstrap';

  Future<void> save(Map<String, dynamic> payload) =>
      _storage.write(key: _key, value: jsonEncode(payload));

  /// The stored payload, or null when there is none or it no longer parses.
  ///
  /// A cache written by an older build whose shape has since changed must not
  /// crash the splash screen — the honest fallback is the login screen, which
  /// is exactly what null produces.
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
