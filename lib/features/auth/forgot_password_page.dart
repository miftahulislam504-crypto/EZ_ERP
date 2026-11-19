import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_inputs.dart';
import 'auth_layout.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthLayout(
        title: 'Reset link sent',
        subtitle: 'If an account exists for ${_email.text.trim()}, you will receive an email with a link to choose a new password.',
        child: AppButton(label: 'Back to sign in', expand: true, onPressed: () => context.go('/login')),
      );
    }
    return AuthLayout(
      title: 'Reset your password',
      subtitle: 'Enter your email and we will send you a reset link.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[AuthError(_error!), const SizedBox(height: 16)],
            AppTextField(
              controller: _email,
              label: 'Email',
              hint: 'you@company.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email address' : null,
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Send reset link', expand: true, loading: _loading, onPressed: _submit),
            const SizedBox(height: 8),
            AppButton(label: 'Back to sign in', kind: AppButtonKind.ghost, onPressed: () => context.go('/login')),
          ],
        ),
      ),
    );
  }
}
