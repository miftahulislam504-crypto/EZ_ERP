import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../widgets/adaptive_dialog.dart';
import '../widgets/app_button.dart';
import '../widgets/app_inputs.dart';
import 'crud_config.dart';

class CrudForm extends ConsumerStatefulWidget {
  const CrudForm({super.key, required this.config, required this.orgId, this.row});

  final CrudConfig config;
  final String orgId;
  final Map<String, dynamic>? row;

  @override
  ConsumerState<CrudForm> createState() => _CrudFormState();
}

class _CrudFormState extends ConsumerState<CrudForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, dynamic> _val = {};
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.row != null;
  CrudConfig get c => widget.config;

  /// Fields this user may see. Financial figures need the financial figures permission.
  List<FieldDef> get _fields {
    final showFinancial = ref.read(permsProvider).canView(Modules.financialData);
    return c.fields.where((f) => !f.sensitive || showFinancial).toList();
  }

  @override
  void initState() {
    super.initState();
    for (final f in c.fields) {
      final initial = widget.row != null ? widget.row![f.key] : f.defaultValue;
      switch (f.type) {
        case FieldType.dropdown:
        case FieldType.date:
        case FieldType.image:
          _val[f.key] = initial?.toString();
        case FieldType.toggle:
          _val[f.key] = initial is bool ? initial : false;
        default:
          _ctrl[f.key] = TextEditingController(text: initial?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final t in _ctrl.values) {
      t.dispose();
    }
    super.dispose();
  }

  TextInputType? _keyboard(FieldType t) => switch (t) {
        FieldType.email => TextInputType.emailAddress,
        FieldType.phone => TextInputType.phone,
        FieldType.number || FieldType.money => const TextInputType.numberWithOptions(decimal: true),
        FieldType.multiline => TextInputType.multiline,
        _ => null,
      };

  String? _validateText(FieldDef f, String? v) {
    final t = (v ?? '').trim();
    if (f.required && t.isEmpty) return '${f.label} is required';
    if (t.isEmpty) return null;
    if ((f.type == FieldType.number || f.type == FieldType.money)) {
      final n = num.tryParse(t);
      if (n == null) return 'Enter a valid number';
      if (n < 0) return 'Value cannot be negative';
    }
    if (f.type == FieldType.email && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Enter a valid email address';
    return null;
  }

  Widget _field(FieldDef f) {
    final locked = _isEdit && f.lockOnEdit;
    switch (f.type) {
      case FieldType.dropdown:
        final opts = f.options ?? (f.optionsSource != null ? ref.watch(f.optionsSource!).valueOrNull : null) ?? const <Option>[];
        final current = _val[f.key] as String?;
        return AppDropdown<String>(
          label: f.label,
          required: f.required,
          hint: f.hint ?? (opts.isEmpty ? 'No options yet' : 'Select'),
          value: opts.any((o) => o.value == current) ? current : null,
          items: [for (final o in opts) DropdownMenuItem(value: o.value, child: Text(o.label, overflow: TextOverflow.ellipsis))],
          onChanged: locked ? null : (v) => setState(() => _val[f.key] = v),
          validator: f.required ? (v) => v == null ? '${f.label} is required' : null : null,
        );
      case FieldType.toggle:
        return AppSwitchRow(
          label: f.label,
          subtitle: f.hint,
          value: _val[f.key] == true,
          onChanged: (v) => setState(() => _val[f.key] = v),
        );
      case FieldType.date:
        return AppDateField(
          label: f.label,
          required: f.required,
          value: _val[f.key] as String?,
          onChanged: (v) => setState(() => _val[f.key] = v),
        );
      case FieldType.image:
        return _ImageField(
          label: f.label,
          bucket: f.imageBucket,
          orgId: widget.orgId,
          url: _val[f.key] as String?,
          onChanged: (v) => setState(() => _val[f.key] = v),
        );
      default:
        return AppTextField(
          controller: _ctrl[f.key],
          label: f.label,
          hint: f.hint,
          required: f.required,
          enabled: !locked,
          maxLines: f.type == FieldType.multiline ? 3 : 1,
          keyboardType: _keyboard(f.type),
          validator: (v) => _validateText(f, v),
        );
    }
  }

  Widget _grid(List<FieldDef> fields, double maxWidth) {
    final twoCols = maxWidth >= 480;
    final half = twoCols ? (maxWidth - 16) / 2 : maxWidth;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final f in fields)
          SizedBox(
            width: (f.fullWidth || f.type == FieldType.multiline || f.type == FieldType.image) ? maxWidth : half,
            child: _field(f),
          ),
      ],
    );
  }

  Widget _sections(double maxWidth) {
    final fields = _fields;
    final order = <String?>[];
    for (final f in fields) {
      if (!order.contains(f.section)) order.add(f.section);
    }
    final children = <Widget>[];
    for (final section in order) {
      final group = fields.where((f) => f.section == section).toList();
      final grid = _grid(group, maxWidth);
      if (section == null) {
        children.add(grid);
      } else if (c.collapsedSections.contains(section)) {
        children.add(
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              maintainState: true,
              title: Text(section, style: AppText.h3),
              children: [grid],
            ),
          ),
        );
      } else {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(section, style: AppText.h3)));
        children.add(grid);
      }
      children.add(const SizedBox(height: 20));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{};
    for (final f in _fields) {
      if (_isEdit && f.lockOnEdit) continue;
      dynamic v;
      switch (f.type) {
        case FieldType.toggle:
          v = _val[f.key] == true;
        case FieldType.dropdown:
        case FieldType.date:
        case FieldType.image:
          v = _val[f.key];
        case FieldType.number:
        case FieldType.money:
          {
            final t = _ctrl[f.key]!.text.trim();
            v = t.isEmpty ? (f.defaultValue is num ? f.defaultValue : null) : num.tryParse(t);
          }
        default:
          {
            final t = _ctrl[f.key]!.text.trim();
            v = t.isEmpty ? null : t;
          }
      }
      payload[f.key] = v;
    }

    try {
      final client = ref.read(supabaseProvider);
      if (_isEdit) {
        await client.from(c.table).update(payload).eq('id', widget.row!['id'] as Object);
      } else {
        // Empty values are omitted on create so database defaults (such as automatic codes) apply.
        payload.removeWhere((k, v) => v == null);
        await client.from(c.table).insert({...payload, ...c.extraInsert, 'org_id': widget.orgId});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormShell(
        title: _isEdit ? 'Edit ${c.singular.toLowerCase()}' : 'Add ${c.singular.toLowerCase()}',
        child: LayoutBuilder(
          builder: (context, cons) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sections(cons.maxWidth),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ),
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: _isEdit ? 'Save changes' : 'Create', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Image upload field. Files go to a public bucket under "<org id>/".
class _ImageField extends ConsumerStatefulWidget {
  const _ImageField({required this.label, required this.bucket, required this.orgId, required this.url, required this.onChanged});

  final String label;
  final String bucket;
  final String orgId;
  final String? url;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends ConsumerState<_ImageField> {
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read that file. Try another image.');
      return;
    }
    if (bytes.length > 3 * 1024 * 1024) {
      setState(() => _error = 'Choose an image smaller than 3 MB.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      var ext = (file.extension ?? 'png').toLowerCase();
      if (ext == 'jpg') ext = 'jpeg';
      final path = '${widget.orgId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await client.storage.from(widget.bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );
      widget.onChanged(client.storage.from(widget.bucket).getPublicUrl(path));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(widget.label),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: AppColors.border),
              ),
              child: url == null
                  ? const Icon(Icons.image_outlined, color: AppColors.textMuted)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                    ),
            ),
            const SizedBox(width: 14),
            AppButton(
              label: url == null ? 'Upload image' : 'Replace',
              icon: Icons.upload_rounded,
              kind: AppButtonKind.secondary,
              compact: true,
              loading: _uploading,
              onPressed: _pick,
            ),
            if (url != null) ...[
              const SizedBox(width: 8),
              AppButton(label: 'Remove', kind: AppButtonKind.ghost, compact: true, onPressed: () => widget.onChanged(null)),
            ],
          ],
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
      ],
    );
  }
}
