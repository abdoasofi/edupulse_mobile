import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/session.dart';

/// Hard gate shown when the tenant's `min_app_version` exceeds this build.
class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final message = auth is UpgradeRequired
        ? auth.message
        : 'A newer version of the app is required.';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update, size: 64),
              const SizedBox(height: 24),
              Text(
                'Update required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).restore(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
