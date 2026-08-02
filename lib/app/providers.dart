import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_result.dart';
import '../core/storage/token_store.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/domain/session.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Base URL is overridden at runtime once the tenant is known.
final appConfigProvider = StateProvider<AppConfig>(
  (ref) => const AppConfig(baseUrl: AppConfig.defaultBaseUrl),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
});

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthUnknown());

  final Ref _ref;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  /// Called once on app start: restores a stored session if one exists.
  Future<void> restore() async {
    state = const AuthLoading();

    if (!await _repo.hasStoredSession) {
      state = const Unauthenticated();
      return;
    }

    try {
      state = await _repo.bootstrap(appVersion: await _version());
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.appUpgradeRequired) {
        state = UpgradeRequired(e.message);
      } else if (e.isAuthFailure) {
        await _repo.logout();
        state = const Unauthenticated(message: 'Session expired.');
      } else {
        state = Unauthenticated(message: e.message);
      }
    }
  }

  Future<void> login(String username, String password) async {
    state = const AuthLoading();

    try {
      await _repo.login(
        username: username,
        password: password,
        appVersion: await _version(),
      );
      state = await _repo.bootstrap(appVersion: await _version());
    } on ApiException catch (e) {
      state = e.code == ApiErrorCode.appUpgradeRequired
          ? UpgradeRequired(e.message)
          : Unauthenticated(message: e.message);
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const Unauthenticated();
  }

  Future<String> _version() async =>
      _ref.read(appVersionProvider).value ?? '0.0.0';
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: the signed-in persona, or null when unauthenticated.
final personaProvider = Provider<Persona?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is Authenticated ? state.user.persona : null;
});

final tenantProvider = Provider<TenantConfig?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is Authenticated ? state.tenant : null;
});
