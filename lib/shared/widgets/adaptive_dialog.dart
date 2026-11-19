import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

/// Dialog on wide screens, bottom sheet on phones.
Future<T?> showAdaptiveForm<T>(BuildContext context, {required WidgetBuilder builder, double maxWidth = 580}) {
  if (context.isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(ctx),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: builder(ctx)),
    ),
  );
}

/// Standard layout for form dialogs and sheets: title, scrolling body, footer.
class FormShell extends StatelessWidget {
  const FormShell({super.key, required this.title, required this.child, this.subtitle, this.footer});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.h2),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.small),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: child,
          ),
        ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: footer,
          ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      title: Text(title, style: AppText.h3),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(message, style: AppText.body),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: danger ? AppColors.danger : AppColors.primary),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a short piece of text, such as a rejection reason. Returns null if cancelled.
Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? message,
  bool required = true,
  bool danger = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PromptDialog(title: title, label: label, confirmLabel: confirmLabel, message: message, required: required, danger: danger),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.message,
    required this.required,
    required this.danger,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? message;
  final bool required;
  final bool danger;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _error = '${widget.label} is required');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      title: Text(widget.title, style: AppText.h3),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[Text(widget.message!, style: AppText.body), const SizedBox(height: 14)],
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _error,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: widget.danger ? AppColors.danger : AppColors.primary),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
