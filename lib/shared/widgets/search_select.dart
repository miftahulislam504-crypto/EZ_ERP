import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../crud/crud_config.dart';
import 'adaptive_dialog.dart';
import 'app_inputs.dart';

class _Pick {
  const _Pick(this.value);
  final String? value;
}

/// A select field with a search box, for long lists such as accounts and parties.
class SearchSelectField extends StatelessWidget {
  const SearchSelectField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'Select',
    this.required = false,
    this.enabled = true,
    this.clearable = false,
    this.validator,
  });

  final List<Option> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final String hint;
  final bool required;
  final bool enabled;
  final bool clearable;
  final String? Function(String?)? validator;

  Option? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final pick = await showAdaptiveForm<_Pick>(
      context,
      maxWidth: 480,
      builder: (_) => _SearchSheet(title: label ?? 'Select', options: options, selected: value, clearable: clearable),
    );
    if (pick != null) onChanged(pick.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return FormField<String>(
      validator: (_) => validator?.call(value),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) FieldLabel(label!, required: required),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: enabled ? () => _open(context) : null,
            child: InputDecorator(
              isEmpty: selected == null,
              decoration: AppInput.decoration(
                hint: hint,
                suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              ),
              child: Text(
                selected?.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, color: enabled ? AppColors.textPrimary : AppColors.textMuted),
              ),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(state.errorText!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.title, required this.options, required this.selected, required this.clearable});

  final String title;
  final List<Option> options;
  final String? selected;
  final bool clearable;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final matches = widget.options.where((o) => q.isEmpty || o.label.toLowerCase().contains(q)).toList();
    final shown = matches.take(60).toList();
    return FormShell(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            autofocus: true,
            hint: 'Search',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (widget.clearable && widget.selected != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.close_rounded, size: 20),
              title: const Text('Clear selection'),
              onTap: () => Navigator.of(context).pop(const _Pick(null)),
            ),
          if (shown.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text('No matches', style: AppText.body))
          else
            for (final o in shown)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                title: Text(o.label, style: AppText.bodyStrong.copyWith(fontSize: 14)),
                trailing: o.value == widget.selected ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20) : null,
                onTap: () => Navigator.of(context).pop(_Pick(o.value)),
              ),
          if (matches.length > shown.length)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Showing ${shown.length} of ${matches.length}. Keep typing to narrow the list.', style: AppText.small),
            ),
        ],
      ),
    );
  }
}
