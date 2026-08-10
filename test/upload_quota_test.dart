import 'package:edupulse_mobile/features/teacher/domain/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

UploadTarget _target({int maxBytes = 0, int? left}) => UploadTarget(
  provider: 'site',
  providerLabel: 'الموقع',
  strategy: UploadStrategy.fromWire('site_upload'),
  hint: '',
  accepts: const ['mp4'],
  available: true,
  offlineAllowed: true,
  maxBytes: maxBytes,
  storageLeftBytes: left,
);

/// A teacher on a school uplink spends real minutes on an upload. Both walls
/// have to be checked before the first byte leaves the phone — and they need
/// different answers, because only one of them a shorter recording can solve.
void main() {
  group('rejects', () {
    test('a file over the per-file cap says to record a shorter one', () {
      final why = _target(maxBytes: 100 * _mb).rejects(150 * _mb);

      expect(why, isNotNull);
      expect(why, contains('أقصر'));
    });

    test('a file over the school quota does not send them off to re-record',
        () {
      final why = _target(maxBytes: 500 * _mb, left: 40 * _mb).rejects(100 * _mb);

      expect(why, isNotNull);
      // Filming again would hit exactly the same wall.
      expect(why, isNot(contains('أقصر')));
      expect(why, contains('احذف'));
    });

    test('the per-file cap is reported first when both are breached', () {
      final why = _target(maxBytes: 50 * _mb, left: 10 * _mb).rejects(100 * _mb);

      expect(why, contains('أقصر'));
    });

    test('a file that fits both is accepted', () {
      expect(_target(maxBytes: 100 * _mb, left: 100 * _mb).rejects(10 * _mb), isNull);
    });

    test('an unknown quota is unlimited, not zero', () {
      // A server that predates the field sends nothing. Reading that as zero
      // would refuse every upload on every school at once.
      expect(_target(maxBytes: 100 * _mb).rejects(90 * _mb), isNull);
    });
  });

  group('storageNotice', () {
    test('stays silent while there is plenty of room', () {
      expect(_target(left: 5 * 1024 * _mb).storageNotice, isNull);
      expect(_target().storageNotice, isNull);
    });

    test('speaks up inside the last gigabyte', () {
      expect(_target(left: 200 * _mb).storageNotice, contains('200'));
    });

    test('a full quota says so plainly rather than reporting zero', () {
      final notice = _target(left: 0).storageNotice;

      expect(notice, isNotNull);
      expect(notice, contains('امتلأ'));
    });
  });
}
