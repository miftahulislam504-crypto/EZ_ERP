import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_form.dart';
import '../../shared/crud/crud_page.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/stat_card.dart';
import '../masters/party_pages.dart';
import '../trade/trade_models.dart';
import 'opening_balance_dialog.dart';
import 'payment_access.dart';
import 'payment_models.dart';
import 'payment_providers.dart';
import 'record_payment_dialog.dart';

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

/// A customer or supplier: what they owe or are owed, credit, documents,
/// payments, statement and contact details in one place.
class PartyProfilePage extends ConsumerStatefulWidget {
  const PartyProfilePage({super.key, required this.side, required this.partyId});

  final LedgerSide side;
  final String partyId;

  @override
  ConsumerState<PartyProfilePage> createState() => _PartyProfilePageState();
}

class _PartyProfilePageState extends ConsumerState<PartyProfilePage> {
  int _tab = 0;
  bool _openOnly = false;
  String? _from;
  String? _to;

  LedgerSide get side => widget.side;
  String get id => widget.partyId;

  Future<void> _edit(Map<String, dynamic> row, String org) async {
    final saved = await showAdaptiveForm<bool>(
      context,
      maxWidth: 680,
      builder: (_) => CrudForm(config: side.isReceivable ? customerCrudConfig : supplierCrudConfig, orgId: org, row: row),
    );
    if (saved == true) {
      ref.invalidate(partyRowProvider);
      ref.invalidate(partySummaryProvider);
      ref.invalidate(crudListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(side.module)) return const NoAccessView();
    final async = ref.watch(partyRowProvider(id));
    final listPath = side.isReceivable ? '/sales/customers' : '/purchase/suppliers';

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(partyRowProvider)),
      data: (party) {
        final isRole = party != null && (side.isReceivable ? party['is_customer'] == true : party['is_supplier'] == true);
        if (!isRole) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: '${side.partyLabel} not found',
            message: 'It may have been removed, or you may not have access to it.',
            actionLabel: 'Back to ${side.partyLabel.toLowerCase()}s',
            onAction: () => context.go(listPath),
          );
        }
        final summary = ref.watch(partySummaryProvider((org: m.orgId, party: id))).valueOrNull;
        final canRecord = canRecordPayment(perms, side);
        final canEdit = perms.can(side.module, PermAction.edit);
        final canCreate = perms.can(side.module, PermAction.create);
        final legacy = _n(side.isReceivable ? party['opening_receivable'] : party['opening_payable']);

        final actions = <Widget>[
          if (canRecord) AppButton(label: side.recordLabel, icon: Icons.payments_outlined, onPressed: () => showRecordPayment(context, side: side, partyId: id)),
          if (canCreate && side.isReceivable) AppButton(label: 'New invoice', icon: Icons.receipt_long_outlined, kind: AppButtonKind.secondary, onPressed: () => context.go('${invoiceType.newPath}?customer=$id')),
          if (canCreate && side.isReceivable) AppButton(label: 'New quotation', icon: Icons.request_quote_outlined, kind: AppButtonKind.secondary, onPressed: () => context.go('${quotationType.newPath}?customer=$id')),
          if (canCreate && !side.isReceivable) AppButton(label: 'New bill', icon: Icons.description_outlined, kind: AppButtonKind.secondary, onPressed: () => context.go('${billType.newPath}?supplier=$id')),
          if (canEnterOpening(perms)) AppButton(label: 'Add opening balance', icon: Icons.history_rounded, kind: AppButtonKind.secondary, onPressed: () => showOpeningBalance(context, side: side, partyId: id)),
          if (canEdit) AppButton(label: 'Edit details', icon: Icons.edit_outlined, kind: AppButtonKind.ghost, onPressed: () => _edit(party, m.orgId)),
        ];

