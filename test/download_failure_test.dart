import 'dart:io';

import 'package:edupulse_mobile/core/config/app_config.dart';
import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:edupulse_mobile/core/network/api_result.dart';
import 'package:edupulse_mobile/core/storage/token_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a failed download tells the student.
///
/// The first real download failure in this app was a 500 on a file that was
/// present on the server, and the app said "the file no longer exists on the
/// school's site" — the one claim that was false, and one that sends whoever
/// reads it to look in the wrong place. A download that fails has to name
/// which thing failed, because they are fixed by different people.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter_test` installs an HttpClient that answers 400 to everything, so
  // a status-mapping test would only ever exercise one branch. These cases are
  // about what a real server's real status codes produce, and the server here
  // is a loopback socket in this file.
  final mockedHttp = HttpOverrides.current;

  // The client asks the keystore for a token on every request; there is no
  // platform behind it here, and a null answer simply omits the header.
  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });

  tearDownAll(() => HttpOverrides.global = mockedHttp);

  late HttpServer server;
  late int status;
  late Directory temp;

  setUp(() async {
    status = 200;
    temp = await Directory.systemTemp.createTemp('edupulse_download_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    server.listen((request) async {
      request.response.statusCode = status;
      request.response.write(status == 200 ? 'worksheet' : '<html>no</html>');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  ApiClient client() => ApiClient(
    config: AppConfig(baseUrl: 'http://127.0.0.1:${server.port}'),
    tokens: TokenStore(),
  );

  Future<ApiException> failure() async {
    try {
      await client().downloadFile(
        url: '/files/a.txt',
        savePath: '${temp.path}/a.txt',
      );
      fail('expected the download to be refused');
    } on ApiException catch (e) {
      return e;
    }
  }

  test('a working download returns the byte count', () async {
    final bytes = await client().downloadFile(
      url: '/files/a.txt',
      savePath: '${temp.path}/a.txt',
    );

    expect(bytes, 'worksheet'.length);
  });

  test('a 500 blames the server, not the file', () async {
    // The failure that shipped. The file was on disk the whole time.
    status = 500;
    final error = await failure();

    expect(error.code, ApiErrorCode.serverError);
    expect(error.message, contains('500'));
    expect(error.message, contains('الملف موجود'));
  });

  test('a 404 says the file is gone', () async {
    status = 404;
    final error = await failure();

    expect(error.code, ApiErrorCode.notFound);
    expect(error.message, contains('لم يعد موجوداً'));
  });

  test('a 403 sends the student to log in again', () async {
    status = 403;
    final error = await failure();

    expect(error.code, ApiErrorCode.notAuthenticated);
    expect(error.message, contains('الجلسة'));
  });

  test('an error page is never left on disk as the file', () async {
    // `validateStatus` accepts everything under 600 so error envelopes can be
    // parsed, which means Dio happily writes an HTML 404 page into the file
    // and the app would mark it available offline.
    status = 500;
    await failure();

    expect(File('${temp.path}/a.txt').existsSync(), isFalse);
  });
}
