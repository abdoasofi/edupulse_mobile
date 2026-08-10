import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_result.dart';
import '../core/offline/library_cache.dart';
import '../core/offline/offline_database.dart';
import '../core/storage/token_store.dart';
import '../features/admin/data/admin_repository.dart';
import '../features/admin/domain/admin_models.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/session_cache.dart';
import '../features/auth/domain/session.dart';
import '../features/library/data/library_repository.dart';
import '../features/library/domain/library_item.dart';
import '../features/parent/data/parent_repository.dart';
import '../features/parent/domain/parent_models.dart';
import '../features/quiz/data/quiz_repository.dart';
import '../features/remedial/data/remedial_repository.dart';
import '../features/remedial/domain/remedial_models.dart';
import '../features/quiz/domain/quiz_models.dart';
import '../features/student/data/student_repository.dart';
import '../features/student/domain/student_models.dart';
import '../features/teacher/data/teacher_repository.dart';
import '../features/teacher/domain/teacher_models.dart';
import '../features/video/data/video_repository.dart';

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

final sessionCacheProvider = Provider<SessionCache>((ref) => SessionCache());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
    cache: ref.watch(sessionCacheProvider),
  );
});

// --------------------------------------------------------- المكتبة دون اتصال

final offlineDatabaseProvider = Provider<OfflineDatabase>((ref) {
  final database = OfflineDatabase();
  ref.onDispose(database.close);
  return database;
});

/// Where downloaded attachments live.
///
/// Application *support*, not the cache directory: both platforms reclaim the
/// cache directory under storage pressure without asking, which would delete
/// the library of the student least able to re-download it.
final downloadDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, 'library'));
});

final libraryCacheProvider = FutureProvider<LibraryCache>((ref) async {
  return LibraryCache(
    database: ref.watch(offlineDatabaseProvider),
    downloads: await ref.watch(downloadDirectoryProvider.future),
  );
});

final libraryRepositoryProvider = FutureProvider<LibraryRepository>((
  ref,
) async {
  return LibraryRepository(
    api: ref.watch(apiClientProvider),
    cache: await ref.watch(libraryCacheProvider.future),
  );
});

/// The filters the library screen is showing, as a provider key.
typedef LibraryQuery = ({String? itemType, String search, bool downloadedOnly});

final libraryItemsProvider = FutureProvider.autoDispose
    .family<List<LibraryItem>, LibraryQuery>((ref, query) async {
      final repo = await ref.watch(libraryRepositoryProvider.future);

      return repo.items(
        itemType: query.itemType,
        search: query.search,
        downloadedOnly: query.downloadedOnly,
      );
    });

/// Reading an item is also what marks it recently used, which is what keeps
/// eviction from taking the thing the student actually studies.
final libraryItemProvider = FutureProvider.autoDispose
    .family<LibraryItem?, String>((ref, name) async {
      final repo = await ref.watch(libraryRepositoryProvider.future);
      return repo.open(name);
    });

final libraryUsageProvider = FutureProvider.autoDispose<StorageUsage>((
  ref,
) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.usage();
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
      state = await _bind(await _repo.bootstrap(appVersion: await _version()));
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.appUpgradeRequired) {
        state = UpgradeRequired(e.message);
      } else if (e.isAuthFailure) {
        await _repo.logout();
        state = const Unauthenticated(message: 'انتهت الجلسة، سجّل الدخول مجدداً.');
      } else if (e.code == ApiErrorCode.network) {
        state = await _offline() ?? Unauthenticated(message: e.message);
      } else {
        state = Unauthenticated(message: e.message);
      }
    }
  }

  /// The stored session, but only when there is something behind it.
  ///
  /// Letting anyone in offline would open a home screen whose every card
  /// fails, which is a worse answer than the login screen naming the address
  /// it could not reach. So this is deliberately narrow: a student, with a
  /// library already on the device. Nobody else has anything to see.
  Future<Authenticated?> _offline() async {
    final session = await _repo.cachedSession();

    if (session == null || session.user.persona != Persona.student) return null;

    try {
      final cache = await _ref.read(libraryCacheProvider.future);
      return await cache.count() > 0 ? session : null;
    } catch (_) {
      return null;
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
      state = await _bind(await _repo.bootstrap(appVersion: await _version()));
    } on ApiException catch (e) {
      state = e.code == ApiErrorCode.appUpgradeRequired
          ? UpgradeRequired(e.message)
          : Unauthenticated(message: e.message);
    }
  }

  /// Hand the offline store to whoever just signed in.
  ///
  /// A phone gets handed to a sibling and a school tablet is shared all day.
  /// Without this the second student inherits the first one's library — their
  /// subjects, their downloads, their reading history — so the store checks
  /// who owns it and empties itself when the answer changes.
  ///
  /// A store that will not open must not cost anyone their login: the library
  /// is one screen, and the session is the whole app.
  Future<Authenticated> _bind(Authenticated session) async {
    try {
      final cache = await _ref.read(libraryCacheProvider.future);
      await cache.claim('${session.tenant.site}|${session.user.name}');
    } catch (_) {
      // Nothing to bind to. The library screen will report it in its own place.
    }

    return session;
  }

  Future<void> logout() async {
    // Before clearing the credentials, while we still know whose library it is.
    try {
      final cache = await _ref.read(libraryCacheProvider.future);
      await cache.wipe();
    } catch (_) {
      // A store that will not open cannot trap the user in the app either.
    }

    await _repo.logout();
    state = const Unauthenticated();
  }

  /// Must AWAIT the provider. Reading `.value` before the future resolves
  /// yields null → '0.0.0', which the server correctly rejects as below the
  /// tenant's minimum version, showing a bogus "update required" screen.
  Future<String> _version() => _ref.read(appVersionProvider.future);
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