        return AppPage(
          title: '${party['name']}',
          subtitle: '${side.partyLabel}${party['code'] == null ? '' : '   ${party['code']}'}',
          maxWidth: 1100,
          actions: actions,
          children: [
            if (legacy > 0 && canEnterOpening(perms))
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 19, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A balance of ${Fmt.money(legacy, currency: m.currency)} was typed on this profile before opening ${side.documentLabel}s existed, so it is not in your books. Add it as an opening ${side.documentLabel} with its original date.',
                      style: const TextStyle(color: AppColors.warning, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            _stats(summary, m.currency, party),
            const SizedBox(height: 16),
            PillTabs(labels: ['Documents', side.paymentsTabLabel, 'Statement', 'Details'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
            const SizedBox(height: 16),
            switch (_tab) {
              0 => _documents(m.orgId, m.currency),
              1 => _payments(m.orgId, m.currency),
              2 => _statement(m.orgId, m.currency),
              _ => _details(party),
            },
          ],
        );
      },
    );
  }

  Widget _stats(Map<String, dynamic>? s, String currency, Map<String, dynamic> party) {
    String money(Object? v) => Fmt.money(_n(v), currency: currency);
    final cards = side.isReceivable
        ? <Widget>[
            StatCard(label: 'Outstanding', value: s == null ? null : money(s['receivable_open']), icon: Icons.account_balance_wallet_outlined),
            StatCard(label: 'Overdue', value: s == null ? null : money(s['receivable_overdue']), icon: Icons.event_busy_outlined, tone: _n(s?['receivable_overdue']) > 0 ? BadgeTone.danger : BadgeTone.neutral),
            StatCard(label: 'Customer advance', value: s == null ? null : money(s['receivable_advance']), icon: Icons.savings_outlined, tone: BadgeTone.info, hint: 'Received, not yet applied'),
            StatCard(
              label: 'Credit available',
              value: s == null ? null : (s['available_credit'] == null ? 'No limit' : money(s['available_credit'])),
              icon: Icons.speed_outlined,
              tone: s != null && s['available_credit'] != null && _n(s['available_credit']) < 0 ? BadgeTone.danger : BadgeTone.success,
              hint: s?['credit_limit'] == null ? null : 'Limit ${money(s!['credit_limit'])}',
            ),
          ]
        : <Widget>[
            StatCard(label: 'You owe', value: s == null ? null : money(s['payable_open']), icon: Icons.account_balance_wallet_outlined),
            StatCard(label: 'Overdue', value: s == null ? null : money(s['payable_overdue']), icon: Icons.event_busy_outlined, tone: _n(s?['payable_overdue']) > 0 ? BadgeTone.danger : BadgeTone.neutral),
            StatCard(label: 'Advance paid', value: s == null ? null : money(s['payable_advance']), icon: Icons.savings_outlined, tone: BadgeTone.info, hint: 'Paid, not yet applied'),
            StatCard(label: 'Payment terms', value: party['payment_terms_days'] == null ? 'Not set' : '${party['payment_terms_days']} days', icon: Icons.schedule_outlined, tone: BadgeTone.primary),
          ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final x in cards) SizedBox(width: w, child: x)]);
      },
    );
  }

  // ---------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------
  Widget _documents(String org, String currency) {
    final types = side.isReceivable ? const ['sales_invoice', 'sales_order', 'sales_quotation'] : const ['supplier_bill', 'purchase_order', 'goods_receipt'];
    final async = ref.watch(partyDocumentsProvider((org: org, party: id, types: types)));
    final balances = ref.watch(documentBalancesProvider((org: org, type: side.docType))).valueOrNull ?? const <String, Map<String, dynamic>>{};
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(partyDocumentsProvider)),
      data: (all) {
        final rows = all.where((r) {
          if (!_openOnly) return true;
          final b = balances['${r['id']}'];
          return b != null && _n(b['balance']) > 0;
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: context.isMobile ? double.infinity : 360, child: AppSwitchRow(label: 'Only ${side.documentLabel}s with an amount still to pay', value: _openOnly, onChanged: (v) => setState(() => _openOnly = v))),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              AppCard(child: EmptyState(icon: Icons.description_outlined, title: all.isEmpty ? 'No documents yet' : 'Nothing matches', message: all.isEmpty ? 'Quotations, orders and invoices for this customer appear here.' : null))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final r in rows) ...[
                      InkWell(
                        onTap: () {
                          final path = tradeDocumentPath('${r['doc_type']}', '${r['id']}');
                          if (path != null) context.go(path);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(children: [
                            Icon(tradeTypes['${r['doc_type']}']?.icon ?? Icons.description_outlined, size: 20, color: AppColors.textMuted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${r['number']}${r['is_opening'] == true ? '  (opening balance)' : ''}', style: AppText.bodyStrong),
                                Text('${tradeTypes['${r['doc_type']}']?.label ?? ''}, ${Fmt.date(DateTime.tryParse('${r['doc_date']}'))}${r['reference'] == null ? '' : ', ${r['reference']}'}', style: AppText.small),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(Fmt.money(_n(r['total']), currency: currency), style: AppText.bodyStrong),
                              if (balances['${r['id']}'] != null && _n(balances['${r['id']}']!['balance']) > 0)
                                Text('${Fmt.money(_n(balances['${r['id']}']!['balance']), currency: currency)} to pay', style: AppText.small.copyWith(color: AppColors.warning)),
                            ]),
                            const SizedBox(width: 14),
                            _docBadge(r, balances['${r['id']}']),
                          ]),
                        ),
                      ),
                      if (r != rows.last) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _docBadge(Map<String, dynamic> r, Map<String, dynamic>? b) {
    final status = '${r['status']}';
    if (status == 'posted' && b != null && (r['doc_type'] == 'sales_invoice' || r['doc_type'] == 'supplier_bill')) {
      final state = paymentStateOf(total: _n(r['total']), paid: _n(b['paid']), daysOverdue: (b['days_overdue'] as num?)?.toInt() ?? 0);
      return StatusBadge.status(state);
    }
    return StatusBadge.status(status);
  }

  // ---------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------
  Widget _payments(String org, String currency) {
    final async = ref.watch(paymentsListProvider((org: org, kind: side.paymentKind, party: id)));
    final balances = ref.watch(paymentBalancesProvider((org: org, kind: side.paymentKind))).valueOrNull ?? const <String, ({double allocated, double unallocated})>{};
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(paymentsListProvider)),
      data: (rows) {
        if (rows.isEmpty) {
          return AppCard(child: EmptyState(icon: Icons.payments_outlined, title: 'No ${side.paymentsTabLabel.toLowerCase()} yet', message: 'Money ${side.isReceivable ? 'received from' : 'paid to'} this ${side.partyLabel.toLowerCase()} appears here.'));
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final r in rows) ...[
                InkWell(
                  onTap: () => context.go(side.paymentPath('${r['id']}')),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.payments_outlined, size: 20, color: AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['number']}', style: AppText.bodyStrong),
                          Text('${Fmt.date(DateTime.tryParse('${r['pay_date']}'))}, ${(r['account'] as Map?)?['name'] ?? ''}${r['reference'] == null ? '' : ', ${r['reference']}'}', style: AppText.small),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(Fmt.money(_n(r['amount']), currency: currency), style: AppText.bodyStrong),
                        if ((balances['${r['id']}']?.unallocated ?? 0) > 0) Text('${Fmt.money(balances['${r['id']}']!.unallocated, currency: currency)} unapplied', style: AppText.small.copyWith(color: AppColors.info)),
                      ]),
                      const SizedBox(width: 14),
                      StatusBadge.status('${r['status']}'),
                    ]),
                  ),
                ),
                if (r != rows.last) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Statement
  // ---------------------------------------------------------------------
  Widget _statement(String org, String currency) {
    final async = ref.watch(statementProvider((org: org, party: id, role: side.role, from: _from, to: _to)));
    final w = context.isMobile ? double.infinity : 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(width: w, child: AppDateField(label: 'From', value: _from, onChanged: (v) => setState(() => _from = v))),
            SizedBox(width: w, child: AppDateField(label: 'To', value: _to, onChanged: (v) => setState(() => _to = v))),
            if (_from != null || _to != null)
              Padding(padding: const EdgeInsets.only(top: 22), child: AppButton(label: 'Clear dates', kind: AppButtonKind.ghost, compact: true, onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }))),
          ],
        ),
        const SizedBox(height: 14),
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(statementProvider)),
          data: (rows) {
            if (rows.isEmpty) return AppCard(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No activity', message: 'Posted ${side.documentLabel}s and ${side.paymentsTabLabel.toLowerCase()} appear here with a running balance.'));
            final closing = _n(rows.last['balance']);
            Widget head(String text, int flex, {bool right = false}) =>
                Expanded(flex: flex, child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
            String cell(double v) => v == 0 ? '' : Fmt.money(v, currency: currency);
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFFF7F9F8),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(children: [
                      head('Date', 2),
                      head('Document', 3),
                      if (!context.isMobile) head('Reference', 3),
                      head(side.isReceivable ? 'Invoiced' : 'Billed', 2, right: true),
                      head(side.isReceivable ? 'Received' : 'Paid', 2, right: true),
                      head('Balance', 2, right: true),
                    ]),
                  ),
                  for (final r in rows) ...[
                    const Divider(height: 1),
                    InkWell(
                      onTap: r['doc_id'] == null
                          ? null
                          : () {
                              final type = '${r['doc_type']}';
                              final path = type == 'customer_receipt' || type == 'supplier_payment' ? side.paymentPath('${r['doc_id']}') : tradeDocumentPath(type, '${r['doc_id']}');
                              if (path != null) context.go(path);
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                        child: Row(children: [
                          Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['entry_date']}')), style: AppText.body)),
                          Expanded(
                            flex: 3,
                            child: Text(
                              r['row_type'] == 'opening' ? 'Balance brought forward' : '${r['number']}${r['is_opening'] == true ? ' (opening)' : ''}',
                              style: r['row_type'] == 'opening' ? AppText.body.copyWith(fontStyle: FontStyle.italic) : AppText.bodyStrong,
                            ),
                          ),
                          if (!context.isMobile) Expanded(flex: 3, child: Text('${r['reference'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                          Expanded(flex: 2, child: Text(cell(_n(r['charge'])), textAlign: TextAlign.right, style: AppText.body)),
                          Expanded(flex: 2, child: Text(cell(_n(r['payment'])), textAlign: TextAlign.right, style: AppText.body)),
                          Expanded(flex: 2, child: Text(Fmt.money(_n(r['balance']), currency: currency), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                        ]),
                      ),
                    ),
                  ],
                  const Divider(height: 1),
                  Container(
                    color: const Color(0xFFF7F9F8),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(children: [
                      Expanded(child: Text(side.isReceivable ? 'Closing balance (owed to you)' : 'Closing balance (you owe)', style: AppText.bodyStrong)),
                      Text(Fmt.money(closing, currency: currency), style: AppText.h3),
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Details
  // ---------------------------------------------------------------------
  Widget _details(Map<String, dynamic> p) {
    Widget info(String label, Object? value) => SizedBox(
          width: 240,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.small), const SizedBox(height: 2), Text(value == null || '$value'.isEmpty ? '--' : '$value', style: AppText.bodyStrong)]),
        );
    final groupRow = (side.isReceivable ? p['customer_group'] : p['supplier_category']) as Map?;
    final group = groupRow?['name'];
    final address = [p['address_line'], p['area'], p['upazila'], p['district'], p['division'], p['postal_code']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    return SectionCard(
      title: 'Details',
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          info('Status', p['is_active'] == false ? 'Archived' : 'Active'),
          info('Type', Fmt.humanize('${p['party_type']}')),
          info('Contact person', p['contact_person']),
          info('Phone', p['phone']),
          info('Email', p['email']),
          info('Website', p['website']),
          info(side.isReceivable ? 'Customer group' : 'Supplier category', group),
          info('Payment terms', p['payment_terms_days'] == null ? null : '${p['payment_terms_days']} days'),
          if (side.isReceivable) info('Credit limit', p['credit_limit'] == null ? null : Fmt.money(_n(p['credit_limit']))),
          info('Trade license number', p['trade_license_no']),
          info('Tax or BIN number', p['tax_id']),
          info('Billing address', address),
          if (side.isReceivable) info('Shipping address', p['shipping_address']),
          if (p['notes'] != null) info('Notes', p['notes']),
        ],
      ),
    );
  }
}
