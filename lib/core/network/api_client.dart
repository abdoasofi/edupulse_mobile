import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_result.dart';

/// The single bridge between Flutter and Frappe.
///
/// Responsibilities:
///  * attach `Authorization: token <api_key>:<api_secret>` to every call
///  * unwrap the `{ok, data, meta}` envelope into typed results
///  * translate transport + envelope failures into one [ApiException] type
class ApiClient {
  ApiClient({required AppConfig config, required this.tokens})
    : _config = config,
      _dio = Dio(
        BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          // Frappe returns 4xx with a meaningful envelope; we parse it
          // ourselves rather than letting Dio throw first.
          validateStatus: (status) => status != null && status < 600,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokens.authHeader();
          if (token != null) {
            options.headers['Authorization'] = token;
          }
          return handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final AppConfig _config;
  final TokenStore tokens;

  AppConfig get config => _config;

  /// Points the client at a different tenant site at runtime.
  void switchTenant(String baseUrl) => _dio.options.baseUrl = baseUrl;

  /// Resolves a server-supplied URL.
  ///
  /// The API returns site-hosted media as a relative path (`/files/x.mp4`) so
  /// it stays correct whatever host the app reaches the tenant on — an
  /// `adb reverse` localhost, a LAN IP, or the school's real domain.
  String resolveUrl(String url) {
    if (url.isEmpty || url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  /// GET a whitelisted method. Frappe convention: GET for reads.
  Future<ApiResult<T>> get<T>(
    String module,
    String method, {
    Map<String, dynamic>? query,
  }) => _send<T>(
    () => _dio.get(
      _config.methodPath(module, method),
      queryParameters: _clean(query),
    ),
  );

  /// POST a whitelisted method. Frappe auto-commits after a successful POST.
  Future<ApiResult<T>> post<T>(
    String module,
    String method, {
    Map<String, dynamic>? body,
  }) => _send<T>(
    () => _dio.post(_config.methodPath(module, method), data: _clean(body)),
  );

  Future<ApiResult<T>> _send<T>(Future<Response> Function() request) async {
    late final Response response;

    try {
      response = await request();
    } on DioException catch (e) {
      throw ApiException(
        code: ApiErrorCode.network,
        message: _networkMessage(e),
        statusCode: e.response?.statusCode,
      );
    }

    final body = response.data;

    if (body is! Map) {
      throw ApiException(
        code: ApiErrorCode.serverError,
        message: 'Malformed response from server.',
        statusCode: response.statusCode,
      );
    }

    // Frappe wraps whitelisted return values in `message`; our envelope
    // then lives inside it.
    final envelope = (body['message'] is Map)
        ? Map<String, dynamic>.from(body['message'] as Map)
        : Map<String, dynamic>.from(body);

    if (envelope['ok'] == true) {
      return ApiResult<T>(
        data: envelope['data'] as T,
        meta: envelope['meta'] is Map
            ? Map<String, dynamic>.from(envelope['meta'] as Map)
            : const {},
      );
    }

    if (envelope['error'] is Map) {
      throw ApiException.fromEnvelope(
        Map<String, dynamic>.from(envelope['error'] as Map),
        statusCode: response.statusCode,
      );
    }

    // Frappe's own error shape (unhandled server exception).
    throw ApiException(
      code: response.statusCode == 401
          ? ApiErrorCode.notAuthenticated
          : ApiErrorCode.serverError,
      message: (body['exc_type'] as String?) ?? 'Request failed.',
      statusCode: response.statusCode,
    );
  }

  String _networkMessage(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => 'The connection timed out.',
    DioExceptionType.connectionError => 'No connection to the server.',
    _ => e.message ?? 'Network error.',
  };

  Map<String, dynamic>? _clean(Map<String, dynamic>? input) {
    if (input == null) return null;
    return {
      for (final entry in input.entries)
        if (entry.value != null) entry.key: entry.value,
    };
  }
}
