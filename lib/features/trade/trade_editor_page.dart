import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/option_sources.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import '../finance/finance_providers.dart';
import '../payments/payment_providers.dart';
import 'sales_actions.dart';
import 'trade_models.dart';
import 'trade_providers.dart';

class _Line {
  _Line({
    this.productId,
    String description = '',
    String qty = '',
    String price = '',
    String discount = '',
    this.taxRateId,
    this.accountId,
    this.sourceLineId,
    this.sourceLabel,
    this.maxQty,
    this.isStock = false,
    this.locked = false,
  })  : description = TextEditingController(text: description),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price),
        discount = TextEditingController(text: discount);

  String? productId;
  String? taxRateId;
  String? accountId;

  /// Line on an earlier document this one was created from.
  String? sourceLineId;
  String? sourceLabel;
  double? maxQty;
  bool isStock;

  /// Linked lines keep their item; only quantity, price and tax can change.
  bool locked;
  final TextEditingController description;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController discount;

  void dispose() {
    description.dispose();
    qty.dispose();
    price.dispose();
    discount.dispose();
  }
}

double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

String _plain(num v) {
  final s = v.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Creates or edits a draft purchase or sales document. One form serves
/// requisitions, orders, receipts and bills, and quotations, sales orders and
/// invoices; the fields shown follow the document type.
///
/// [fromId] pre-fills the form from an earlier document: a requisition for an
/// order, an order for a receipt, a receipt for a bill, a quotation for a sales
/// order, a sales order for an invoice. [supplierId] holds the supplier, or the
/// customer on sales documents.
class TradeEditorPage extends ConsumerStatefulWidget {
  const TradeEditorPage({super.key, required this.type, this.docId, this.fromId, this.supplierId});

  final TradeType type;
  final String? docId;
  final String? fromId;
  final String? supplierId;

  @override
  ConsumerState<TradeEditorPage> createState() => _TradeEditorPageState();
}

class _TradeEditorPageState extends ConsumerState<TradeEditorPage> {
  late final String _id = widget.docId ?? newUuid();
  String? _party;
  String? _date;
  String? _second;
  String? _warehouse;
  String? _branch;
  String? _department;
  String? _sourceId;
  String? _sourceNumber;
  String? _status;
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final List<_Line> _lines = [];
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _error;

  /// Quantity on hand per item in the chosen warehouse, refreshed on every build for sales documents.
  Map<String, double> _stock = const {};

  TradeType get t => widget.type;
  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    _date = _iso(DateTime.now());
    _party = widget.supplierId;
    if (_isEdit || widget.fromId != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _lines.add(_Line());
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaults());
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _applyDefaults() async {
    if (t.isReceipt || t.isOrder || t.isInvoice || t.isSalesOrder) {
      final wh = await ref.read(defaultWarehouseProvider.future);
      if (mounted && _warehouse == null) setState(() => _warehouse = wh);
    }
    // A quotation is valid for 30 days unless the date is changed.
    if (t.isQuotation && mounted && _second == null) setState(() => _second = _iso(DateTime.now().add(const Duration(days: 30))));
  }

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------
  Future<void> _load() async {
    try {
      final client = ref.read(supabaseProvider);
      final org = ref.read(activeMembershipProvider)?.orgId;
      if (org == null) throw 'No company selected.';
      final catalog = await ref.read(productCatalogProvider.future);
      Map<String, dynamic>? product(Object? id) {
        for (final p in catalog) {
          if (p['id'] == id) return p;
        }
        return null;
      }

      final lineSelect = 'id, line_no, product_id, description, quantity, unit_price, discount_amount, tax_rate_id, account_id, source_line_id';
      final newLines = <_Line>[];

      if (_isEdit) {
        final d = await client.from('trade_documents').select('*, trade_document_lines($lineSelect)').eq('id', _id).single();
        if (d['doc_type'] != t.key) throw 'This is not a ${t.label.toLowerCase()}.';
        if (d['status'] != 'draft' && d['status'] != 'rejected') throw 'Only draft or rejected documents can be edited.';
        _status = '${d['status']}';
        _party = d['party_id'] as String?;
        _date = d['doc_date'] as String?;
        _second = (t.hasPayments ? d['due_date'] : d['expected_date']) as String?;
        _warehouse = d['warehouse_id'] as String?;
        _branch = d['branch_id'] as String?;
        _department = d['department_id'] as String?;
        _sourceId = d['source_id'] as String?;
        _reference.text = (d['reference'] as String?) ?? '';
        _notes.text = (d['notes'] as String?) ?? '';
        final rows = List<Map<String, dynamic>>.from(d['trade_document_lines'] as List)..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));
        for (final r in rows) {
          final p = product(r['product_id']);
          newLines.add(_Line(
            productId: r['product_id'] as String?,
            description: (r['description'] as String?) ?? '',
            qty: _plain(r['quantity'] as num),
            price: _plain(r['unit_price'] as num),
            discount: (r['discount_amount'] as num) == 0 ? '' : _plain(r['discount_amount'] as num),
            taxRateId: r['tax_rate_id'] as String?,
            accountId: r['account_id'] as String?,
            sourceLineId: r['source_line_id'] as String?,
            sourceLabel: r['source_line_id'] == null ? null : (t.isBill ? 'Linked to a receipt or order line' : 'Linked to the earlier document'),
            isStock: isStockItem(p),
            locked: r['source_line_id'] != null && !t.isRequisition && !t.isSalesOrder,
          ));
        }
        if (_sourceId != null) {
          final s = await client.from('trade_documents').select('number').eq('id', _sourceId!).maybeSingle();
          _sourceNumber = s?['number'] as String?;
        }
      } else {
        final from = await client.from('trade_documents').select('*, trade_document_lines($lineSelect)').eq('id', widget.fromId!).single();
        final fromLines = List<Map<String, dynamic>>.from(from['trade_document_lines'] as List)..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));
        _sourceNumber = from['number'] as String?;

        if (t.isSalesOrder) {
          // Quotation to order: copy the items with their prices, discounts and tax.
          if (from['doc_type'] != 'sales_quotation' || (from['status'] != 'sent' && from['status'] != 'accepted')) {
            throw 'Only a sent or accepted quotation can be converted to a sales order.';
          }
          _sourceId = from['id'] as String;
          _party = from['party_id'] as String?;
          _branch = from['branch_id'] as String?;
          _warehouse = from['warehouse_id'] as String? ?? await ref.read(defaultWarehouseProvider.future);
          _reference.text = (from['reference'] as String?) ?? '';
          _notes.text = 'Raised from quotation ${from['number']}';
          for (final r in fromLines) {
            final p = product(r['product_id']);
            newLines.add(_Line(
              productId: r['product_id'] as String?,
              description: (r['description'] as String?) ?? '',
              qty: _plain(r['quantity'] as num),
              price: _plain(r['unit_price'] as num),
              discount: (r['discount_amount'] as num) == 0 ? '' : _plain(r['discount_amount'] as num),
              taxRateId: r['tax_rate_id'] as String?,
              sourceLineId: r['id'] as String,
              sourceLabel: 'From ${from['number']}',
              isStock: isStockItem(p),
            ));
          }
        } else if (t.isInvoice) {
          // Sales order to invoice: offer what is still to be invoiced.
          if (from['doc_type'] != 'sales_order' || (from['status'] != 'approved' && from['status'] != 'partial')) {
            throw 'An invoice can only be created from an approved sales order that is still open.';
          }
          _sourceId = from['id'] as String;
          _party = from['party_id'] as String?;
          _branch = from['branch_id'] as String?;
          _warehouse = from['warehouse_id'] as String? ?? await ref.read(defaultWarehouseProvider.future);
          _reference.text = (from['reference'] as String?) ?? '';
          final progress = await ref.read(salesOrderProgressProvider((doc: from['id'] as String, exclude: null)).future);
          for (final r in fromLines) {
            final p = product(r['product_id']);
            final pr = progress[r['id']];
            final ordered = (r['quantity'] as num).toDouble();
            final remaining = (pr?.ordered ?? ordered) - (pr?.committed ?? 0);
            if (remaining <= 0) continue;
            final discount = round2(remaining * ((r['discount_amount'] as num).toDouble() / (ordered == 0 ? 1 : ordered)));
            newLines.add(_Line(
              productId: r['product_id'] as String?,
              description: (r['description'] as String?) ?? '',
              qty: _plain(remaining),
              price: _plain(r['unit_price'] as num),
              discount: discount == 0 ? '' : _plain(discount),
              taxRateId: r['tax_rate_id'] as String?,
              sourceLineId: r['id'] as String,
              sourceLabel: 'From ${from['number']}',
              maxQty: remaining,
              isStock: isStockItem(p),
              locked: r['product_id'] != null,
            ));
          }
          if (newLines.isEmpty) throw 'Everything on this order has already been invoiced.';
        } else if (t.isOrder) {
          // Requisition to order: copy the items, the supplier is chosen next.
          if (from['doc_type'] != 'purchase_requisition' || (from['status'] != 'approved' && from['status'] != 'ordered')) {
            throw 'Only an approved requisition can be converted to an order.';
          }
          _sourceId = from['id'] as String;
          _party = widget.supplierId ?? from['party_id'] as String?;
          _branch = from['branch_id'] as String?;
          _department = from['department_id'] as String?;
          _second = from['expected_date'] as String?;
          _notes.text = 'Raised from requisition ${from['number']}';
          for (final r in fromLines) {
            final p = product(r['product_id']);
            newLines.add(_Line(
              productId: r['product_id'] as String?,
              description: (r['description'] as String?) ?? '',
              qty: _plain(r['quantity'] as num),
              price: _plain((r['unit_price'] as num?) ?? (p?['purchase_price'] as num?) ?? 0),
              taxRateId: p?['tax_rate_id'] as String?,
              sourceLineId: r['id'] as String,
              sourceLabel: 'From ${from['number']}',
              isStock: isStockItem(p),
            ));
          }
        } else if (t.isReceipt) {
          // Order to receipt: offer what is still to be received.
          if (from['doc_type'] != 'purchase_order' || (from['status'] != 'approved' && from['status'] != 'partial')) {
            throw 'Goods can only be received against an approved order that is still open.';
          }
          _sourceId = from['id'] as String;
          _party = from['party_id'] as String?;
          _warehouse = from['warehouse_id'] as String? ?? await ref.read(defaultWarehouseProvider.future);
          _branch = from['branch_id'] as String?;
          final progress = await ref.read(orderProgressProvider(from['id'] as String).future);
          for (final r in fromLines) {
            final p = product(r['product_id']);
            if (!isStockItem(p)) continue;
            final pr = progress[r['id']];
            final remaining = (pr?.ordered ?? (r['quantity'] as num).toDouble()) - (pr?.received ?? 0);
            if (remaining <= 0) continue;
            final qty = (r['quantity'] as num).toDouble();
            final net = round2(qty * (r['unit_price'] as num).toDouble()) - (r['discount_amount'] as num).toDouble();
            newLines.add(_Line(
              productId: r['product_id'] as String?,
              qty: _plain(remaining),
              price: _plain(qty == 0 ? 0 : (net / qty * 10000).roundToDouble() / 10000),
              sourceLineId: r['id'] as String,
              sourceLabel: 'From ${from['number']}',
              maxQty: remaining,
              isStock: true,
              locked: true,
            ));
          }
          if (newLines.isEmpty) throw 'Everything on this order has already been received.';
        } else if (t.isBill) {
          // Receipt to bill: bill what has been received and not billed yet.
          if (from['doc_type'] != 'goods_receipt' || from['status'] != 'posted') throw 'Bills are created from a posted goods receipt.';
          _party = from['party_id'] as String?;
          final unbilled = await ref.read(unbilledReceiptLinesProvider((org: org, party: _party!, excludeBill: null)).future);
          for (final r in unbilled) {
            if (r['receipt_id'] != from['id']) continue;
            newLines.add(_receiptLine(r));
          }
          if (newLines.isEmpty) throw 'Everything on this receipt has already been billed.';
        }
      }

      if (!mounted) return;
      setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..addAll(newLines.isEmpty ? [_Line()] : newLines);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e is String ? e : friendlyError(e);
        });
      }
    }
  }

  _Line _receiptLine(Map<String, dynamic> r) {
    final remaining = (r['remaining_qty'] as num).toDouble();
    final orderPrice = r['order_unit_price'] as num?;
    final perUnitDiscount = (r['order_discount_per_unit'] as num?)?.toDouble() ?? 0;
    final discount = round2(remaining * perUnitDiscount);
    return _Line(
      productId: r['product_id'] as String?,
      qty: _plain(remaining),
      price: _plain(orderPrice ?? (r['receipt_unit_cost'] as num)),
      discount: discount == 0 ? '' : _plain(discount),
      taxRateId: r['tax_rate_id'] as String?,
      sourceLineId: r['receipt_line_id'] as String,
      sourceLabel: 'Received on ${r['receipt_number']}',
      maxQty: remaining,
      isStock: true,
      locked: true,
    );
  }

  _Line _orderLine(Map<String, dynamic> r) {
    final remaining = (r['remaining_qty'] as num).toDouble();
    final discount = round2(remaining * ((r['discount_per_unit'] as num?)?.toDouble() ?? 0));
    return _Line(
      productId: r['product_id'] as String?,
      description: (r['description'] as String?) ?? '',
      qty: _plain(remaining),
      price: _plain(r['unit_price'] as num),
      discount: discount == 0 ? '' : _plain(discount),
      taxRateId: r['tax_rate_id'] as String?,
      sourceLineId: r['order_line_id'] as String,
      sourceLabel: 'Ordered on ${r['order_number']}',
      maxQty: remaining,
      locked: r['product_id'] != null,
    );
  }

  // ---------------------------------------------------------------------
  // Calculations
  // ---------------------------------------------------------------------
  double _rateFor(_Line l, Rows rates) {
    if (l.taxRateId == null) return 0;
    for (final r in rates) {
      if (r['id'] == l.taxRateId) return (r['rate'] as num).toDouble();
    }
    return 0;
  }

  LineCalc _calc(_Line l, Rows rates) => calcLine(
        qty: _num(l.qty),
        price: _num(l.price),
        discount: t.hasTaxAndDiscount ? _num(l.discount) : 0,
        taxRate: t.hasTaxAndDiscount ? _rateFor(l, rates) : 0,
      );

  void _onProduct(_Line l, String? id, Rows catalog, Map<String, Map<String, dynamic>> lastPrices) {
    Map<String, dynamic>? p;
    for (final r in catalog) {
      if (r['id'] == id) p = r;
    }
    setState(() {
      l.productId = id;
      l.isStock = isStockItem(p);
      if (p == null) return;
      if (_num(l.price) == 0) {
        final last = lastPrices[id];
        // Sales documents start from the selling price, purchases from the last cost.
        final price = t.isSales ? ((p['sales_price'] as num?) ?? 0) : ((last?['unit_cost'] as num?) ?? (p['purchase_price'] as num?) ?? 0);
        l.price.text = price == 0 ? '' : _plain(price);
      }
      if (t.hasTaxAndDiscount && l.taxRateId == null) l.taxRateId = p['tax_rate_id'] as String?;
      if (_num(l.qty) == 0) l.qty.text = '1';
    });
  }

  // ---------------------------------------------------------------------
  // Adding lines from earlier documents (bills)
  // ---------------------------------------------------------------------
  Future<void> _addFromDocuments() async {
    final m = ref.read(activeMembershipProvider);
    if (m == null || _party == null) {
      showToast(context, 'Choose the supplier first.', error: true);
      return;
    }
    final picked = await showAdaptiveForm<List<({bool receipt, Map<String, dynamic> row})>>(
      context,
      maxWidth: 760,
      builder: (_) => _SourcePicker(org: m.orgId, party: _party!, excludeBill: _isEdit ? _id : null, taken: {for (final l in _lines) if (l.sourceLineId != null) l.sourceLineId!}),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      if (_lines.length == 1 && _lines.first.productId == null && _lines.first.description.text.isEmpty && _num(_lines.first.qty) == 0) {
        _lines.removeAt(0).dispose();
      }
      for (final p in picked) {
        _lines.add(p.receipt ? _receiptLine(p.row) : _orderLine(p.row));
      }
    });
  }

  // ---------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------
  Future<void> _save(String then) async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() => _error = null);

    if (t.needsSupplier && _party == null) {
      setState(() => _error = 'Choose a ${t.partyLabel.toLowerCase()}.');
      return;
    }
    if (t.needsWarehouse && _warehouse == null) {
      setState(() => _error = 'Choose the warehouse that is receiving the goods.');
      return;
    }
    if (t.isInvoice && _warehouse == null && _lines.any((l) => l.isStock)) {
      setState(() => _error = 'Choose the warehouse the goods are issued from.');
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final text = l.description.text.trim();
      if (l.productId == null && text.isEmpty) {
        setState(() => _error = 'Line ${i + 1}: choose an item or write a description.');
        return;
      }
      if (_num(l.qty) <= 0) {
        setState(() => _error = 'Line ${i + 1}: enter a quantity greater than zero.');
        return;
      }
      if (t.isBill && !l.isStock && l.accountId == null) {
        setState(() => _error = 'Line ${i + 1}: choose the expense account.');
        return;
      }
      lines.add({
        'product_id': l.productId,
        'description': text.isEmpty ? null : text,
        'quantity': _num(l.qty),
        'unit_price': _num(l.price),
        'discount_amount': t.hasTaxAndDiscount ? _num(l.discount) : 0,
        'tax_rate_id': t.hasTaxAndDiscount ? l.taxRateId : null,
        'account_id': (t.isBill || t.isInvoice) && !l.isStock ? l.accountId : null,
        'source_line_id': l.sourceLineId,
      });
    }

    setState(() => _saving = true);
    try {
      final client = ref.read(supabaseProvider);
      if (t.isSales) {
        await client.rpc('save_sales_document', params: {
          'p_id': _id,
          'p_org': m.orgId,
          'p_type': t.key,
          'p_party': _party,
          'p_date': _date,
          'p_due': t.isInvoice ? _second : null,
          'p_expected': t.isInvoice ? null : _second,
          'p_branch': _branch,
          'p_warehouse': _warehouse,
          'p_reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'p_source': _sourceId,
          'p_lines': lines,
        });
      } else {
        await client.rpc('save_purchase_document', params: {
          'p_id': _id,
          'p_org': m.orgId,
          'p_type': t.key,
          'p_party': _party,
          'p_date': _date,
          'p_due': t.isBill ? _second : null,
          'p_expected': t.isBill ? null : _second,
          'p_branch': _branch,
          'p_warehouse': _warehouse,
          'p_department': _department,
          'p_reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'p_source': _sourceId,
          'p_lines': lines,
        });
      }
      var done = 'Saved as draft';
      if (then == 'submit') {
        await client.rpc(t.isSales ? 'submit_sales_document' : 'submit_document', params: {'p_id': _id});
        done = 'Submitted for approval';
      } else if (then == 'send') {
        await client.rpc('mark_quotation_sent', params: {'p_id': _id});
        done = 'Quotation marked as sent';
      } else if (then == 'post') {
        if (t.isInvoice) {
          if (!mounted) return;
          final posted = await postSalesInvoice(context, ref, _id);
          done = posted ? 'Invoice approved and posted' : 'Saved as a draft. The invoice was not posted.';
        } else {
          await client.rpc(t.isReceipt ? 'post_goods_receipt' : 'post_supplier_bill', params: {'p_id': _id});
          done = t.isReceipt ? 'Receipt posted. Stock has been updated.' : 'Bill approved and posted';
        }
      }
      invalidateTrade(ref);
      if (!mounted) return;
      showToast(context, done);
      context.go(t.detailPath(_id));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!t.canView(perms)) return const NoAccessView();
    if (!t.can(perms, PermAction.create) && !t.can(perms, PermAction.edit)) return const NoAccessView();
    if (_loading) return const LoadingView();
    if (_loadError != null) {
      return EmptyState(icon: Icons.info_outline_rounded, title: 'This form cannot be opened', message: _loadError, actionLabel: 'Back to ${t.plural.toLowerCase()}', onAction: () => context.go(t.path));
    }

    final catalog = ref.watch(productCatalogProvider).valueOrNull ?? <Map<String, dynamic>>[];
    final rates = ref.watch(t.isSales ? salesTaxRatesProvider : purchaseTaxRatesProvider).valueOrNull ?? <Map<String, dynamic>>[];
    final lastPrices = ref.watch(lastPurchasePricesProvider).valueOrNull ?? const <String, Map<String, dynamic>>{};
    // The party list is customers on sales documents and suppliers on purchases.
    final suppliers = ref.watch(t.isSales ? customerOptions : supplierOptions).valueOrNull ?? const <Option>[];
    final warehouses = ref.watch(warehouseOptions).valueOrNull ?? const <Option>[];
    final departments = ref.watch(departmentOptions).valueOrNull ?? const <Option>[];
    final branches = ref.watch(branchOptions).valueOrNull ?? const <Option>[];
    final accounts = ref.watch(t.isInvoice ? incomeHeadOptions : billAccountOptions).valueOrNull ?? const <Option>[];

    // Stock on hand, so a sale can be checked against what is in the warehouse.
    if (t.isInvoice || t.isSalesOrder) {
      final rows = ref.watch(stockOnHandProvider((org: m.orgId, warehouse: _warehouse))).valueOrNull ?? <Map<String, dynamic>>[];
      final onHand = <String, double>{};
      for (final r in rows) {
        onHand['${r['product_id']}'] = (onHand['${r['product_id']}'] ?? 0) + ((r['quantity'] as num?)?.toDouble() ?? 0);
      }
      _stock = onHand;
    }
    final credit = t.isInvoice && _party != null ? ref.watch(partySummaryProvider((org: m.orgId, party: _party!))).valueOrNull : null;

    final productOptions = [
      for (final p in catalog)
        if (!t.isReceipt || isStockItem(p)) Option(p['id'] as String, '${p['sku']}  ${p['name']}'),
    ];

    var sub = 0.0, disc = 0.0, tax = 0.0;
    for (final l in _lines) {
      final c = _calc(l, rates);
      sub += c.gross;
      disc += c.discount;
      tax += c.tax;
    }
    final total = sub - disc + tax;

    final canSubmitOrPost = t.can(perms, PermAction.approve);
    final fieldWidth = context.isMobile ? double.infinity : 330.0;
    final partyLocked = _lines.any((l) => l.sourceLineId != null && !t.isRequisition) || (t.isReceipt && _sourceId != null);
    final showSupplier = t.needsSupplier || perms.canView(Modules.purchase);

    Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

    return AppPage(
      title: _isEdit ? 'Edit ${t.label.toLowerCase()}' : 'New ${t.label.toLowerCase()}',
      subtitle: _sourceNumber != null && !_isEdit ? 'Created from $_sourceNumber' : t.subtitle,
      maxWidth: 1120,
      children: [
        if (_status == 'rejected')
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: const Text('This document was rejected. Saving it returns it to draft so you can resubmit.', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        SectionCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (showSupplier)
                field(SearchSelectField(
                  label: t.needsSupplier ? t.partyLabel : 'Preferred supplier',
                  required: t.needsSupplier,
                  hint: t.needsSupplier ? 'Select ${t.partyLabel.toLowerCase()}' : 'Optional',
                  clearable: !t.needsSupplier,
                  enabled: !partyLocked,
                  options: suppliers,
                  value: _party,
                  onChanged: (v) => setState(() => _party = v),
                )),
              field(AppDateField(label: t.dateLabel, required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
              if (t.secondDateLabel != null) field(AppDateField(label: t.secondDateLabel!, value: _second, onChanged: (v) => setState(() => _second = v))),
              if (t.needsWarehouse || t.isOrder || t.isInvoice || t.isSalesOrder)
                field(SearchSelectField(
                  label: t.isOrder ? 'Deliver to' : (t.isInvoice ? 'Issue stock from' : (t.isSalesOrder ? 'Deliver from' : 'Receiving warehouse')),
                  required: t.needsWarehouse,
                  clearable: !t.needsWarehouse,
                  hint: t.isOrder || t.isSalesOrder ? 'Optional' : (t.isInvoice ? 'Needed for stock items' : 'Select warehouse'),
                  options: warehouses,
                  value: _warehouse,
                  onChanged: (v) => setState(() => _warehouse = v),
                )),
              if (t.isRequisition)
                field(SearchSelectField(label: 'Department', hint: 'Optional', clearable: true, options: departments, value: _department, onChanged: (v) => setState(() => _department = v))),
              if (branches.length > 1)
                field(SearchSelectField(label: 'Branch', hint: 'Optional', clearable: true, options: branches, value: _branch, onChanged: (v) => setState(() => _branch = v))),
              if (!t.isRequisition) field(AppTextField(controller: _reference, label: t.referenceLabel)),
            ],
          ),
              if (t.isInvoice) ...[
                const SizedBox(height: 8),
                Text("Leave the due date empty to use the customer's payment terms.", style: AppText.small),
              ],
            ],
          ),
        ),
        if (credit != null && credit['credit_limit'] != null) ...[const SizedBox(height: 16), _creditBanner(credit, total, m.currency)],
        const SizedBox(height: 16),
        SectionCard(
          title: 'Items',
          subtitle: t.isBill
              ? 'Stock items are billed from goods receipts. Services and other costs need an expense account.'
              : (t.isInvoice ? 'Stock items are issued from the warehouse at average cost when the invoice is posted. Services and other income can use their own income account.' : null),
          trailing: t.isBill
              ? AppButton(label: 'Add from receipts or orders', icon: Icons.playlist_add_rounded, kind: AppButtonKind.secondary, compact: true, onPressed: _addFromDocuments)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _lines.length; i++) ...[
                KeyedSubtree(
                  key: ObjectKey(_lines[i]),
                  child: _lineEditor(i, productOptions, catalog, rates, accounts, lastPrices, m.currency),
                ),
                const SizedBox(height: 12),
              ],
              if (!t.isBill || _lines.isEmpty || !_lines.every((l) => l.locked))
                AppButton(label: 'Add line', icon: Icons.add_rounded, kind: AppButtonKind.ghost, compact: true, onPressed: () => setState(() => _lines.add(_Line()))),
              if (t.hasPrices || t.isReceipt) ...[
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      children: [
                        _totalRow('Subtotal', sub, m.currency),
                        if (t.hasTaxAndDiscount && disc > 0) _totalRow('Discount', -disc, m.currency),
                        if (t.hasTaxAndDiscount && tax > 0) _totalRow('Tax', tax, m.currency),
                        const SizedBox(height: 6),
                        _totalRow(t.isRequisition ? 'Estimated total' : 'Total', total, m.currency, strong: true),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Notes and documents',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(controller: _notes, label: t.isRequisition ? 'Reason for the request' : 'Notes', maxLines: 3),
              const SizedBox(height: 16),
              AttachmentsPanel(entityType: t.key, entityId: _id),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(label: 'Save draft', kind: AppButtonKind.secondary, loading: _saving, onPressed: () => _save('draft')),
            if (t.usesApproval) AppButton(label: 'Save and submit for approval', loading: _saving, onPressed: () => _save('submit')),
            if (t.isQuotation) AppButton(label: 'Save and mark as sent', loading: _saving, onPressed: () => _save('send')),
            if (t.isReceipt && canSubmitOrPost) AppButton(label: 'Save and post receipt', loading: _saving, onPressed: () => _save('post')),
            if ((t.isBill || t.isInvoice) && canSubmitOrPost) AppButton(label: 'Save, approve and post', kind: AppButtonKind.secondary, loading: _saving, onPressed: () => _save('post')),
            AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: _saving ? null : () => context.go(_isEdit ? t.detailPath(_id) : t.path)),
          ],
        ),
      ],
    );
  }

  /// Shows the customer's credit limit and how much room is left, and warns when this invoice would exceed it.
  Widget _creditBanner(Map<String, dynamic> s, double total, String currency) {
    final limit = (s['credit_limit'] as num).toDouble();
    final available = (s['available_credit'] as num?)?.toDouble();
    if (limit <= 0 || available == null) return const SizedBox.shrink();
    final over = total > available;
    final fg = over ? AppColors.warning : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: over ? AppColors.warningSoft : AppColors.infoSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(children: [
        Icon(over ? Icons.warning_amber_rounded : Icons.speed_outlined, size: 19, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Credit limit ${Fmt.money(limit, currency: currency)}. ${Fmt.money(available, currency: currency)} is still available.'
            '${over ? ' This invoice is ${Fmt.money(total - available, currency: currency)} over the limit. You will be asked to confirm before it is posted.' : ''}',
            style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _totalRow(String label, double value, String currency, {bool strong = false}) {
    final style = strong ? AppText.h3 : AppText.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(Fmt.money(value, currency: currency), style: strong ? style : AppText.bodyStrong)]),
    );
  }

  Widget _numField(TextEditingController c, String label, {String? hint, bool enabled = true}) => AppTextField(
        controller: c,
        label: label,
        hint: hint,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      );

  Widget _lineEditor(int i, List<Option> productOptions, Rows catalog, Rows rates, List<Option> accounts, Map<String, Map<String, dynamic>> lastPrices, String currency) {
    final l = _lines[i];
    final calc = _calc(l, rates);
    final taxOptions = [for (final r in rates) DropdownMenuItem<String?>(value: r['id'] as String, child: Text('${r['name']} (${r['rate']}%)'))];

    final item = SearchSelectField(
      label: 'Item',
      hint: t.isReceipt ? 'Select item' : 'Select item or type a description below',
      clearable: !t.isReceipt && !l.locked,
      enabled: !l.locked,
      options: productOptions,
      value: l.productId,
      onChanged: (v) => _onProduct(l, v, catalog, lastPrices),
    );
    final desc = AppTextField(controller: l.description, label: l.productId == null ? 'Description' : 'Details', required: l.productId == null, enabled: !(l.locked && l.productId != null && t.isReceipt));
    final qty = _numField(l.qty, 'Quantity', hint: l.maxQty == null ? null : 'Up to ${qtyText(l.maxQty)}');
    final price = _numField(l.price, t.isReceipt ? 'Unit cost' : (t.isRequisition ? 'Estimated price' : 'Unit price'));
    final discount = _numField(l.discount, 'Discount');
    final tax = AppDropdown<String?>(
      label: 'Tax',
      value: l.taxRateId,
      items: [const DropdownMenuItem<String?>(value: null, child: Text('No tax')), ...taxOptions],
      onChanged: (v) => setState(() => l.taxRateId = v),
    );
    final account = SearchSelectField(
      label: t.isInvoice ? 'Income account' : 'Expense account',
      required: t.isBill,
      hint: t.isInvoice ? 'Default: Sales revenue' : 'Select',
      clearable: t.isInvoice,
      options: accounts,
      value: l.accountId,
      onChanged: (v) => setState(() => l.accountId = v),
    );
    final remove = IconButton(
      tooltip: 'Remove line',
      onPressed: _lines.length <= 1 ? null : () => setState(() => _lines.removeAt(i).dispose()),
      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
    );
    final showAmounts = t.hasPrices || t.isReceipt;
    final needsAccount = (t.isBill || t.isInvoice) && !l.isStock;
    // Stock check for sales: how much is on hand against what is being sold.
    String? stockNote;
    var stockShort = false;
    if ((t.isInvoice || t.isSalesOrder) && l.isStock && l.productId != null) {
      final onHand = _stock[l.productId!] ?? 0;
      stockShort = _num(l.qty) > onHand;
      stockNote = stockShort ? 'Only ${qtyText(onHand)} in stock' : '${qtyText(onHand)} in stock';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFA), borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: AppColors.border)),
      child: LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= 760;
          final children = <Widget>[];
          if (wide) {
            children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: item),
              const SizedBox(width: 12),
              SizedBox(width: 110, child: qty),
              if (showAmounts) ...[const SizedBox(width: 12), SizedBox(width: 130, child: price)],
              if (t.hasTaxAndDiscount) ...[const SizedBox(width: 12), SizedBox(width: 110, child: discount)],
              remove,
            ]));
            children.add(const SizedBox(height: 12));
            children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!t.isReceipt) Expanded(flex: 5, child: desc) else const Spacer(flex: 5),
              if (t.hasTaxAndDiscount) ...[const SizedBox(width: 12), SizedBox(width: 200, child: tax)],
              if (needsAccount) ...[const SizedBox(width: 12), SizedBox(width: 260, child: account)],
            ]));
          } else {
            children.addAll([
              item,
              if (!t.isReceipt) ...[const SizedBox(height: 12), desc],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: qty),
                if (showAmounts) ...[const SizedBox(width: 12), Expanded(child: price)],
              ]),
              if (t.hasTaxAndDiscount) ...[
                const SizedBox(height: 12),
                Row(children: [Expanded(child: discount), const SizedBox(width: 12), Expanded(child: tax)]),
              ],
              if (needsAccount) ...[const SizedBox(height: 12), account],
              Align(alignment: Alignment.centerRight, child: remove),
            ]);
          }
          children.add(const SizedBox(height: 8));
          children.add(Row(children: [
            if (l.sourceLabel != null)
              Expanded(child: Text(l.sourceLabel!, style: AppText.small))
            else
              const Spacer(),
            if (stockNote != null)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(stockNote, style: AppText.small.copyWith(color: stockShort && t.isInvoice ? AppColors.danger : AppColors.textMuted, fontWeight: stockShort && t.isInvoice ? FontWeight.w600 : FontWeight.w400)),
              ),
            if (showAmounts) Text('Line total ${Fmt.money(calc.total, currency: currency)}', style: AppText.bodyStrong),
          ]));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        },
      ),
    );
  }
}

