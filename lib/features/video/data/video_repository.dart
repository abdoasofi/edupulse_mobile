import '../../../core/network/api_client.dart';

/// Playback progress reporting.
///
/// The player heartbeats every [heartbeatSeconds]; `delta` tells the server how
/// much real playback happened, so scrubbing cannot fake completion.
class VideoRepository {
  const VideoRepository(this.api);

  final ApiClient api;

  static const int heartbeatSeconds = 10;

  Future<VideoProgressUpdate> updateProgress({
    required String lesson,
    required double position,
    double? duration,
    double? delta,
    String? device,
  }) async {
    final result = await api.post<Map<String, dynamic>>(
      'video',
      'update_progress',
      body: {
        'lesson': lesson,
        'position': position,
        'duration': ?duration,
        'delta': ?delta,
        'device': ?device,
      },
    );

    return VideoProgressUpdate.fromJson(result.data);
  }

  Future<VideoProgressUpdate> markComplete(String lesson) async {
    final result = await api.post<Map<String, dynamic>>(
      'video',
      'mark_complete',
      body: {'lesson': lesson},
    );
    return VideoProgressUpdate.fromJson(result.data);
  }

  /// Flush progress captured while offline.
  Future<int> syncOffline(List<Map<String, dynamic>> entries) async {
    final result = await api.post<Map<String, dynamic>>(
      'video',
      'sync_offline_progress',
      body: {'entries': entries},
    );
    return (result.data['synced'] as num?)?.toInt() ?? 0;
  }
}

class VideoProgressUpdate {
  const VideoProgressUpdate({
    required this.lesson,
    this.watchedPercentage = 0,
    this.isCompleted = false,
    this.newlyCompleted = false,
    this.threshold = 90,
    this.gateQuiz,
  });

  final String lesson;
  final double watchedPercentage;
  final bool isCompleted;

  /// True only on the transition — use it to fire the "quiz unlocked" prompt
  /// exactly once instead of on every heartbeat.
  final bool newlyCompleted;
  final int threshold;
  final String? gateQuiz;

  factory VideoProgressUpdate.fromJson(Map<String, dynamic> json) =>
      VideoProgressUpdate(
        lesson: (json['lesson'] as String?) ?? '',
        watchedPercentage:
            (json['watched_percentage'] as num?)?.toDouble() ?? 0,
        isCompleted: (json['is_completed'] as num?)?.toInt() == 1,
        newlyCompleted: json['newly_completed'] == true,
        threshold: (json['threshold'] as num?)?.toInt() ?? 90,
        gateQuiz: json['gate_quiz'] as String?,
      );
}
