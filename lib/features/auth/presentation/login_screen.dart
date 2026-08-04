import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/app_config.dart';
import '../domain/session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _siteController = TextEditingController(text: AppConfig.defaultBaseUrl);

  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _restoreSite();
  }

  /// `TokenStore.clear()` deliberately keeps the tenant address across a
  /// logout, but the field was seeded from the compile-time default and threw
  /// that away — so every sign-in after the first sent the user back to
  /// `localhost`, which on a real phone is the phone itself.
  Future<void> _restoreSite() async {
    final stored = await ref.read(tokenStoreProvider).baseUrl;
    if (!mounted || stored == null || stored.isEmpty) return;
    _siteController.text = stored;
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _siteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final site = AppConfig.normaliseSiteUrl(_siteController.text);
    _siteController.text = site;

    // Point the client at this tenant's site before authenticating, and keep
    // it even if the credentials fail — the address is what the user will be
    // correcting, and losing it on every failed attempt is its own trap.
    ref.read(appConfigProvider.notifier).state = AppConfig(baseUrl: site);
    await ref.read(tokenStoreProvider).setBaseUrl(site);

    await ref
        .read(authControllerProvider.notifier)
        .login(_userController.text.trim(), _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final busy = auth is AuthLoading;
    final error = auth is Unauthenticated ? auth.message : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'نبض التعلّم',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'منصة التعلّم القائم على الإتقان',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _siteController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان المدرسة',
                        helperText: 'مثال: alnoor.edupulse.sa',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'أدخل عنوان مدرستك'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _userController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم أو البريد',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'إظهار' : 'إخفاء',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'مطلوب' : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBox(message: error),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تسجيل الدخول'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A failure at sign-in is nearly always the address, not the password. Bare
/// red text reads as "you got it wrong"; a bordered box with the server's own
/// wording reads as a report of what the app tried and what came back.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
