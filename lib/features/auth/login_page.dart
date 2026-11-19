import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/state/session.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_inputs.dart';
import 'auth_layout.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
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
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to your EZ ERP workspace.',
      footer: Row(
        children: [
          const Text('New to EZ ERP?  '),
          GestureDetector(
            onTap: () => context.go('/register'),
            child: const Text('Create an account', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F6B5C))),
          ),
        ],
      ),
      child: Form(
        key: _form,
        child: AutofillGroup(
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email address' : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(label: 'Forgot password?', kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go('/forgot-password')),
              ),
              const SizedBox(height: 8),
              AppButton(label: 'Sign in', expand: true, loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
