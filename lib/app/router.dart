import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../features/auth/domain/session.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/upgrade_screen.dart';
import '../shared/widgets/placeholder_screen.dart';
import 'providers.dart';

/// Role-based routing.
///
/// The redirect is the single authority on where a user may be: it reads the
/// auth state and the signed-in persona, and bounces anyone who lands outside
/// their portal back to their own home.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthState>(const AuthUnknown());

  ref.listen<AuthState>(authControllerProvider, (_, next) {
    notifier.value = next;
  }, fireImmediately: true);

  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = notifier.value;
      final location = state.matchedLocation;

      if (auth is AuthUnknown || auth is AuthLoading) {
        return location == '/splash' ? null : '/splash';
      }

      if (auth is UpgradeRequired) {
        return location == '/upgrade' ? null : '/upgrade';
      }

      if (auth is Unauthenticated) {
        return location == '/login' ? null : '/login';
      }

      if (auth is Authenticated) {
        final home = auth.user.persona.homeRoute;

        // Bounce away from the pre-auth screens.
        if (location == '/splash' ||
            location == '/login' ||
            location == '/upgrade') {
          return home;
        }

        // Enforce portal isolation: a parent may not open /teacher/*.
        final portal = _portalOf(location);
        if (portal != null && portal != auth.user.persona) {
          return home;
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/upgrade', builder: (_, _) => const UpgradeScreen()),

      // ------------------------------------------------ بوابة الطالب
      GoRoute(
        path: '/student/home',
        builder: (_, _) => const PlaceholderScreen(title: 'Student Home'),
        routes: [
          GoRoute(
            path: 'path/:course',
            builder: (_, s) =>
                PlaceholderScreen(title: 'Path ${s.pathParameters['course']}'),
          ),
          GoRoute(
            path: 'lesson/:lesson',
            builder: (_, s) => PlaceholderScreen(
              title: 'Lesson ${s.pathParameters['lesson']}',
            ),
          ),
          GoRoute(
            path: 'quiz/:quiz',
            builder: (_, s) =>
                PlaceholderScreen(title: 'Quiz ${s.pathParameters['quiz']}'),
          ),
          GoRoute(
            path: 'remedial',
            builder: (_, _) => const PlaceholderScreen(title: 'Remedial Path'),
          ),
          GoRoute(
            path: 'library',
            builder: (_, _) =>
                const PlaceholderScreen(title: 'EduPulse Library'),
          ),
        ],
      ),

      // ------------------------------------------- بوابة ولي الأمر
      GoRoute(
        path: '/parent/home',
        builder: (_, _) => const PlaceholderScreen(title: 'Parent Home'),
        routes: [
          GoRoute(
            path: 'child/:student',
            builder: (_, s) => PlaceholderScreen(
              title: 'Child ${s.pathParameters['student']}',
            ),
          ),
        ],
      ),

      // ------------------------------------------------ بوابة المعلم
      GoRoute(
        path: '/teacher/home',
        builder: (_, _) => const PlaceholderScreen(title: 'Teacher Home'),
        routes: [
          GoRoute(
            path: 'class/:course',
            builder: (_, s) => PlaceholderScreen(
              title: 'Class ${s.pathParameters['course']}',
            ),
          ),
          GoRoute(
            path: 'struggling',
            builder: (_, _) =>
                const PlaceholderScreen(title: 'Struggling Students'),
          ),
        ],
      ),

      // ----------------------------------------------- بوابة المشرف
      GoRoute(
        path: '/supervisor/home',
        builder: (_, _) => const PlaceholderScreen(title: 'Supervisor Home'),
      ),

      // ---------------------------------------------- بوابة الإدارة
      GoRoute(
        path: '/admin/home',
        builder: (_, _) => const PlaceholderScreen(title: 'Admin KPIs'),
      ),
    ],
    errorBuilder: (_, state) =>
        PlaceholderScreen(title: 'Not found: ${state.uri}'),
  );
});

/// Maps a route prefix to the persona allowed to view it.
Persona? _portalOf(String location) {
  if (location.startsWith('/student')) return Persona.student;
  if (location.startsWith('/parent')) return Persona.parent;
  if (location.startsWith('/teacher')) return Persona.teacher;
  if (location.startsWith('/supervisor')) return Persona.supervisor;
  if (location.startsWith('/admin')) return Persona.admin;
  return null;
}
