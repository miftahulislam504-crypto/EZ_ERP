import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import '../trade/trade_providers.dart';
import 'payment_models.dart';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Enters an amount a customer owed you, or you owed a supplier, from before
/// you started using EZ ERP. It is posted as an invoice or bill with its
/// original dates, so aging and payments work the same as for any document.
Future<bool> showOpeningBalance(BuildContext context, {required LedgerSide side, String? partyId}) async {
  final saved = await showAdaptiveForm<bool>(
    context,
    maxWidth: 680,
    builder: (_) => OpeningBalanceForm(side: side, partyId: partyId),
  );
  return saved == true;
}

class OpeningBalanceForm extends ConsumerStatefulWidget {
  const OpeningBalanceForm({super.key, required this.side, this.partyId});

  final LedgerSide side;
  final String? partyId;

  @override
  ConsumerState<OpeningBalanceForm> createState() => _OpeningBalanceFormState();
}

class _OpeningBalanceFormState extends ConsumerState<OpeningBalanceForm> {
  String? _party;
  String? _date = _iso(DateTime.now());
  String? _due;
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  LedgerSide get side => widget.side;

  @override
  void initState() {
    super.initState();
    _party = widget.partyId;
  }

  @override
  void dispose() {
    _reference.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    String? problem;
    if (_party == null) {
      problem = 'Choose the ${side.partyLabel.toLowerCase()}.';
    } else if (_date == null) {
      problem = 'Choose the date of the original ${side.documentLabel}.';
    } else if (amount <= 0) {
      problem = 'Enter an amount greater than zero.';
    } else if (_due != null && _due!.compareTo(_date!) < 0) {
      problem = 'The due date cannot be before the ${side.documentLabel} date.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('post_opening_balance', params: {
        'p_org': m.orgId,
        'p_kind': side.key,
        'p_party': _party,
        'p_date': _date,
        'p_due': _due,
        'p_reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'p_amount': amount,
        'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      invalidateTrade(ref);
      if (!mounted) return;
      showToast(context, 'Opening balance added');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(side.isReceivable ? customerOptions : supplierOptions).valueOrNull ?? const <Option>[];
    final w = context.isMobile ? double.infinity : 300.0;
    Widget field(Widget child) => SizedBox(width: w, child: child);

    return FormShell(
      title: 'Add opening balance',
      subtitle: side.isReceivable ? 'An amount a customer owed you before you started.' : 'An amount you owed a supplier before you started.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          AppButton(label: 'Add opening balance', loading: _saving, onPressed: _submit),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(
              'Enter each unpaid ${side.documentLabel} from before you started, with its original date and due date, so aging and overdue tracking stay accurate. '
              'If you only know the total, enter it as one entry. It is posted against Opening balance equity.',
              style: const TextStyle(color: AppColors.info, fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              field(SearchSelectField(
                label: side.partyLabel,
                required: true,
                hint: 'Select ${side.partyLabel.toLowerCase()}',
                enabled: widget.partyId == null,
                options: parties,
                value: _party,
                onChanged: (v) => setState(() => _party = v),
              )),
              field(AppTextField(
                controller: _amount,
                label: 'Amount owed',
                required: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              )),
              field(AppDateField(label: 'Original ${side.documentLabel} date', required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
              field(AppDateField(label: 'Due date', value: _due, onChanged: (v) => setState(() => _due = v))),
              field(AppTextField(controller: _reference, label: side.isReceivable ? 'Original invoice number' : 'Supplier invoice number', hint: 'Optional')),
            ],
          ),
          const SizedBox(height: 4),
          Text('Leave the due date empty to use the ${side.partyLabel.toLowerCase()}\'s payment terms.', style: AppText.small),
          const SizedBox(height: 16),
          AppTextField(controller: _notes, label: 'Notes', maxLines: 2, hint: 'Optional'),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
        ],
      ),
    );
  }
}
