import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every school types its own address into the login screen, so a typo is the
/// first failure a new one meets — before a session, a role or a single screen
/// has had a chance to work. The message it gets has to name the cause.
void main() {
  group('wrongAddressMessage', () {
    test('a 404 is reported as a wrong address, not a broken platform', () {
      final message = wrongAddressMessage('alnoor.edupulse.sa', 404);

      expect(message, contains('alnoor.edupulse.sa'));
      expect(message, contains('عنوان المدرسة'));
      // The old text. English, on an Arabic screen, blaming the server for
      // what is almost always a typo.
      expect(message, isNot(contains('Malformed')));
    });

    test('another status still names the address rather than staying vague', () {
      final message = wrongAddressMessage('10.40.84.8:8001', 502);

      expect(message, contains('10.40.84.8:8001'));
      expect(message, contains('502'));
    });

    test('a missing host and status still produce a readable sentence', () {
      final message = wrongAddressMessage('', null);

      expect(message.trim(), isNotEmpty);
      expect(message, isNot(contains('null')));
    });
  });
}
