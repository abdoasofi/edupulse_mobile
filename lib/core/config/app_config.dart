/// Tenant-aware configuration.
///
/// EduPulse is multi-tenant via Frappe's multi-site bench: every school is a
/// separate site reached on its own host. The app therefore treats the base
/// URL as *runtime* state, not a compile-time constant — a user at
/// `alnoor.edupulse.sa` and one at `alfaisal.edupulse.sa` run the same binary.
library;

class AppConfig {
  const AppConfig({
    required this.baseUrl,
    this.tenantSlug,
    this.apiVersion = 'v1',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  final String baseUrl;
  final String? tenantSlug;
  final String apiVersion;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Compile-time default, overridable per build:
  ///   flutter run --dart-define=EDUPULSE_BASE_URL=https://demo.edupulse.sa
  static const String defaultBaseUrl = String.fromEnvironment(
    'EDUPULSE_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );

  /// Frappe exposes whitelisted methods at `/api/method/<dotted.path>`.
  /// We namespace every EduPulse endpoint under `edupulse_core.api.v1`.
  String methodPath(String module, String method) =>
      '/api/method/edupulse_core.api.$apiVersion.$module.$method';

  /// Frappe's generic document REST resource, for the rare CRUD case.
  String resourcePath(String doctype, [String? name]) =>
      name == null ? '/api/resource/$doctype' : '/api/resource/$doctype/$name';

  /// Turns what a human types into a base URL Dio can use.
  ///
  /// People type `alnoor.edupulse.sa`, not `https://alnoor.edupulse.sa/`. Dio
  /// treats a scheme-less base URL as a relative path, so the request goes
  /// nowhere and fails as a connection error — indistinguishable, in the UI,
  /// from a server being down.
  ///
  /// The scheme is inferred rather than guessed: an IP literal, `localhost`,
  /// a `.local` name or an explicit port is a development bench and gets
  /// `http`; anything else is a school's real domain and gets `https`. Typing
  /// a scheme explicitly always wins.
  static String normaliseSiteUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;

    if (!value.contains('://')) {
      value = '${_inferScheme(value)}://$value';
    }

    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static String _inferScheme(String hostAndPort) {
    final host = hostAndPort.split('/').first;
    final bare = host.split(':').first;

    final isLocal =
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(bare) ||
        bare == 'localhost' ||
        bare.endsWith('.local') ||
        host.contains(':');

    return isLocal ? 'http' : 'https';
  }

  AppConfig copyWith({String? baseUrl, String? tenantSlug}) => AppConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    tenantSlug: tenantSlug ?? this.tenantSlug,
    apiVersion: apiVersion,
    connectTimeout: connectTimeout,
    receiveTimeout: receiveTimeout,
  );
}

/// The five personas. `wire` matches `User.epc_persona` on the server.
enum Persona {
  student('Student', '/student/home'),
  teacher('Teacher', '/teacher/home'),
  parent('Parent', '/parent/home'),
  supervisor('Supervisor', '/supervisor/home'),
  admin('Admin', '/admin/home');

  const Persona(this.wire, this.homeRoute);

  final String wire;
  final String homeRoute;

  static Persona fromWire(String? value) => Persona.values.firstWhere(
    (p) => p.wire == value,
    orElse: () => Persona.student,
  );
}