/// Lets a bill pull in lines from posted receipts and from orders.
class _SourcePicker extends ConsumerStatefulWidget {
  const _SourcePicker({required this.org, required this.party, required this.excludeBill, required this.taken});

  final String org;
  final String party;
  final String? excludeBill;
  final Set<String> taken;

  @override
  ConsumerState<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends ConsumerState<_SourcePicker> {
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) {
    final key = (org: widget.org, party: widget.party, excludeBill: widget.excludeBill);
    final receipts = ref.watch(unbilledReceiptLinesProvider(key));
    final orders = ref.watch(unbilledOrderLinesProvider(key));

    Widget section(String title, String empty, AsyncValue<Rows> async, String idKey, String Function(Map<String, dynamic>) name, String Function(Map<String, dynamic>) doc) {
      return async.when(
        loading: () => const LoadingView(),
        error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text(friendlyError(e), style: AppText.body)),
        data: (rows) {
          final available = rows.where((r) => !widget.taken.contains(r[idKey])).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(title, style: AppText.h3)),
              if (available.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(empty, style: AppText.body))
              else
                for (final r in available)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _chosen.contains(r[idKey]),
                    onChanged: (v) => setState(() => v == true ? _chosen.add(r[idKey] as String) : _chosen.remove(r[idKey])),
                    title: Text(name(r), style: AppText.bodyStrong.copyWith(fontSize: 14)),
                    subtitle: Text('${doc(r)}, ${qtyText(r['remaining_qty'] as num)} left to bill', style: AppText.small),
                  ),
            ],
          );
        },
      );
    }

    return FormShell(
      title: 'Add from receipts or orders',
      subtitle: 'Choose what this bill covers.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          AppButton(
            label: _chosen.isEmpty ? 'Add' : 'Add ${_chosen.length} line${_chosen.length == 1 ? '' : 's'}',
            onPressed: _chosen.isEmpty
                ? null
                : () {
                    final out = <({bool receipt, Map<String, dynamic> row})>[];
                    for (final r in receipts.valueOrNull ?? <Map<String, dynamic>>[]) {
                      if (_chosen.contains(r['receipt_line_id'])) out.add((receipt: true, row: r));
                    }
                    for (final r in orders.valueOrNull ?? <Map<String, dynamic>>[]) {
                      if (_chosen.contains(r['order_line_id'])) out.add((receipt: false, row: r));
                    }
                    Navigator.of(context).pop(out);
                  },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          section('Goods received, not yet billed', 'Nothing received from this supplier is waiting to be billed.', receipts, 'receipt_line_id',
              (r) => '${r['product_name']}', (r) => '${r['receipt_number']}'),
          const Divider(),
          section('Services and other order lines', 'No open service lines on this supplier\'s orders.', orders, 'order_line_id',
              (r) => '${r['description'] ?? 'Line'}', (r) => '${r['order_number']}'),
        ],
      ),
    );
  }
}
