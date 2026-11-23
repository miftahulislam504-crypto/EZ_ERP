import 'package:flutter/material.dart';

import '../../core/permissions/permissions.dart';

/// Rounds to two decimals the way the database does (half away from zero).
double round2(double v) => (v * 100).roundToDouble() / 100;

/// Amounts of one document line. The server recalculates these on save, so
/// this only drives what the person sees while typing.
class LineCalc {
  const LineCalc({required this.gross, required this.discount, required this.net, required this.tax});

  final double gross;
  final double discount;
  final double net;
  final double tax;

  double get total => net + tax;
}

LineCalc calcLine({required double qty, required double price, double discount = 0, double taxRate = 0}) {
  final gross = round2(qty * price);
  final disc = discount < 0 ? 0.0 : (round2(discount) > gross ? gross : round2(discount));
  final net = gross - disc;
  return LineCalc(gross: gross, discount: disc, net: net, tax: round2(net * taxRate / 100));
}

/// Describes one purchase document type: where it lives in the app, which
/// permission governs it and which fields its form shows.
class TradeType {
  const TradeType({
    required this.key,
    required this.label,
    required this.plural,
    required this.path,
    required this.module,
    required this.icon,
    required this.subtitle,
    required this.referenceLabel,
    this.needsSupplier = true,
    this.hasPrices = true,
    this.hasTaxAndDiscount = true,
    this.needsWarehouse = false,
    this.usesApproval = true,
    this.dateLabel = 'Date',
    this.secondDateLabel,
    this.filters = const [],
  });

  /// Value of trade_documents.doc_type.
  final String key;
  final String label;
  final String plural;
  final String path;
  final String module;
  final IconData icon;
  final String subtitle;
  final String referenceLabel;
  /// Whether the document needs a party: a supplier on purchases, a customer on sales.
  final bool needsSupplier;
  final bool hasPrices;
  final bool hasTaxAndDiscount;
  final bool needsWarehouse;
  final bool usesApproval;
  final String dateLabel;

  /// Label of the second date: needed by, expected delivery or due date.
  final String? secondDateLabel;
  final List<TradeFilter> filters;

  bool get isRequisition => key == 'purchase_requisition';
  bool get isOrder => key == 'purchase_order';
  bool get isReceipt => key == 'goods_receipt';
  bool get isBill => key == 'supplier_bill';
  bool get isQuotation => key == 'sales_quotation';
  bool get isSalesOrder => key == 'sales_order';
  bool get isInvoice => key == 'sales_invoice';

  /// Quotations, sales orders and sales invoices (the customer side).
  bool get isSales => isQuotation || isSalesOrder || isInvoice;

  /// Posted bills and invoices are settled by payments.
  bool get hasPayments => isBill || isInvoice;

  /// What the party on this document is called: Customer or Supplier.
  String get partyLabel => isSales ? 'Customer' : 'Supplier';
  String get partyRole => isSales ? 'customer' : 'supplier';

  /// Whether the person may see, create, edit and approve this document type.
  bool canView(PermissionSet p) => isReceipt ? (p.canView(Modules.purchase) || p.canView(Modules.inventory)) : p.canView(module);

  bool can(PermissionSet p, PermAction a) {
    if (isReceipt) {
      if (a == PermAction.approve) return p.can(Modules.inventory, PermAction.edit) || p.can(Modules.purchase, PermAction.approve);
      return p.can(Modules.inventory, a) || p.can(Modules.purchase, a);
    }
    return p.can(module, a);
  }

  String get newPath => '$path/new';
  String detailPath(String id) => '$path/$id';
  String editPath(String id) => '$path/$id/edit';
}

class TradeFilter {
  const TradeFilter(this.label, [this.statuses = const [], this.paymentState]);
  final String label;

  /// Empty means every status.
  final List<String> statuses;

  /// For posted bills and invoices: 'open' keeps those with an amount still to pay,
  /// 'overdue' keeps those past their due date.
  final String? paymentState;
}

