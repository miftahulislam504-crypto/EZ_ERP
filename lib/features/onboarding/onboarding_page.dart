import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../auth/auth_layout.dart';
import '../../shell/sidebar.dart';

/// First-run company setup for a user who does not belong to any company yet.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _businessTypes = [
    'Retail',
    'Wholesale and distribution',
    'Manufacturing',
    'Trading, import and export',
    'Services',
    'Construction',
    'Restaurant and hospitality',
    'Healthcare',
    'Education',
    'Other',
  ];
  static const _divisions = ['Barishal', 'Chattogram', 'Dhaka', 'Khulna', 'Mymensingh', 'Rajshahi', 'Rangpur', 'Sylhet'];
  static const _currencies = ['BDT', 'USD', 'EUR', 'GBP', 'INR', 'AED', 'SAR'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final _step1 = GlobalKey<FormState>();
  final _step2 = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _district = TextEditingController();
  String? _type;
  String? _division;
  String _currency = 'BDT';
  int _fiscalMonth = 7;
  int _step = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _district.dispose();
    super.dispose();
  }

  void _next() {
    if (_step1.currentState!.validate()) setState(() => _step = 1);
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await ref.read(supabaseProvider).rpc('create_organization', params: {
        'p_name': _name.text.trim(),
        'p_business_type': _type,
        'p_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'p_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'p_division': _division,
        'p_district': _district.text.trim().isEmpty ? null : _district.text.trim(),
        'p_currency': _currency,
        'p_fiscal_year_start_month': _fiscalMonth,
      });
      await ref.read(activeOrgIdProvider.notifier).select(id as String);
      ref.invalidate(membershipsProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Widget _stepOne() {
    return Form(
      key: _step1,
      child: Column(
        key: const ValueKey('step1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Company name',
            required: true,
            hint: 'For example, Rahman Trading Ltd',
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your company name' : null,
          ),
          const SizedBox(height: 16),
          AppDropdown<String>(
            label: 'Business type',
            hint: 'Select',
            value: _type,
            items: [for (final t in _businessTypes) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 16),
          AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone),
          const SizedBox(height: 16),
          AppTextField(controller: _email, label: 'Business email', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 24),
          AppButton(label: 'Continue', expand: true, onPressed: _next),
        ],
      ),
    );
  }

  Widget _stepTwo() {
    return Form(
      key: _step2,
      child: Column(
        key: const ValueKey('step2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[AuthError(_error!), const SizedBox(height: 16)],
          AppDropdown<String>(
            label: 'Division',
            hint: 'Select',
            value: _division,
            items: [for (final d in _divisions) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _division = v),
          ),
          const SizedBox(height: 16),
          AppTextField(controller: _district, label: 'District'),
          const SizedBox(height: 16),
          AppDropdown<String>(
            label: 'Currency',
            value: _currency,
            items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _currency = v ?? 'BDT'),
          ),
          const SizedBox(height: 16),
          AppDropdown<int>(
            label: 'Financial year starts in',
            value: _fiscalMonth,
            items: [for (var i = 0; i < 12; i++) DropdownMenuItem(value: i + 1, child: Text(_months[i]))],
            onChanged: (v) => setState(() => _fiscalMonth = v ?? 7),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              AppButton(label: 'Back', kind: AppButtonKind.secondary, onPressed: _loading ? null : () => setState(() => _step = 0)),
              const SizedBox(width: 12),
              Expanded(child: AppButton(label: 'Create workspace', loading: _loading, onPressed: _create)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(size: 44),
                const SizedBox(height: 24),
                Text(_step == 0 ? 'Set up your company' : 'Where and how you operate', style: AppText.h1),
                const SizedBox(height: 6),
                Text(
                  _step == 0
                      ? 'This creates your workspace. You can change every detail later in Settings.'
                      : 'These defaults shape your calendar, currency and numbering.',
                  style: AppText.body,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 4,
                          margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                          decoration: BoxDecoration(
                            color: i <= _step ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _step == 0 ? _stepOne() : _stepTwo(),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: AppButton(
                    label: 'Sign out',
                    kind: AppButtonKind.ghost,
                    compact: true,
                    onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
