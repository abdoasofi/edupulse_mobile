import 'package:edupulse_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scheme-less base URL is the failure this file exists for. Dio treats it
/// as a relative path, the request never leaves for the intended host, and the
/// app reports a connection error — so a typo that is trivially fixable is
/// presented as an infrastructure problem.
void main() {
  group('normaliseSiteUrl', () {
    test('a bare school domain becomes https', () {
      expect(
        AppConfig.normaliseSiteUrl('alnoor.edupulse.sa'),
        'https://alnoor.edupulse.sa',
      );
    });

    test('an explicit scheme is never rewritten', () {
      expect(
        AppConfig.normaliseSiteUrl('http://alnoor.edupulse.sa'),
        'http://alnoor.edupulse.sa',
      );
    });

    test('a LAN address gets http, not https', () {
      // A dev bench serves plain HTTP. Upgrading this to https would fail the
      // TLS handshake and surface as the same opaque connection error.
      expect(
        AppConfig.normaliseSiteUrl('10.40.84.8:8001'),
        'http://10.40.84.8:8001',
      );
      expect(AppConfig.normaliseSiteUrl('localhost:8001'), 'http://localhost:8001');
      expect(
        AppConfig.normaliseSiteUrl('demo.edupulse.local'),
        'http://demo.edupulse.local',
      );
    });

    test('trailing slashes are stripped so paths do not double up', () {
      expect(
        AppConfig.normaliseSiteUrl('https://alnoor.edupulse.sa///'),
        'https://alnoor.edupulse.sa',
      );
    });

    test('surrounding whitespace from a paste or keyboard is dropped', () {
      expect(
        AppConfig.normaliseSiteUrl('  alnoor.edupulse.sa  '),
        'https://alnoor.edupulse.sa',
      );
    });

    test('an empty field stays empty for the validator to catch', () {
      expect(AppConfig.normaliseSiteUrl('   '), '');
    });
  });
}
