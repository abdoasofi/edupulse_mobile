import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_result.dart';

/// One place that decides how loading, errors and pedagogical gates look.
///
/// A locked lesson or an exhausted quiz is NOT an error — it is the product
/// working. Those get an explanatory panel, never a red failure state.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorPanel(error: error, onRetry: onRetry),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = error is ApiException ? error as ApiException : null;
    final isGate = api?.isGate ?? false;

    final icon = switch (api?.code) {
      ApiErrorCode.contentLocked => Icons.lock_outline,
      ApiErrorCode.attemptsExhausted => Icons.replay_circle_filled_outlined,
      ApiErrorCode.network => Icons.wifi_off_outlined,
      _ => Icons.error_outline,
    };

    final colour = isGate ? theme.colorScheme.primary : theme.colorScheme.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colour),
            const SizedBox(height: 16),
            Text(
              isGate ? 'لم يحن وقت هذا بعد' : 'تعذّر التحميل',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              api?.message ?? 'حدث خطأ غير متوقع.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mastery ring used on dashboard cards.
class MasteryBadge extends StatelessWidget {
  const MasteryBadge({required this.percentage, this.size = 44, super.key});

  final double percentage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (percentage / 100).clamp(0.0, 1.0);

    final colour = percentage >= 80
        ? const Color(0xFF10B981)
        : percentage >= 50
        ? const Color(0xFFF59E0B)
        : theme.colorScheme.error;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 4,
              backgroundColor: colour.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          Text(
            '${percentage.round()}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
