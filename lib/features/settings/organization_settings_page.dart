import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/feedback.dart';

final _orgDetailsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <String, dynamic>{};
  return await ref.watch(supabaseProvider).from('organizations').select().eq('id', m.orgId).single();
});

class OrganizationSettingsPage extends ConsumerWidget {
  const OrganizationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permsProvider);
    if (!perms.canView(Modules.settings)) return const NoAccessView();
    final async = ref.watch(_orgDetailsProvider);
    return AppPage(
      title: 'Organization',
      subtitle: 'Company details used on invoices, vouchers and reports',
      maxWidth: 980,
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_orgDetailsProvider)),
          data: (org) => _OrgForm(org: org, canEdit: perms.can(Modules.settings, PermAction.edit)),
        ),
      ],
    );
  }
}

class _OrgForm extends ConsumerStatefulWidget {
  const _OrgForm({required this.org, required this.canEdit});
  final Map<String, dynamic> org;
  final bool canEdit;

  @override
  ConsumerState<_OrgForm> createState() => _OrgFormState();
}

class _OrgFormState extends ConsumerState<_OrgForm> {
  static const _textKeys = [
    'name', 'legal_name', 'trade_license_no', 'tax_id', 'email', 'phone', 'website',
    'address_line', 'district', 'upazila', 'area', 'postal_code',
  ];
  static const _businessTypes = [
    'Retail', 'Wholesale and distribution', 'Manufacturing', 'Trading, import and export', 'Services',
    'Construction', 'Restaurant and hospitality', 'Healthcare', 'Education', 'Other',
  ];
  static const _divisions = ['Barishal', 'Chattogram', 'Dhaka', 'Khulna', 'Mymensingh', 'Rajshahi', 'Rangpur', 'Sylhet'];
  static const _currencies = ['BDT', 'USD', 'EUR', 'GBP', 'INR', 'AED', 'SAR'];
  static const _dateFormats = ['dd MMM yyyy', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'];
  static const _timezones = ['Asia/Dhaka', 'Asia/Kolkata', 'Asia/Dubai', 'Asia/Riyadh', 'Europe/London', 'UTC'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  String? _type;
  String? _division;
  late String _currency;
  late String _dateFormat;
  late String _timezone;
  late int _fiscalMonth;
  bool _saving = false;
  bool _uploading = false;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    final o = widget.org;
    for (final k in _textKeys) {
      _c[k] = TextEditingController(text: (o[k] as String?) ?? '');
    }
    _type = o['business_type'] as String?;
    _division = o['division'] as String?;
    _currency = (o['currency_code'] as String?) ?? 'BDT';
    _dateFormat = (o['date_format'] as String?) ?? 'dd MMM yyyy';
    _timezone = (o['timezone'] as String?) ?? 'Asia/Dhaka';
    _fiscalMonth = (o['fiscal_year_start_month'] as int?) ?? 7;
    _logoUrl = o['logo_url'] as String?;
  }

  @override
  void dispose() {
    for (final t in _c.values) {
      t.dispose();
    }
    super.dispose();
  }

  String? _nullable(String key) {
    final t = _c[key]!.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(supabaseProvider).from('organizations').update({
        'name': _c['name']!.text.trim(),
        for (final k in _textKeys.where((k) => k != 'name')) k: _nullable(k),
        'business_type': _type,
        'division': _division,
        'currency_code': _currency,
        'date_format': _dateFormat,
        'timezone': _timezone,
        'fiscal_year_start_month': _fiscalMonth,
      }).eq('id', widget.org['id'] as Object);
      ref.invalidate(membershipsProvider);
      ref.invalidate(_orgDetailsProvider);
      if (mounted) showToast(context, 'Organization settings saved');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadLogo() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showToast(context, 'Could not read that file. Try another image.', error: true);
      return;
    }
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) showToast(context, 'Choose an image smaller than 2 MB.', error: true);
      return;
    }
    setState(() => _uploading = true);
    try {
      final client = ref.read(supabaseProvider);
      final orgId = widget.org['id'] as String;
      var ext = (file.extension ?? 'png').toLowerCase();
      if (ext == 'jpg') ext = 'jpeg';
      final path = '$orgId/logo-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await client.storage.from('org-assets').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );
      final url = client.storage.from('org-assets').getPublicUrl(path);
      await client.from('organizations').update({'logo_url': url}).eq('id', orgId);
      ref.invalidate(membershipsProvider);
      ref.invalidate(_orgDetailsProvider);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _text(String key, String label, {bool required = false, TextInputType? type, String? hint}) {
    return AppTextField(
      controller: _c[key],
      label: label,
      hint: hint,
      required: required,
      keyboardType: type,
      enabled: widget.canEdit,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    );
  }

  Widget _grid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, cons) {
        final twoCols = cons.maxWidth >= 560;
        final w = twoCols ? (cons.maxWidth - 16) / 2 : cons.maxWidth;
        return Wrap(spacing: 16, runSpacing: 16, children: [for (final c in children) SizedBox(width: w, child: c)]);
      },
    );
  }

  Widget _dropdown<T>(String label, T? value, List<T> items, ValueChanged<T?> onChanged, {String Function(T)? text}) {
    return AppDropdown<T>(
      label: label,
      hint: 'Select',
      value: value,
      items: [for (final i in items) DropdownMenuItem<T>(value: i, child: Text(text == null ? '$i' : text(i)))],
      onChanged: widget.canEdit ? onChanged : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _c['name']!.text;
    return Form(
      key: _form,
      child: Column(
        children: [
          SectionCard(
            title: 'Company identity',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InitialsAvatar(name: name, size: 64, imageUrl: _logoUrl),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Company logo', style: AppText.label),
                          const SizedBox(height: 2),
                          Text('PNG or JPG, up to 2 MB. Shown in the workspace and on printed documents.', style: AppText.small),
                          const SizedBox(height: 10),
                          if (widget.canEdit)
                            AppButton(
                              label: _logoUrl == null ? 'Upload logo' : 'Replace logo',
                              icon: Icons.upload_rounded,
                              kind: AppButtonKind.secondary,
                              compact: true,
                              loading: _uploading,
                              onPressed: _uploadLogo,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _grid([
                  _text('name', 'Company name', required: true),
                  _text('legal_name', 'Legal name'),
                  _dropdown<String>('Business type', _type, _businessTypes, (v) => setState(() => _type = v)),
                  _text('trade_license_no', 'Trade license number'),
                  _text('tax_id', 'Tax or BIN number'),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Contact',
            child: _grid([
              _text('email', 'Email', type: TextInputType.emailAddress),
              _text('phone', 'Phone', type: TextInputType.phone),
              _text('website', 'Website', type: TextInputType.url),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Address',
            child: _grid([
              _text('address_line', 'Address'),
              _dropdown<String>('Division', _division, _divisions, (v) => setState(() => _division = v)),
              _text('district', 'District'),
              _text('upazila', 'Upazila or thana'),
              _text('area', 'Area'),
              _text('postal_code', 'Postal code'),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Regional settings',
            subtitle: 'Applied to new documents and reports',
            child: _grid([
              _dropdown<String>('Default currency', _currency, _currencies, (v) => setState(() => _currency = v ?? 'BDT')),
              _dropdown<String>('Date format', _dateFormat, _dateFormats, (v) => setState(() => _dateFormat = v ?? _dateFormat)),
              _dropdown<String>('Time zone', _timezone, _timezones, (v) => setState(() => _timezone = v ?? _timezone)),
              _dropdown<int>('Financial year starts in', _fiscalMonth, List.generate(12, (i) => i + 1),
                  (v) => setState(() => _fiscalMonth = v ?? 7),
                  text: (m) => _months[m - 1]),
            ]),
          ),
          if (widget.canEdit) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(label: 'Save changes', loading: _saving, onPressed: _save),
            ),
          ],
        ],
      ),
    );
  }
}
