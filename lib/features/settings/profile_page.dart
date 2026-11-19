import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/state/models.dart';
import '../../core/state/session.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return AppPage(
      title: 'My account',
      subtitle: 'Your profile, password and signed-in devices',
      maxWidth: 760,
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(profileProvider)),
          data: (p) => p == null ? const SizedBox.shrink() : _ProfileForm(profile: p),
        ),
        const SizedBox(height: 16),
        const _PasswordCard(),
        const SizedBox(height: 16),
        const _SessionsCard(),
      ],
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.profile.fullName ?? '');
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  final _key = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(supabaseProvider).from('profiles').update({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      }).eq('id', widget.profile.id);
      ref.invalidate(profileProvider);
      if (mounted) showToast(context, 'Profile saved');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Form(
        key: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _name,
              label: 'Full name',
              required: true,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(initialValue: widget.profile.email ?? '', label: 'Email', enabled: false),
            const SizedBox(height: 16),
            AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone),
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerRight, child: AppButton(label: 'Save profile', loading: _saving, onPressed: _save)),
          ],
        ),
      ),
    );
  }
}

class _PasswordCard extends ConsumerStatefulWidget {
  const _PasswordCard();

  @override
  ConsumerState<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends ConsumerState<_PasswordCard> {
  final _key = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(supabaseProvider).auth.updateUser(UserAttributes(password: _password.text));
      _password.clear();
      _confirm.clear();
      if (mounted) showToast(context, 'Password updated');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Change password',
      child: Form(
        key: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PasswordField(
              controller: _password,
              label: 'New password',
              hint: 'At least 8 characters',
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerRight, child: AppButton(label: 'Update password', loading: _saving, onPressed: _save)),
          ],
        ),
      ),
    );
  }
}

class _SessionsCard extends ConsumerWidget {
  const _SessionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Signed-in devices',
      subtitle: 'Lost a phone or used a shared computer? End every other session.',
      child: Row(
        children: [
          AppButton(
            label: 'Sign out of other devices',
            kind: AppButtonKind.secondary,
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Sign out of other devices?',
                message: 'You stay signed in here. Every other browser and phone will be asked to sign in again.',
                confirmLabel: 'Sign out others',
              );
              if (!ok) return;
              try {
                await ref.read(supabaseProvider).auth.signOut(scope: SignOutScope.others);
                if (context.mounted) showToast(context, 'Other sessions ended');
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Sign out',
            kind: AppButtonKind.ghost,
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
    );
  }
}