const requisitionType = TradeType(
  key: 'purchase_requisition',
  label: 'Purchase requisition',
  plural: 'Requisitions',
  path: '/purchase/requisitions',
  module: Modules.requisitions,
  icon: Icons.playlist_add_check_outlined,
  subtitle: 'Ask for items or services. Approved requisitions become purchase orders.',
  referenceLabel: 'Reference',
  needsSupplier: false,
  hasTaxAndDiscount: false,
  secondDateLabel: 'Needed by',
  filters: [
    TradeFilter('All'),
    TradeFilter('Awaiting approval', ['pending']),
    TradeFilter('Approved', ['approved']),
    TradeFilter('Ordered', ['ordered']),
    TradeFilter('Draft', ['draft', 'rejected']),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const orderType = TradeType(
  key: 'purchase_order',
  label: 'Purchase order',
  plural: 'Purchase orders',
  path: '/purchase/orders',
  module: Modules.purchase,
  icon: Icons.shopping_bag_outlined,
  subtitle: 'Orders sent to suppliers. Track what is still to be received and billed.',
  referenceLabel: 'Supplier quotation or reference',
  secondDateLabel: 'Expected delivery',
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft', 'rejected']),
    TradeFilter('Awaiting approval', ['pending']),
    TradeFilter('Open', ['approved', 'partial']),
    TradeFilter('Received', ['received', 'closed']),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const receiptType = TradeType(
  key: 'goods_receipt',
  label: 'Goods receipt',
  plural: 'Goods receipts',
  path: '/purchase/receipts',
  module: Modules.purchase,
  icon: Icons.move_to_inbox_outlined,
  subtitle: 'Goods received from suppliers. Posting a receipt adds stock and books the value.',
  referenceLabel: 'Delivery note number',
  hasTaxAndDiscount: false,
  needsWarehouse: true,
  usesApproval: false,
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft']),
    TradeFilter('Posted', ['posted']),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const billType = TradeType(
  key: 'supplier_bill',
  label: 'Supplier bill',
  plural: 'Supplier bills',
  path: '/purchase/bills',
  module: Modules.purchase,
  icon: Icons.description_outlined,
  subtitle: 'Bills from suppliers, matched against goods received. Posting creates the payable.',
  referenceLabel: 'Supplier invoice number',
  secondDateLabel: 'Due date',
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft', 'rejected']),
    TradeFilter('Awaiting approval', ['pending']),
    TradeFilter('Approved', ['approved']),
    TradeFilter('Posted', ['posted']),
    TradeFilter('Unpaid', ['posted'], 'open'),
    TradeFilter('Overdue', ['posted'], 'overdue'),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const quotationType = TradeType(
  key: 'sales_quotation',
  label: 'Quotation',
  plural: 'Quotations',
  path: '/sales/quotations',
  module: Modules.sales,
  icon: Icons.request_quote_outlined,
  subtitle: 'Prices offered to customers. An accepted quotation converts into a sales order.',
  referenceLabel: 'Customer reference',
  usesApproval: false,
  dateLabel: 'Quotation date',
  secondDateLabel: 'Valid until',
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft']),
    TradeFilter('Sent', ['sent']),
    TradeFilter('Accepted', ['accepted']),
    TradeFilter('Converted', ['converted']),
    TradeFilter('Declined', ['rejected']),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const salesOrderType = TradeType(
  key: 'sales_order',
  label: 'Sales order',
  plural: 'Sales orders',
  path: '/sales/orders',
  module: Modules.sales,
  icon: Icons.shopping_cart_outlined,
  subtitle: 'Confirmed customer orders. Track what is still to be invoiced.',
  referenceLabel: 'Customer PO number',
  secondDateLabel: 'Delivery date',
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft', 'rejected']),
    TradeFilter('Awaiting approval', ['pending']),
    TradeFilter('Open', ['approved', 'partial']),
    TradeFilter('Invoiced', ['invoiced', 'closed']),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const invoiceType = TradeType(
  key: 'sales_invoice',
  label: 'Sales invoice',
  plural: 'Sales invoices',
  path: '/sales/invoices',
  module: Modules.sales,
  icon: Icons.receipt_long_outlined,
  subtitle: 'Invoices to customers. Posting creates the receivable, books the sale and issues stock.',
  referenceLabel: 'Customer PO or reference',
  dateLabel: 'Invoice date',
  secondDateLabel: 'Due date',
  filters: [
    TradeFilter('All'),
    TradeFilter('Draft', ['draft', 'rejected']),
    TradeFilter('Awaiting approval', ['pending']),
    TradeFilter('Approved', ['approved']),
    TradeFilter('Posted', ['posted']),
    TradeFilter('Unpaid', ['posted'], 'open'),
    TradeFilter('Overdue', ['posted'], 'overdue'),
    TradeFilter('Cancelled', ['cancelled']),
  ],
);

const tradeTypes = <String, TradeType>{
  'purchase_requisition': requisitionType,
  'purchase_order': orderType,
  'goods_receipt': receiptType,
  'supplier_bill': billType,
  'sales_quotation': quotationType,
  'sales_order': salesOrderType,
  'sales_invoice': invoiceType,
};

/// Profile page of a customer or supplier.
String partyProfilePath(String role, String id) => role == 'customer' ? '/sales/customers/$id' : '/purchase/suppliers/$id';

/// Route for any document, used by notifications and related-document links.
String? tradeDocumentPath(String docType, String id) {
  final t = tradeTypes[docType];
  return t?.detailPath(id);
}

const adjustmentReasons = <String, String>{
  'opening_stock': 'Opening stock',
  'count_correction': 'Count correction',
  'damaged': 'Damaged stock',
  'expired': 'Expired stock',
  'lost': 'Lost stock',
  'issue': 'Internal issue',
  'other': 'Other',
};

/// Reasons that can only take stock out, or only bring it in.
const reducingReasons = {'damaged', 'expired', 'lost', 'issue'};
const increasingReasons = {'opening_stock'};

const movementLabels = <String, String>{
  'purchase_receipt': 'Goods receipt',
  'purchase_return': 'Purchase return',
  'sales_issue': 'Sales issue',
  'sales_return': 'Sales return',
  'adjustment_in': 'Adjustment (in)',
  'adjustment_out': 'Adjustment (out)',
  'transfer_in': 'Transfer in',
  'transfer_out': 'Transfer out',
  'reversal': 'Reversal',
};

/// Quantity text without trailing zeros: 60.000 becomes 60, 2.500 becomes 2.5.
String qtyText(num? v) {
  if (v == null) return '--';
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}
