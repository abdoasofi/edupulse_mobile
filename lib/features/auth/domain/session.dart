import '../../../core/config/app_config.dart';

/// The authenticated user, as returned by `auth.login` / `auth.bootstrap`.
class UserProfile {
  const UserProfile({
    required this.name,
    required this.fullName,
    required this.persona,
    required this.roles,
    this.email,
    this.mobileNo,
    this.avatar,
    this.language = 'ar',
    this.gradeLevel,
    this.schoolClass,
    this.studentId,
  });

  final String name;
  final String fullName;
  final Persona persona;
  final List<String> roles;
  final String? email;
  final String? mobileNo;
  final String? avatar;
  final String language;
  final String? gradeLevel;
  final String? schoolClass;
  final String? studentId;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    fullName: (json['full_name'] as String?) ?? json['name'] as String,
    persona: Persona.fromWire(json['persona'] as String?),
    roles: (json['roles'] as List?)?.cast<String>() ?? const [],
    email: json['email'] as String?,
    mobileNo: json['mobile_no'] as String?,
    avatar: json['avatar'] as String?,
    language: (json['language'] as String?) ?? 'ar',
    gradeLevel: json['grade_level'] as String?,
    schoolClass: json['school_class'] as String?,
    studentId: json['student_id'] as String?,
  );
}

/// Tenant branding + pedagogical configuration from `auth.bootstrap`.
class TenantConfig {
  const TenantConfig({
    required this.site,
    this.schoolName,
    this.schoolNameAr,
    this.logo,
    this.primaryColor,
    this.defaultLanguage = 'ar',
    this.passingPercentage = 80,
    this.masteryThreshold = 80,
    this.videoCompletionPercentage = 90,
    this.enforceSequentialUnlock = true,
    this.maxQuizAttempts = 3,
    this.offlineLibraryEnabled = true,
    this.offlineSyncDays = 14,
    this.pushEnabled = false,
  });

  final String site;
  final String? schoolName;
  final String? schoolNameAr;
  final String? logo;
  final String? primaryColor;
  final String defaultLanguage;
  final int passingPercentage;
  final int masteryThreshold;
  final int videoCompletionPercentage;
  final bool enforceSequentialUnlock;
  final int maxQuizAttempts;
  final bool offlineLibraryEnabled;
  final int offlineSyncDays;
  final bool pushEnabled;

  factory TenantConfig.fromBootstrap(Map<String, dynamic> json) {
    final tenant = Map<String, dynamic>.from(json['tenant'] as Map? ?? {});
    final config = Map<String, dynamic>.from(json['config'] as Map? ?? {});
    final features = Map<String, dynamic>.from(json['features'] as Map? ?? {});

    return TenantConfig(
      site: (tenant['site'] as String?) ?? '',
      schoolName: tenant['school_name'] as String?,
      schoolNameAr: tenant['school_name_ar'] as String?,
      logo: tenant['logo'] as String?,
      primaryColor: tenant['primary_color'] as String?,
      defaultLanguage: (tenant['default_language'] as String?) ?? 'ar',
      passingPercentage: (config['passing_percentage'] as num?)?.toInt() ?? 80,
      masteryThreshold: (config['mastery_threshold'] as num?)?.toInt() ?? 80,
      videoCompletionPercentage:
          (config['video_completion_percentage'] as num?)?.toInt() ?? 90,
      enforceSequentialUnlock:
          (config['enforce_sequential_unlock'] as num?)?.toInt() == 1,
      maxQuizAttempts: (config['max_quiz_attempts'] as num?)?.toInt() ?? 3,
      offlineLibraryEnabled: (features['offline_library'] as num?)?.toInt() == 1,
      offlineSyncDays: (features['offline_sync_days'] as num?)?.toInt() ?? 14,
      pushEnabled: features['push_notifications'] == true,
    );
  }
}

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Unauthenticated extends AuthState {
  const Unauthenticated({this.message});
  final String? message;
}

class Authenticated extends AuthState {
  const Authenticated({required this.user, required this.tenant});

  final UserProfile user;
  final TenantConfig tenant;
}

class UpgradeRequired extends AuthState {
  const UpgradeRequired(this.message);
  final String message;
}