// ─────────────────────────────── وحدة الطالب ───────────────────────────────

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.watch(apiClientProvider)),
);

final videoRepositoryProvider = Provider<VideoRepository>(
  (ref) => VideoRepository(ref.watch(apiClientProvider)),
);

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(ref.watch(apiClientProvider)),
);

final dashboardProvider = FutureProvider.autoDispose<StudentDashboard>(
  (ref) => ref.watch(studentRepositoryProvider).dashboard(),
);

final learningPathProvider = FutureProvider.autoDispose
    .family<LearningPath, String>(
      (ref, course) => ref.watch(studentRepositoryProvider).learningPath(course),
    );

final lessonProvider = FutureProvider.autoDispose.family<LessonDetail, String>(
  (ref, lesson) => ref.watch(studentRepositoryProvider).lesson(lesson),
);

final quizPaperProvider = FutureProvider.autoDispose.family<QuizPaper, String>(
  (ref, quiz) => ref.watch(quizRepositoryProvider).paper(quiz),
);

final remedialRepositoryProvider = Provider<RemedialRepository>(
  (ref) => RemedialRepository(ref.watch(apiClientProvider)),
);

/// The active remedial path. `null` data means the student has none.
final remedialPathProvider = FutureProvider.autoDispose
    .family<RemedialPath?, String?>(
      (ref, assignment) =>
          ref.watch(remedialRepositoryProvider).active(assignment: assignment),
    );

// ─────────────────────────────── وحدة المعلم ───────────────────────────────

final teacherRepositoryProvider = Provider<TeacherRepository>(
  (ref) => TeacherRepository(ref.watch(apiClientProvider)),
);

/// A null course means "every course I teach" — the server resolves the roster
/// from Course Instructor, so the app never has to know the teacher's classes.
final classOverviewProvider = FutureProvider.autoDispose
    .family<ClassOverview, String?>(
      (ref, course) =>
          ref.watch(teacherRepositoryProvider).classOverview(course: course),
    );

final strugglingProvider = FutureProvider.autoDispose
    .family<List<StrugglingEntry>, String?>(
      (ref, course) =>
          ref.watch(teacherRepositoryProvider).struggling(course: course),
    );

final masteryImpactProvider = FutureProvider.autoDispose
    .family<MasteryImpact, String?>(
      (ref, course) =>
          ref.watch(teacherRepositoryProvider).impact(course: course),
    );

final authoringLessonsProvider = FutureProvider.autoDispose
    .family<List<AuthoringLesson>, String?>(
      (ref, course) =>
          ref.watch(teacherRepositoryProvider).lessons(course: course),
    );

/// How this school wants videos attached. Read once per screen, not per lesson:
/// the answer is a tenant setting, and asking per row would be one request per
/// lesson to learn the same thing.
final uploadTargetProvider = FutureProvider.autoDispose<UploadTarget>(
  (ref) => ref.watch(teacherRepositoryProvider).uploadTarget(),
);

// ──────────────────────────── وحدة ولي الأمر ────────────────────────────

final parentRepositoryProvider = Provider<ParentRepository>(
  (ref) => ParentRepository(ref.watch(apiClientProvider)),
);

final childrenProvider = FutureProvider.autoDispose<List<Child>>(
  (ref) => ref.watch(parentRepositoryProvider).children(),
);

/// Keyed by (child, window) so switching 7/30 days refetches rather than
/// reusing the answer to a different question — and so two children on one
/// guardian's account never share a cache entry.
typedef ChildWindow = ({String student, int days});

final childSummaryProvider = FutureProvider.autoDispose
    .family<ChildSummary, ChildWindow>(
      (ref, key) => ref
          .watch(parentRepositoryProvider)
          .summary(key.student, days: key.days),
    );

final childFlaggedProvider = FutureProvider.autoDispose
    .family<FlaggedSubjects, String>(
      (ref, student) => ref.watch(parentRepositoryProvider).flagged(student),
    );

final childTrendProvider = FutureProvider.autoDispose
    .family<List<MasteryTrend>, String>(
      (ref, student) => ref.watch(parentRepositoryProvider).trend(student),
    );

// ────────────────────────── وحدة الإدارة والإشراف ──────────────────────────

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Keyed by the reporting window so switching 7/30/90 days refetches rather
/// than reusing a cached answer for a different question.
final executiveKpisProvider = FutureProvider.autoDispose
    .family<ExecutiveKpis, int>(
      (ref, days) => ref.watch(adminRepositoryProvider).kpis(days: days),
    );
