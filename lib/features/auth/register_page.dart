import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/feedback.dart';
import 'auth_layout.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _needsConfirmation = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(supabaseProvider).auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            data: {'full_name': _name.text.trim()},
          );
      if (res.session == null && mounted) setState(() => _needsConfirmation = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needsConfirmation) {
      return AuthLayout(
        title: 'Check your email',
        subtitle: 'We sent a confirmation link to ${_email.text.trim()}. Open it, then sign in to finish setting up.',
        child: AppButton(label: 'Back to sign in', expand: true, onPressed: () => context.go('/login')),
      );
    }
    return AuthLayout(
      title: 'Create your account',
      subtitle: 'Set up a workspace for your company in a few minutes.',
      footer: Row(
        children: [
          const Text('Already have an account?  '),
          GestureDetector(
            onTap: () => context.go('/login'),
            child: const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[AuthError(_error!), const SizedBox(height: 16)],
            AppTextField(
              controller: _name,
              label: 'Full name',
              prefixIcon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _email,
              label: 'Work email',
              hint: 'you@company.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email address' : null,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              hint: 'At least 8 characters',
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirm password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Create account', expand: true, loading: _loading, onPressed: _submit),
            const SizedBox(height: 12),
            Text(
              'Invited by a colleague? Register with the same email address they invited and you will join their company automatically.',
              style: AppText.small,
            ),
          ],
        ),
      ),
    );
  }
}
