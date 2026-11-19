import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class AppInput {
  AppInput._();

  static OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: c, width: w),
      );

  static InputDecoration decoration({String? hint, Widget? prefixIcon, Widget? suffixIcon}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w400),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        disabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.primary, 1.6),
        errorBorder: _border(AppColors.danger),
        focusedErrorBorder: _border(AppColors.danger, 1.6),
      );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: AppText.label,
          children: [
            if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.required = false,
    this.initialValue,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool required;
  final String? initialValue;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) FieldLabel(label!, required: required),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: obscureText ? 1 : maxLines,
          minLines: 1,
          enabled: enabled,
          autofocus: autofocus,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          autofillHints: autofillHints,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
          decoration: AppInput.decoration(
            hint: hint,
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20, color: AppColors.textMuted),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint,
    this.validator,
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      obscureText: _hidden,
      validator: widget.validator,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      prefixIcon: Icons.lock_outline_rounded,
      suffix: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _hidden = !_hidden),
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: AppColors.textMuted),
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.label,
    this.hint,
    this.validator,
    this.required = false,
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final String? label;
  final String? hint;
  final String? Function(T?)? validator;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) FieldLabel(label!, required: required),
        DropdownButtonFormField<T>(
          // ignore: deprecated_member_use
          value: value,
          items: items,
          onChanged: onChanged,
          validator: validator,
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.control),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
          decoration: AppInput.decoration(hint: hint),
        ),
      ],
    );
  }
}

/// Date picker field. The value is an ISO date string (yyyy-MM-dd).
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.onChanged,
    this.label,
    this.value,
    this.required = false,
    this.firstDate,
    this.lastDate,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final bool required;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final parsed = value == null ? null : DateTime.tryParse(value!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) FieldLabel(label!, required: required),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: parsed ?? DateTime.now(),
              firstDate: firstDate ?? DateTime(2000),
              lastDate: lastDate ?? DateTime(2100),
            );
            if (picked != null) onChanged(DateFormat('yyyy-MM-dd').format(picked));
          },
          child: InputDecorator(
            isEmpty: parsed == null,
            decoration: AppInput.decoration(
              hint: 'Select date',
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textMuted),
            ),
            child: Text(Fmt.date(parsed), style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.subtitle});

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.label),
                if (subtitle != null) Text(subtitle!, style: AppText.small),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
