import 'package:edupulse_mobile/core/config/app_config.dart';
import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:edupulse_mobile/core/storage/token_store.dart';
import 'package:edupulse_mobile/features/auth/data/auth_repository.dart';
import 'package:edupulse_mobile/features/auth/data/session_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What logging out is allowed to take with it.
///
/// The school address is not the user's to remember. The app asked for it once,
/// on first run, and has known it ever since — so a logout that drops it strands
/// them on a login screen demanding a URL they may never have typed. Clearing
/// the credentials must not clear the way back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();

    // A real store, not a null one: the bug this guards is an ordering
    // question between two handles, which a store that forgets everything
    // could never show.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String?;

          switch (call.method) {
            case 'write':
              store[key!] = args['value'] as String;
              return null;
            case 'read':
              return store[key];
            case 'delete':
              store.remove(key);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'containsKey':
              return store.containsKey(key);
          }
          return null;
        });
  });

  AuthRepository repository() {
    final tokens = TokenStore();
    return AuthRepository(
      api: ApiClient(
        config: const AppConfig(baseUrl: 'http://school.test'),
        tokens: tokens,
      ),
      tokens: tokens,
      cache: SessionCache(),
    );
  }

  test('logging out keeps the school address', () async {
    final repo = repository();

    await repo.tokens.saveSession(
      apiKey: 'k',
      apiSecret: 's',
      user: 'student@school.test',
      persona: 'Student',
      baseUrl: 'http://localhost:8001',
    );
    await repo.cache.save({'user': {}, 'tenant': {}});

    await repo.logout();

    expect(await repo.tokens.baseUrl, 'http://localhost:8001');
  });

  test('logging out takes the credentials and the cached session', () async {
    final repo = repository();

    await repo.tokens.saveSession(
      apiKey: 'k',
      apiSecret: 's',
      user: 'student@school.test',
      persona: 'Student',
      baseUrl: 'http://localhost:8001',
    );
    await repo.cache.save({'user': {}, 'tenant': {}});

    await repo.logout();

    expect(await repo.tokens.hasSession, isFalse);
    expect(await repo.cache.read(), isNull);
    expect(await repo.tokens.authHeader(), isNull);
  });

  test('a logout with no server still clears the device', () async {
    // The call to `auth.logout` fails here — there is no server. Being unable
    // to tell the server must never leave the credentials on the phone.
    final repo = repository();

    await repo.tokens.saveSession(
      apiKey: 'k',
      apiSecret: 's',
      user: 'student@school.test',
      persona: 'Student',
    );

    await repo.logout();

    expect(await repo.tokens.hasSession, isFalse);
  });
}
