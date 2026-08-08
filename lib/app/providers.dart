import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_result.dart';
import '../core/storage/token_store.dart';
import '../features/admin/data/admin_repository.dart';
import '../features/admin/domain/admin_models.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/domain/session.dart';
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
        state = const Unauthenticated(message: 'انتهت الجلسة، سجّل الدخول مجدداً.');
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
